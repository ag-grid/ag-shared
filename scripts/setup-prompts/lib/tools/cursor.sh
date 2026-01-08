#!/bin/bash
# lib/tools/cursor.sh - Cursor specific setup

# Setup Cursor worktrees configuration
setup_cursor_worktrees() {
    local target_file="$REPO_ROOT/$1"
    local relative_path
    relative_path=$(path_to_root "$1")

    # Only create if worktrees config exists in prompts
    if [[ -f "$PROMPTS_SYMLINK/.cursor-worktrees.json" ]]; then
        mkdir -p "$(dirname "$target_file")"
        ln -sf "${relative_path}external/prompts/.cursor-worktrees.json" "$target_file"
    elif [[ -f "$AG_SHARED_PROMPTS/.cursor-worktrees.json" ]]; then
        mkdir -p "$(dirname "$target_file")"
        ln -sf "${relative_path}external/ag-shared/prompts/.cursor-worktrees.json" "$target_file"
    fi
}

setup_cursor() {
    echo "Setting up Cursor..."

    # Setup commands as symlinks
    setup_commands .cursor/commands md link

    # Setup MCP configuration
    setup_mcp .cursor/mcp.json

    # Setup worktrees configuration
    setup_cursor_worktrees .cursor/worktrees.json

    echo "✓ Cursor setup complete"
}
