#!/bin/bash
# lib/tools/cursor.sh - Cursor specific setup

# Setup Cursor worktrees configuration
setup_cursor_worktrees() {
    local target_file="$REPO_ROOT/$1"
    # Use dirname since path_to_root expects directory paths, not file paths
    local relative_path
    relative_path=$(path_to_root "$(dirname "$1")")

    # Only create if worktrees config exists in prompts
    if [[ -f "$PROMPTS_SYMLINK/.cursor-worktrees.json" ]]; then
        mkdir -p "$(dirname "$target_file")"
        ln -sf "${relative_path}external/prompts/.cursor-worktrees.json" "$target_file"
    elif [[ -f "$AG_SHARED_PROMPTS/.cursor-worktrees.json" ]]; then
        mkdir -p "$(dirname "$target_file")"
        ln -sf "${relative_path}external/ag-shared/prompts/.cursor-worktrees.json" "$target_file"
    fi
}

# Setup Cursor rules from guides in all prompt sources
# Cursor uses folder-based rules: .cursor/rules/{rule-name}/RULE.md
# Only includes files with YAML frontmatter (starting with ---)
# Usage: setup_cursor_rules ".cursor/rules"
setup_cursor_rules() {
    local target_dir="$REPO_ROOT/$1"

    mkdir -p "$target_dir"

    local count=0
    local sources
    read -ra sources <<< "$(get_prompt_sources)"

    for source in "${sources[@]}"; do
        local source_dir="$source/guides"
        if [[ ! -d "$source_dir" ]]; then
            continue
        fi

        # Calculate relative path (extra ../ for rule subdirectory)
        local relative_source
        if [[ "$source" == "$AG_SHARED_PROMPTS" ]]; then
            relative_source="$(path_to_root "$1")../external/ag-shared/prompts/guides"
        elif [[ "$source" == "$PROMPTS_SYMLINK" ]]; then
            relative_source="$(path_to_root "$1")../external/prompts/guides"
        elif [[ "$source" == "$TOOLS_PROMPTS" ]]; then
            relative_source="$(path_to_root "$1")../tools/prompts/guides"
        fi

        for file in "$source_dir"/*.md; do
            if [[ -f "$file" ]]; then
                # Check if file starts with YAML frontmatter (---)
                if head -n 1 "$file" | grep -q '^---$'; then
                    local filename
                    filename=$(basename "$file" .md)
                    local rule_dir="$target_dir/$filename"

                    # Remove existing rule directory/symlink
                    rm -rf "$rule_dir"
                    mkdir -p "$rule_dir"

                    # Symlink the guide as RULE.md
                    ln -sf "$relative_source/$(basename "$file")" "$rule_dir/RULE.md"
                    count=$((count+1))
                fi
            fi
        done
    done

    echo "✓ Setup $count Cursor rules in $target_dir"
}

setup_cursor() {
    echo "Setting up Cursor..."

    # Setup commands as symlinks
    setup_commands .cursor/commands md link

    # Setup MCP configuration
    setup_mcp .cursor/mcp.json

    # Setup worktrees configuration
    setup_cursor_worktrees .cursor/worktrees.json

    # Setup rules from guides
    setup_cursor_rules .cursor/rules

    echo "✓ Cursor setup complete"
}
