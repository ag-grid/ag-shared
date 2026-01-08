#!/bin/bash
# lib/mcp.sh - MCP configuration helpers
# Uses Node.js script for JSON processing (mcp-config.mjs)

# Get the directory where the setup-prompts scripts are located
MCP_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")/.."

# Get all .mcp.json source files that exist (comma-separated for Node script)
get_mcp_sources_csv() {
    local sources=()
    [[ -f "$AG_SHARED_PROMPTS/.mcp.json" ]] && sources+=("$AG_SHARED_PROMPTS/.mcp.json")
    [[ -d "$PROMPTS_SYMLINK" && -f "$PROMPTS_SYMLINK/.mcp.json" ]] && sources+=("$PROMPTS_SYMLINK/.mcp.json")
    [[ -f "$TOOLS_PROMPTS/.mcp.json" ]] && sources+=("$TOOLS_PROMPTS/.mcp.json")

    # Join with commas
    local IFS=','
    echo "${sources[*]}"
}

# Setup MCP configuration for a specific tool
# Usage: setup_tool_mcp <tool> <output-path>
# Tools: claude, cursor, gemini, vscode, codex
setup_tool_mcp() {
    local tool="$1"
    local output_path="$2"
    local target_file

    # Handle paths - codex uses absolute path, others are relative to REPO_ROOT
    if [[ "$output_path" == /* ]]; then
        target_file="$output_path"
    else
        target_file="$REPO_ROOT/$output_path"
    fi

    local sources
    sources=$(get_mcp_sources_csv)

    if [[ -z "$sources" ]]; then
        return 0
    fi

    # Remove existing file (we're creating a new one)
    if [[ -L "$target_file" || -f "$target_file" ]]; then
        rm -f "$target_file"
    fi

    # Call Node.js script
    node "$MCP_SCRIPT_DIR/mcp-config.mjs" \
        --tool "$tool" \
        --output "$target_file" \
        --sources "$sources" \
        --project-prefix "$PROJECT_PREFIX" \
        --repo-root "$REPO_ROOT"
}

# Convenience functions for each tool
setup_mcp() {
    setup_tool_mcp claude "$1"
}

setup_cursor_mcp() {
    setup_tool_mcp cursor "$1"
}

setup_gemini_mcp() {
    setup_tool_mcp gemini "$1"
}

setup_vscode_mcp() {
    setup_tool_mcp vscode "$1"
}

setup_codex_mcp() {
    local path_arg="$1"
    local target_file
    target_file=$(expand_path "$path_arg")

    # Backup existing file if it exists
    if [[ -f "$target_file" ]]; then
        cp "$target_file" "${target_file}.bak"
    fi

    setup_tool_mcp codex "$target_file"

    if [[ -f "${target_file}.bak" ]]; then
        echo "  (Backup saved as ${target_file}.bak)"
        cleanup_old_backups "$target_file" 3
    fi
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
