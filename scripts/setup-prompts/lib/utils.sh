#!/bin/bash
# lib/utils.sh - Utility functions for setup-prompts

# Calculate relative path from a file location back to repo root
# Usage: path_to_root ".claude/commands/foo.md" -> "./../.."
path_to_root() {
    local target_file=$1

    # Count directory levels in target_file path
    local dir_count
    dir_count=$(echo "$target_file" | tr -cd '/' | wc -c)

    # Build relative path with appropriate number of ../ prefixes
    local relative_path="./"
    for ((i=0; i<dir_count; i++)); do
        relative_path="$relative_path../"
    done

    echo "$relative_path"
}

# Cleanup old backup files, keeping only the most recent N
# Usage: cleanup_old_backups "/path/to/file" 3
cleanup_old_backups() {
    local target_file=$1
    local max_backups=${2:-3}

    local backup_dir
    backup_dir=$(dirname "$target_file")
    local backup_name
    backup_name=$(basename "$target_file")

    # Count backup files
    local backup_count
    backup_count=$(find "$backup_dir" -name "${backup_name}.bak*" -type f 2>/dev/null | wc -l)

    if [[ $backup_count -gt $max_backups ]]; then
        echo "Found $backup_count backup files, cleaning up to keep only $max_backups most recent"

        # Use ls with modification time sort to get files in reverse chronological order
        ls -t "$backup_dir"/${backup_name}.bak* 2>/dev/null | tail -n +$((max_backups + 1)) | while read -r old_backup; do
            if [[ -f "$old_backup" ]]; then
                echo "Removing old backup: $old_backup"
                rm -f "$old_backup"
            fi
        done
    fi
}

# Detect CI environment
is_ci() {
    [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${JENKINS_URL:-}" || -n "${BUILDKITE:-}" || -n "${CIRCLECI:-}" || -n "${TRAVIS:-}" ]]
}

# Detect if running in interactive terminal
is_interactive() {
    [[ -t 0 ]]
}

# Prompt user with default yes, or auto-yes in non-interactive mode
# Usage: prompt_yes_no "Update now?" && do_update
prompt_yes_no() {
    local message="$1"
    if ! is_interactive; then
        # Non-interactive: auto-yes
        return 0
    fi
    read -p "$message [Y/n] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Nn]$ ]]
}

# Detect if user has agentic tools installed
has_agentic_tools() {
    command -v claude >/dev/null 2>&1 || \
    command -v cursor >/dev/null 2>&1 || \
    command -v gemini >/dev/null 2>&1 || \
    command -v codex >/dev/null 2>&1
}

# Expand path with ~ to absolute path
# Usage: expand_path "~/.codex/config.toml" -> "/Users/foo/.codex/config.toml"
expand_path() {
    local path_arg="$1"
    if [[ "$path_arg" == /* ]]; then
        echo "$path_arg"
    elif [[ "$path_arg" == ~* ]]; then
        echo "${path_arg/#\~/$HOME}"
    else
        echo "$REPO_ROOT/$path_arg"
    fi
}
