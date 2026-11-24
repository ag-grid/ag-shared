#!/usr/bin/env bash

##########################################################################################
## Runs one read-only Codex security review per shard in $SHARDS_FILE.
##
## For each shard it writes, under $OUT_DIR:
##   <shard>.json   the findings, matching findings.schema.json (only when the review succeeds)
##   status.jsonl   one {"shard", "status", "paths"} line per shard
##                  (status: ok | failed | timeout | invalid-output | out-of-time)
##
## Up to $PARALLEL_SHARDS shards run at once. Each review mostly waits on the Codex API, so this
## cuts the run to roughly the slowest shards rather than the sum of all of them.
##
## A shard that Codex rate-limits is retried up to $RATE_LIMIT_RETRIES times, waiting
## $RATE_LIMIT_BACKOFF_SECONDS, then twice that, and so on (plus up to 30s of jitter so retrying
## shards don't line up again). Running out of quota (insufficient_quota) is not retried: waiting
## won't fix it.
##
## All shards share a budget of $REVIEW_BUDGET_MINUTES, so the job still has time to report what
## finished before it hits its own timeout. Each shard gets at most $SHARD_TIMEOUT_MINUTES or what
## is left of the budget, and shards with less than 5 minutes left are not started (out-of-time).
##
## Nothing Codex produces is printed: the repo may be public, and so is this log. stdout and
## stderr go to files under $OUT_DIR, and on failure only a canned classification is printed.
##
## Exits non-zero only for configuration errors. Failed shards are listed in the
## failed_shards step output so the report still runs and the action fails afterwards.
##########################################################################################

set -euo pipefail

: "${SHARDS_FILE:?}" "${PROMPT_FILE:?}" "${SCHEMA_FILE:?}" "${OUT_DIR:?}" "${CODEX_HOME:?}"

for f in "$SHARDS_FILE" "$PROMPT_FILE" "$SCHEMA_FILE"
do
    if [ ! -f "$f" ]
    then
        echo "::error::File not found: $f"
        exit 1
    fi
done

mkdir -p "$OUT_DIR" "$CODEX_HOME"
: > "$OUT_DIR/status.jsonl"

CONTEXT=$(jq -r '.context // ""' "$SHARDS_FILE")
SHARD_NAMES=$(jq -r '.shards[].name' "$SHARDS_FILE")

if [ -n "${SHARD_FILTER:-}" ] && ! grep -qxF "$SHARD_FILTER" <<< "$SHARD_NAMES"
then
    echo "::error::No shard named [$SHARD_FILTER] in $SHARDS_FILE. Shards: $(echo $SHARD_NAMES)"
    exit 1
fi

CODEX_ARGS=(
    --sandbox read-only
    --ephemeral
    --skip-git-repo-check
    --output-schema "$SCHEMA_FILE"
    -c "model_reasoning_effort=\"${REASONING_EFFORT:-high}\""
    -c 'model_reasoning_summary="none"'
    -c 'shell_environment_policy.inherit="core"'
)
if [ -n "${MODEL:-}" ]
then
    CODEX_ARGS+=(-m "$MODEL")
fi

# Each shard writes its own status file, since shards finish in any order. They are combined into
# status.jsonl in shard order at the end.
record_status() {
    jq -cn --arg shard "$1" --arg status "$2" --argjson paths "$3" '{shard: $shard, status: $status, paths: $paths}' > "$OUT_DIR/$1.status.json"
}

SHARD_TIMEOUT_MINUTES=${SHARD_TIMEOUT_MINUTES:-45}
REVIEW_BUDGET_MINUTES=${REVIEW_BUDGET_MINUTES:-300}
PARALLEL_SHARDS=${PARALLEL_SHARDS:-3}
RATE_LIMIT_RETRIES=${RATE_LIMIT_RETRIES:-3}
RATE_LIMIT_BACKOFF_SECONDS=${RATE_LIMIT_BACKOFF_SECONDS:-60}
MIN_SHARD_MINUTES=5

# A zero, negative or non-numeric value would hang the scheduler or break the time budget
for setting in SHARD_TIMEOUT_MINUTES REVIEW_BUDGET_MINUTES PARALLEL_SHARDS
do
    if ! [[ "${!setting}" =~ ^[1-9][0-9]*$ ]]
    then
        echo "::error::$setting must be a positive integer, got [${!setting}]"
        exit 1
    fi
done
for setting in RATE_LIMIT_RETRIES RATE_LIMIT_BACKOFF_SECONDS
do
    if ! [[ "${!setting}" =~ ^[0-9]+$ ]]
    then
        echo "::error::$setting must be a non-negative integer, got [${!setting}]"
        exit 1
    fi
done

# Classify a failed Codex run from its log. The log is never printed (see the header).
# Quota is checked first: an exhausted quota is also reported as a 429.
log_says_quota() { grep -qiE "(insufficient_quota|exceeded your current quota)" "$1"; }
log_says_rate_limited() { grep -qiE "(rate.?limit|429|too many requests)" "$1"; }

# Reviews one shard. Runs in the background, so it reports only through its status file.
review_shard() {
    local name=$1 shard focus p paths paths_json prompt_file output_file log_file remaining shard_minutes start exit_code duration
    local attempt=0 delay

    shard=$(jq -c --arg name "$name" '.shards[] | select(.name == $name)' "$SHARDS_FILE")
    focus=$(jq -r '.focus // ""' <<< "$shard")

    # Only review paths that exist on this branch
    paths=()
    while IFS= read -r p
    do
        if [ -e "$p" ]
        then
            paths+=("$p")
        else
            echo "::warning::Shard [$name]: path $p does not exist - skipping it"
        fi
    done < <(jq -r '.paths[]' <<< "$shard")

    if [ "${#paths[@]}" -eq 0 ]
    then
        echo "::error::Shard [$name] has no existing paths"
        record_status "$name" failed '[]'
        return
    fi
    paths_json=$(printf '%s\n' "${paths[@]}" | jq -R . | jq -cs .)

    prompt_file="$OUT_DIR/$name.prompt.md"
    output_file="$OUT_DIR/$name.json"
    log_file="$OUT_DIR/$name.log"

    {
        cat "$PROMPT_FILE"
        echo
        echo "## Product context"
        echo
        echo "$CONTEXT"
        echo
        echo "## Scope for this review"
        echo
        echo "Review only these paths (relative to the repository root, which is your working directory):"
        echo
        printf -- '- `%s`\n' "${paths[@]}"
        if [ -n "$focus" ]
        then
            echo
            echo "Additional focus for this area: $focus"
        fi
    } > "$prompt_file"

    remaining=$(( REVIEW_BUDGET_MINUTES - SECONDS / 60 ))
    if [ "$remaining" -lt "$MIN_SHARD_MINUTES" ]
    then
        echo "::error::Shard [$name] not started: the ${REVIEW_BUDGET_MINUTES}-minute review budget is used up"
        record_status "$name" out-of-time "$paths_json"
        return
    fi

    echo "Reviewing shard [$name]: ${paths[*]}"
    start=$SECONDS
    mkdir -p "$CODEX_HOME/$name"

    while true
    do
        remaining=$(( REVIEW_BUDGET_MINUTES - SECONDS / 60 ))
        shard_minutes=$(( remaining < SHARD_TIMEOUT_MINUTES ? remaining : SHARD_TIMEOUT_MINUTES ))

        set +e
        # Own Codex home per shard, so concurrent sessions don't share state. SIGTERM at the limit,
        # SIGKILL 30s later if Codex hasn't exited.
        rm -f "$output_file"
        CODEX_HOME="$CODEX_HOME/$name" timeout --kill-after=30 "$(( shard_minutes * 60 ))" \
            codex exec "${CODEX_ARGS[@]}" --output-last-message "$output_file" - \
            < "$prompt_file" > "$log_file" 2>&1
        exit_code=$?
        set -e

        # Retry only a rate limit, and only while the retry still leaves a usable slot in the budget
        if [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne 124 ] && [ "$exit_code" -ne 137 ] \
            && [ "$attempt" -lt "$RATE_LIMIT_RETRIES" ] \
            && ! log_says_quota "$log_file" && log_says_rate_limited "$log_file"
        then
            delay=$(( RATE_LIMIT_BACKOFF_SECONDS * (1 << attempt) + RANDOM % 30 ))
            if [ $(( REVIEW_BUDGET_MINUTES - (SECONDS + delay) / 60 )) -ge "$MIN_SHARD_MINUTES" ]
            then
                attempt=$(( attempt + 1 ))
                echo "::warning::Shard [$name] was rate limited - retrying in ${delay}s (retry ${attempt} of ${RATE_LIMIT_RETRIES})"
                sleep "$delay"
                continue
            fi
        fi
        break
    done

    duration=$(( (SECONDS - start) / 60 ))

    # 124: stopped at the limit; 137: killed after ignoring the stop
    if [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 137 ]
    then
        echo "::error::Shard [$name] timed out after ${shard_minutes} minutes"
        record_status "$name" timeout "$paths_json"
    elif [ "$exit_code" -ne 0 ]
    then
        echo "::error::Shard [$name] failed: Codex exited with code ${exit_code} after ${duration}m"
        if grep -qE "(invalid_api_key|token_expired|401 Unauthorized|Incorrect API key)" "$log_file"
        then
            echo "::error::Shard [$name]: authentication failure - the CODEX_API_KEY secret is likely invalid or expired"
        elif log_says_quota "$log_file"
        then
            echo "::error::Shard [$name]: the Codex API key's organisation is out of quota (insufficient_quota) - raise its usage limit; retrying won't help"
        elif log_says_rate_limited "$log_file"
        then
            echo "::error::Shard [$name]: Codex was still rate limited after ${attempt} retries"
        elif grep -qiE "(bwrap|landlock|sandbox)" "$log_file"
        then
            echo "::error::Shard [$name]: the Codex sandbox failed to start or run a command"
        fi
        record_status "$name" failed "$paths_json"
    elif ! jq -e '.findings | type == "array"' "$output_file" > /dev/null 2>&1
    then
        echo "::error::Shard [$name] produced output that does not match the findings schema"
        rm -f "$output_file"
        record_status "$name" invalid-output "$paths_json"
    else
        echo "Shard [$name] completed in ${duration}m"
        record_status "$name" ok "$paths_json"
    fi
}

while IFS= read -r name
do
    if [ -n "${SHARD_FILTER:-}" ] && [ "$name" != "$SHARD_FILTER" ]
    then
        continue
    fi
    # Wait for a free slot
    while [ "$(jobs -rp | wc -l)" -ge "$PARALLEL_SHARDS" ]
    do
        wait -n || true
    done
    review_shard "$name" < /dev/null &
done <<< "$SHARD_NAMES"
wait

FAILED=()
while IFS= read -r name
do
    status_file="$OUT_DIR/$name.status.json"
    if [ -n "${SHARD_FILTER:-}" ] && [ "$name" != "$SHARD_FILTER" ]
    then
        continue
    fi
    if [ ! -f "$status_file" ]
    then
        # The shard's subshell died before recording a result
        echo "::error::Shard [$name] ended without a result"
        record_status "$name" failed '[]'
    fi
    cat "$status_file" >> "$OUT_DIR/status.jsonl"
    if [ "$(jq -r .status "$status_file")" != ok ]
    then
        FAILED+=("$name")
    fi
done <<< "$SHARD_NAMES"

echo "failed_shards=${FAILED[*]:-}" >> "$GITHUB_OUTPUT"
