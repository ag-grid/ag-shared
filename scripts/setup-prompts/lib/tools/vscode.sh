#!/bin/bash
# lib/tools/vscode.sh - VS Code / GitHub Copilot specific setup

# Detect if running in VS Code or Codespaces
is_vscode() {
    [[ "${TERM_PROGRAM:-}" == "vscode" || "${CODESPACES:-}" == "true" ]]
}

setup_vscode() {
    echo "Setting up VS Code / GitHub Copilot..."

    # Setup MCP configuration
    setup_vscode_mcp .vscode/mcp.json

    # Setup GitHub Copilot prompts
    mkdir -p "$REPO_ROOT/.github/prompts"

    # Link prompts from commands to .github/prompts
    local sources
    read -ra sources <<< "$(get_prompt_sources)"

    for source in "${sources[@]}"; do
        local commands_dir="$source/commands"
        if [[ ! -d "$commands_dir" ]]; then
            continue
        fi

        # Calculate relative path
        local relative_source
        if [[ "$source" == "$AG_SHARED_PROMPTS" ]]; then
            relative_source="../../external/ag-shared/prompts/commands"
        elif [[ "$source" == "$PROMPTS_SYMLINK" ]]; then
            relative_source="../../external/prompts/commands"
        elif [[ "$source" == "$TOOLS_PROMPTS" ]]; then
            relative_source="../../tools/prompts/commands"
        fi

        # Link prompts from commands (recursive search for subdirectories)
        while IFS= read -r -d '' prompt_file; do
            local filename
            filename=$(basename "$prompt_file")
            # Get relative path from commands_dir (e.g., "code/cleanup.md")
            local rel_path="${prompt_file#${commands_dir}/}"
            # Get subfolder name for prefix (e.g., "code" from "code/cleanup.md")
            local subfolder
            subfolder=$(dirname "$rel_path")
            # Build prompt name with subfolder prefix (e.g., "code-cleanup.prompt.md")
            local prompt_name
            if [[ "$subfolder" != "." ]]; then
                prompt_name="${subfolder}-${filename%.md}.prompt.md"
            else
                prompt_name="${filename%.md}.prompt.md"
            fi
            local copilot_prompt="$REPO_ROOT/.github/prompts/$prompt_name"

            # Remove existing and create new symlink (later sources override earlier)
            rm -f "$copilot_prompt"
            ln -sf "$relative_source/$rel_path" "$copilot_prompt"
        done < <(find "$commands_dir" -type f -name '*.md' -print0 2>/dev/null)
    done

    echo "✓ VS Code / GitHub Copilot setup complete"
}
