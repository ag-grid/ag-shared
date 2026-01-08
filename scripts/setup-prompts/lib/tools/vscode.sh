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

        # Link common prompts
        for prompt_file in "$commands_dir"/*.md; do
            if [[ -f "$prompt_file" ]]; then
                local filename
                filename=$(basename "$prompt_file")
                local copilot_prompt="$REPO_ROOT/.github/prompts/${filename%.md}.prompt.md"

                if [[ ! -f "$copilot_prompt" ]]; then
                    ln -sf "$relative_source/$filename" "$copilot_prompt"
                fi
            fi
        done
    done

    echo "✓ VS Code / GitHub Copilot setup complete"
}
