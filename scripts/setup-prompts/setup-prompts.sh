#!/bin/bash
# external/ag-shared/scripts/setup-prompts/setup-prompts.sh
# Smart prompts setup for AG Grid products
#
# This script handles:
# 1. Cloning/updating the external prompts repo if available
# 2. Setting up worktree symlinks
# 3. Configuring agentic tools (Claude, Cursor, Gemini, Codex, VS Code)
#
# Configuration via environment variables (defaults derived from git remote origin):
#   AG_PROMPTS_REPO - Git URL for prompts repository (default: git@github.com:ag-grid/{project}-prompts.git)
#   AG_PROMPTS_DIR_NAME - Directory name for prompts checkout (default: {project}-prompts)
#   AG_PROJECT_NAME - Project name for display (default: title case of project, e.g. "AG Grid")
#   AG_PROJECT_PREFIX - Project prefix for Codex MCP servers (default: {project})

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(readlink -f "$(dirname "$0")")"

# Source library files
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/git.sh"
source "$SCRIPT_DIR/lib/prompts.sh"
source "$SCRIPT_DIR/lib/mcp.sh"
source "$SCRIPT_DIR/lib/tools/claude.sh"
source "$SCRIPT_DIR/lib/tools/cursor.sh"
source "$SCRIPT_DIR/lib/tools/gemini.sh"
source "$SCRIPT_DIR/lib/tools/codex.sh"
source "$SCRIPT_DIR/lib/tools/vscode.sh"

# Detect project name from git remote origin
# Extracts repo name from URLs like:
#   git@github.com:ag-grid/ag-charts.git -> ag-charts
#   https://github.com/ag-grid/ag-grid.git -> ag-grid
detect_project_name() {
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")

    if [[ -z "$remote_url" ]]; then
        echo "ag-grid"  # fallback
        return
    fi

    # Extract repo name from URL (handles both SSH and HTTPS)
    local repo_name
    repo_name=$(echo "$remote_url" | sed -E 's|.*[:/]([^/]+)\.git$|\1|; s|.*[:/]([^/]+)$|\1|')

    echo "$repo_name"
}

# Get detected project name
DETECTED_PROJECT=$(detect_project_name)

# Configuration - defaults derived from git remote, can be overridden
PROMPTS_REPO="${AG_PROMPTS_REPO:-git@github.com:ag-grid/${DETECTED_PROJECT}-prompts.git}"
PROMPTS_DIR_NAME="${AG_PROMPTS_DIR_NAME:-${DETECTED_PROJECT}-prompts}"
PROJECT_PREFIX="${AG_PROJECT_PREFIX:-${DETECTED_PROJECT}}"

# Convert project prefix to title case for display name (ag-grid -> AG Grid)
default_project_name() {
    echo "$PROJECT_PREFIX" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper($i)}1'
}
PROJECT_NAME="${AG_PROJECT_NAME:-$(default_project_name)}"

# Target repo is current working directory
REPO_ROOT="$(pwd)"

# Prompt source paths
AG_SHARED_PROMPTS="$REPO_ROOT/external/ag-shared/prompts"
TOOLS_PROMPTS="$REPO_ROOT/tools/prompts"
PROMPTS_SYMLINK="$REPO_ROOT/external/prompts"

# Get the main repo root (handles worktrees)
MAIN_REPO_ROOT=$(get_main_repo_root)

# Prompts directory is always adjacent to the MAIN repo, not the worktree
PROMPTS_DIR="$MAIN_REPO_ROOT/../$PROMPTS_DIR_NAME"

# Parse command line options
UPDATE_MCP_CONFIG=false
while getopts "u" opt; do
    case $opt in
        u)
            UPDATE_MCP_CONFIG=true
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

main() {
    # Skip in CI
    if is_ci; then
        echo "Skipping prompts setup (CI environment)"
        return 0
    fi

    # Check and configure git symlinks
    check_symlinks_config

    # Handle external prompts repo (clone/update/symlink)
    handle_external_prompts_repo

    # Skip tool setup if no agentic tools detected
    if ! has_agentic_tools && ! is_vscode; then
        echo "Skipping prompts setup (no agentic tools detected)"
        return 0
    fi

    # Update MCP config if -u flag was passed
    if [[ "$UPDATE_MCP_CONFIG" == true ]]; then
        configure_mcp
    fi

    # Tool-specific setups
    if command -v claude >/dev/null 2>&1; then
        setup_claude
    fi

    if command -v gemini >/dev/null 2>&1; then
        setup_gemini
    fi

    if command -v cursor >/dev/null 2>&1; then
        setup_cursor
    fi

    if command -v codex >/dev/null 2>&1; then
        setup_codex
    fi

    if is_vscode; then
        setup_vscode
    fi

    # Enable direnv if installed, .envrc exists, and user has the AG project directory
    if command -v direnv >/dev/null 2>&1 && [[ -f "$REPO_ROOT/.envrc" ]] && [[ -d "$HOME/.claude-${PROJECT_PREFIX}/" ]]; then
        direnv allow
    fi

    echo ""
    echo "✓ Prompts setup complete"
}

main "$@"
