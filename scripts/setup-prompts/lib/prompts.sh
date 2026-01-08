#!/bin/bash
# lib/prompts.sh - Prompt setup functions (commands, agents, skills, rules)
# Merges from all three sources: ag-shared/prompts -> external/prompts -> tools/prompts

# Get all prompt source directories that exist
# Returns array in precedence order (later overrides earlier)
get_prompt_sources() {
    local sources=()
    [[ -d "$AG_SHARED_PROMPTS" ]] && sources+=("$AG_SHARED_PROMPTS")
    [[ -d "$PROMPTS_SYMLINK" && -L "$PROMPTS_SYMLINK" ]] && sources+=("$PROMPTS_SYMLINK")
    [[ -d "$TOOLS_PROMPTS" ]] && sources+=("$TOOLS_PROMPTS")
    echo "${sources[@]}"
}

# Find all .md files in a source directory, respecting .nosymlink markers
# Usage: find_prompt_files "/path/to/source/commands"
find_prompt_files() {
    local source_dir="$1"
    local prompt_files=()

    if [[ ! -d "$source_dir" ]]; then
        return
    fi

    while IFS= read -r -d '' file; do
        local dir_path
        dir_path=$(dirname "$file")
        local skip_dir=false

        # Check for .nosymlink in any parent directory
        while [[ "$dir_path" == "$source_dir"* ]]; do
            if [[ -f "$dir_path/.nosymlink" ]]; then
                skip_dir=true
                break
            fi
            if [[ "$dir_path" == "$source_dir" ]]; then
                break
            fi
            dir_path=$(dirname "$dir_path")
        done

        if [[ "$skip_dir" == true ]]; then
            continue
        fi

        echo "${file#${source_dir}/}"
    done < <(find "$source_dir" -type f -name '*.md' -print0 2>/dev/null | sort -z)
}

# Setup commands from all prompt sources
# Usage: setup_commands ".claude/commands" [format] [mode]
#   format: md (default) or toml
#   mode: link (default) or copy
setup_commands() {
    local path_arg="$1"
    local target_dir
    target_dir=$(expand_path "$path_arg")
    local format=${2:-md}
    local mode=${3:-link}

    mkdir -p "$target_dir"

    local sources
    read -ra sources <<< "$(get_prompt_sources)"

    for source in "${sources[@]}"; do
        local source_dir="$source/commands"
        if [[ ! -d "$source_dir" ]]; then
            continue
        fi

        # Calculate the relative path from target to this source
        local relative_source
        if [[ "$source" == "$AG_SHARED_PROMPTS" ]]; then
            relative_source="$(path_to_root "$path_arg")external/ag-shared/prompts/commands"
        elif [[ "$source" == "$PROMPTS_SYMLINK" ]]; then
            relative_source="$(path_to_root "$path_arg")external/prompts/commands"
        elif [[ "$source" == "$TOOLS_PROMPTS" ]]; then
            relative_source="$(path_to_root "$path_arg")tools/prompts/commands"
        fi

        while IFS= read -r file; do
            [[ -z "$file" ]] && continue

            if [[ "$format" == "md" && "$mode" == "link" ]]; then
                if [[ -f "$target_dir/$file" || -L "$target_dir/$file" ]]; then
                    rm -f "$target_dir/$file"
                fi
                mkdir -p "$(dirname "$target_dir/$file")"
                ln -sf "$relative_source/$file" "$target_dir/$file"
            elif [[ "$format" == "md" && "$mode" == "copy" ]]; then
                if [[ -f "$target_dir/$file" ]]; then
                    rm -f "$target_dir/$file"
                fi
                mkdir -p "$(dirname "$target_dir/$file")"
                cp "$source_dir/$file" "$target_dir/$file"
            elif [[ "$format" == "toml" ]]; then
                mkdir -p "$(dirname "$target_dir/${file%.md}.toml")"
                cat > "$target_dir/${file%.md}.toml" <<EOF
prompt = """
@${relative_source}/${file}
"""
EOF
            fi
        done < <(find_prompt_files "$source_dir")
    done
}

# Setup agents from all prompt sources
# Usage: setup_agents ".claude/agents"
setup_agents() {
    local target_dir="$REPO_ROOT/$1"

    mkdir -p "$target_dir"

    local sources
    read -ra sources <<< "$(get_prompt_sources)"

    for source in "${sources[@]}"; do
        local source_dir="$source/agents"
        if [[ ! -d "$source_dir" ]]; then
            continue
        fi

        # Calculate relative path
        local relative_source
        if [[ "$source" == "$AG_SHARED_PROMPTS" ]]; then
            relative_source="$(path_to_root "$1")external/ag-shared/prompts/agents"
        elif [[ "$source" == "$PROMPTS_SYMLINK" ]]; then
            relative_source="$(path_to_root "$1")external/prompts/agents"
        elif [[ "$source" == "$TOOLS_PROMPTS" ]]; then
            relative_source="$(path_to_root "$1")tools/prompts/agents"
        fi

        for file in "$source_dir"/*.md; do
            if [[ -f "$file" ]]; then
                local filename
                filename=$(basename "$file")
                rm -f "$target_dir/$filename"
                ln -sf "$relative_source/$filename" "$target_dir/$filename"
            fi
        done
    done
}

# Setup skills from all prompt sources
# Usage: setup_skills ".claude/skills"
setup_skills() {
    local target_dir="$REPO_ROOT/$1"

    mkdir -p "$target_dir"

    local sources
    read -ra sources <<< "$(get_prompt_sources)"

    for source in "${sources[@]}"; do
        local source_dir="$source/skills"
        if [[ ! -d "$source_dir" ]]; then
            continue
        fi

        # Calculate relative path
        local relative_source
        if [[ "$source" == "$AG_SHARED_PROMPTS" ]]; then
            relative_source="$(path_to_root "$1")external/ag-shared/prompts/skills"
        elif [[ "$source" == "$PROMPTS_SYMLINK" ]]; then
            relative_source="$(path_to_root "$1")external/prompts/skills"
        elif [[ "$source" == "$TOOLS_PROMPTS" ]]; then
            relative_source="$(path_to_root "$1")tools/prompts/skills"
        fi

        for skill_dir in "$source_dir"/*/; do
            if [[ -d "$skill_dir" ]]; then
                local skill_name
                skill_name=$(basename "$skill_dir")
                # Remove existing symlink or directory
                if [[ -L "$target_dir/$skill_name" || -d "$target_dir/$skill_name" ]]; then
                    rm -rf "$target_dir/$skill_name"
                fi
                ln -sf "$relative_source/$skill_name" "$target_dir/$skill_name"
            fi
        done
    done
}

# Setup rules from guides in all prompt sources
# Only includes files with YAML frontmatter (starting with ---)
# Usage: setup_rules ".claude/rules"
setup_rules() {
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

        # Calculate relative path
        local relative_source
        if [[ "$source" == "$AG_SHARED_PROMPTS" ]]; then
            relative_source="$(path_to_root "$1")external/ag-shared/prompts/guides"
        elif [[ "$source" == "$PROMPTS_SYMLINK" ]]; then
            relative_source="$(path_to_root "$1")external/prompts/guides"
        elif [[ "$source" == "$TOOLS_PROMPTS" ]]; then
            relative_source="$(path_to_root "$1")tools/prompts/guides"
        fi

        for file in "$source_dir"/*.md; do
            if [[ -f "$file" ]]; then
                # Check if file starts with YAML frontmatter (---)
                if head -n 1 "$file" | grep -q '^---$'; then
                    local filename
                    filename=$(basename "$file")
                    rm -f "$target_dir/$filename"
                    ln -sf "$relative_source/$filename" "$target_dir/$filename"
                    count=$((count+1))
                fi
            fi
        done
    done

    echo "✓ Setup $count rules symlinks in $target_dir"
}

# Setup package-agents from tools/prompts only (repo-specific)
# Usage: setup_package_agents ".claude/rules"
setup_package_agents() {
    local target_dir="$REPO_ROOT/$1"
    local source_dir="$TOOLS_PROMPTS/package-agents"

    mkdir -p "$target_dir"

    local count=0
    if [[ -d "$source_dir" ]]; then
        for file in "$source_dir"/*.md; do
            if [[ -f "$file" ]]; then
                # Check if file starts with YAML frontmatter (---)
                if head -n 1 "$file" | grep -q '^---$'; then
                    local filename
                    filename=$(basename "$file")
                    rm -f "$target_dir/$filename"
                    ln -sf "$(path_to_root "$1")tools/prompts/package-agents/$filename" "$target_dir/$filename"
                    count=$((count+1))
                fi
            fi
        done
    fi

    echo "✓ Setup $count package-agent rules symlinks in $target_dir"
}
