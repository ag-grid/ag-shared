#!/bin/bash
# lib/mcp.sh - MCP configuration helpers

# Get all .mcp.json source files that exist
# Returns paths in precedence order (later overrides earlier)
get_mcp_sources() {
    local sources=()
    [[ -f "$AG_SHARED_PROMPTS/.mcp.json" ]] && sources+=("$AG_SHARED_PROMPTS/.mcp.json")
    [[ -d "$PROMPTS_SYMLINK" && -f "$PROMPTS_SYMLINK/.mcp.json" ]] && sources+=("$PROMPTS_SYMLINK/.mcp.json")
    [[ -f "$TOOLS_PROMPTS/.mcp.json" ]] && sources+=("$TOOLS_PROMPTS/.mcp.json")
    echo "${sources[@]}"
}

# Merge MCP configurations from all sources
# Creates a merged .mcp.json with mcpServers from all sources
# Later sources override earlier ones
# Usage: merge_mcp_configs "/path/to/output.json"
merge_mcp_configs() {
    local target_file="$1"

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        echo "Warning: jq not found. Cannot merge MCP configs."
        echo "Install with: brew install jq"
        return 1
    fi

    local sources
    read -ra sources <<< "$(get_mcp_sources)"

    if [[ ${#sources[@]} -eq 0 ]]; then
        return 0
    fi

    # Start with empty base
    local merged='{"mcpServers":{}}'

    # Merge each source in order (later overrides earlier)
    for source in "${sources[@]}"; do
        if [[ -f "$source" ]]; then
            # Deep merge mcpServers objects
            merged=$(echo "$merged" | jq --slurpfile new "$source" '
                .mcpServers = (.mcpServers + ($new[0].mcpServers // {}))
            ')
        fi
    done

    # Write merged config
    mkdir -p "$(dirname "$target_file")"
    echo "$merged" | jq '.' > "$target_file"
}

# Setup MCP configuration by merging from all sources
# Usage: setup_mcp ".mcp.json"
setup_mcp() {
    local target_file="$REPO_ROOT/$1"

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        echo "Warning: jq not found. Cannot setup MCP config."
        echo "Install with: brew install jq"
        return 1
    fi

    local sources
    read -ra sources <<< "$(get_mcp_sources)"

    if [[ ${#sources[@]} -eq 0 ]]; then
        return 0
    fi

    # Remove existing symlink or file (we're creating a merged file, not a symlink)
    if [[ -L "$target_file" || -f "$target_file" ]]; then
        rm -f "$target_file"
    fi

    # Merge all sources into target
    merge_mcp_configs "$target_file"

    echo "✓ Merged MCP config from ${#sources[@]} source(s) into $1"
}

# Configure MCP servers via claude CLI (optional, with -u flag)
# This is for updating the project's .mcp.json with configured servers
configure_mcp() {
    add_mcp() {
        local name=$1
        local scope=$2
        local command=$3
        shift 3
        local args=$@
        if (claude mcp get "$name" 2>&1 | grep -q "Scope: Project"); then
            claude mcp remove "$name" -s project
        fi
        if (claude mcp get "$name" 2>&1 | grep -q "Scope: Local"); then
            claude mcp remove "$name" -s local
        fi
        claude mcp add "$name" -s "$scope" -- "$command" $args
    }

    add_sse_mcp() {
        local name=$1
        local scope=$2
        local url=$3
        if (claude mcp get "$name" 2>&1 | grep -q "Scope: Project"); then
            claude mcp remove "$name" -s project
        fi
        if (claude mcp get "$name" 2>&1 | grep -q "Scope: Local"); then
            claude mcp remove "$name" -s local
        fi
        claude mcp add "$name" -s "$scope" --transport sse "$url"
    }

    # Add standard MCP servers
    add_mcp sequential-thinking project yarn run --silent mcp-server-sequential-thinking
    # add_mcp puppeteer project yarn run --silent mcp-server-puppeteer
    # add_mcp fetch project yarn run --silent mcp-fetch
    # add_mcp context7 project yarn run --silent context7-mcp

    # Atlassian SSE MCP
    # add_sse_mcp atlassian project https://mcp.atlassian.com/v1/sse
}

# Setup VS Code MCP configuration
# Merges .mcp.json sources into VS Code format
setup_vscode_mcp() {
    local target_file="$REPO_ROOT/$1"

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        echo "Warning: jq not found. Cannot update MCP config."
        echo "Install with: brew install jq"
        return 1
    fi

    local sources
    read -ra sources <<< "$(get_mcp_sources)"

    if [[ ${#sources[@]} -eq 0 ]]; then
        return 0
    fi

    # Create target file if it doesn't exist
    if [[ ! -f "$target_file" ]]; then
        mkdir -p "$(dirname "$target_file")"
        echo '{"servers": {}}' > "$target_file"
    fi

    # Merge each source in order
    for source in "${sources[@]}"; do
        if [[ -f "$source" ]]; then
            jq -r '.mcpServers | to_entries[] | @base64' "$source" 2>/dev/null | while read -r entry; do
                local server_name
                server_name=$(echo "$entry" | base64 -d | jq -r '.key')
                local server_config
                server_config=$(echo "$entry" | base64 -d | jq -r '.value')
                jq --argjson server_config "$server_config" ".servers += { (\"$server_name\"): \$server_config }" "$target_file" > "$target_file.tmp"
                mv "$target_file.tmp" "$target_file"
            done
        fi
    done
}

# Setup Codex MCP configuration (TOML format)
# Merges .mcp.json sources into Codex TOML format with project prefix
setup_codex_mcp() {
    local path_arg="$1"
    local target_file
    target_file=$(expand_path "$path_arg")

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        echo "Warning: jq not found. Cannot update MCP config."
        echo "Install with: brew install jq"
        return 1
    fi

    local sources
    read -ra sources <<< "$(get_mcp_sources)"

    if [[ ${#sources[@]} -eq 0 ]]; then
        return 0
    fi

    # Create target directory if needed
    mkdir -p "$(dirname "$target_file")"

    # Backup existing file if it exists
    if [[ -f "$target_file" ]]; then
        cp "$target_file" "${target_file}.bak"
    fi

    # Create a temporary file for the new config
    local temp_config
    temp_config=$(mktemp)

    # If existing file exists and has content, preserve non-project sections
    if [[ -f "$target_file" ]] && [[ -s "$target_file" ]]; then
        local in_project_section=false
        local skip_next_blank=false
        while IFS= read -r line; do
            # Check if we're entering a project MCP server section
            if [[ "$line" =~ ^\[mcp_servers\.\"${PROJECT_PREFIX}- ]] || [[ "$line" == "# ${PROJECT_NAME} MCP Servers (auto-generated)" ]]; then
                in_project_section=true
                skip_next_blank=true
                continue
            elif [[ "$line" =~ ^\[.*\] ]] && [[ ! "$line" =~ ^\[mcp_servers\.\"${PROJECT_PREFIX}- ]]; then
                in_project_section=false
                skip_next_blank=false
            fi

            # Skip project MCP server sections and their content
            if [[ "$in_project_section" == true ]]; then
                continue
            fi

            # Skip blank lines immediately after removed sections
            if [[ "$skip_next_blank" == true ]] && [[ -z "$line" ]]; then
                skip_next_blank=false
                continue
            fi

            echo "$line"
        done < "$target_file" > "$temp_config"
    fi

    # Add the new project MCP server configurations
    {
        echo ""
        echo "# ${PROJECT_NAME} MCP Servers (auto-generated)"

        # Process each source in order, collecting all servers
        for source in "${sources[@]}"; do
            if [[ -f "$source" ]]; then
                jq -r '.mcpServers | to_entries[] | @base64' "$source" 2>/dev/null | while read -r entry; do
                    local server_name
                    server_name=$(echo "$entry" | base64 -d | jq -r '.key')
                    local server_config
                    server_config=$(echo "$entry" | base64 -d | jq -r '.value')

                    # Write TOML section for this server with project prefix
                    echo ""
                    echo "[mcp_servers.\"${PROJECT_PREFIX}-$server_name\"]"

                    # Extract and write command
                    local command
                    command=$(echo "$server_config" | jq -r '.command')
                    echo "command = \"$command\""

                    # Add working directory
                    echo "cwd = \"$REPO_ROOT\""

                    # Extract and write args array
                    local args
                    args=$(echo "$server_config" | jq -c '.args')
                    if [[ "$args" != "null" && "$args" != "[]" ]]; then
                        local toml_args
                        toml_args=$(echo "$args" | jq -r '. | map("\"" + . + "\"") | join(", ")')
                        echo "args = [$toml_args]"
                    else
                        echo "args = []"
                    fi

                    # Extract and write env object if it exists and is not empty
                    local env
                    env=$(echo "$server_config" | jq -c '.env // {}')
                    if [[ "$env" != "{}" && "$env" != "null" ]]; then
                        local toml_env
                        toml_env=$(echo "$env" | jq -r 'to_entries | map("\(.key) = \"\(.value)\"") | join(", ")')
                        echo "env = { $toml_env }"
                    fi

                    # Extract type if present
                    local type
                    type=$(echo "$server_config" | jq -r '.type // empty')
                    if [[ -n "$type" ]]; then
                        echo "type = \"$type\""
                    fi
                done
            fi
        done
    } >> "$temp_config"

    # Move the temp file to the target location
    mv "$temp_config" "$target_file"

    if [[ -f "${target_file}.bak" ]]; then
        echo "✓ Updated Codex MCP configuration at $target_file"
        echo "  (Backup saved as ${target_file}.bak)"
        cleanup_old_backups "$target_file" 3
    else
        echo "✓ Created Codex MCP configuration at $target_file"
    fi
}
