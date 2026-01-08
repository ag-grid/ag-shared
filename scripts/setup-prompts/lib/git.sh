#!/bin/bash
# lib/git.sh - Git helpers for worktree handling and repo operations

# Detect if we're in a git worktree
# In a worktree, .git is a file containing "gitdir: /path/to/main/.git/worktrees/name"
is_worktree() {
    [[ -f ".git" ]]
}

# Get the main repo root (handles worktrees)
# In a worktree, finds the actual main repo location
get_main_repo_root() {
    local git_path=".git"

    if [[ -f "$git_path" ]]; then
        # We're in a worktree - parse the gitdir to find main repo
        local gitdir
        gitdir=$(cat "$git_path" | sed 's/gitdir: //')
        # gitdir is like /path/to/main/.git/worktrees/name
        # Go up twice to get /path/to/main/.git, then dirname for main repo
        local main_git_dir
        main_git_dir=$(dirname "$(dirname "$gitdir")")
        dirname "$main_git_dir"
    else
        # Normal checkout - current directory is the repo root
        pwd
    fi
}

# Setup worktree symlink to allow version-controlled relative symlink to work
# Creates a symlink in the worktree's parent directory pointing to the real prompts location
setup_worktree_symlink() {
    if ! is_worktree; then
        return 0
    fi

    # Only setup if prompts directory exists
    if [[ ! -d "$PROMPTS_DIR" ]]; then
        return 0
    fi

    local worktree_parent
    worktree_parent=$(dirname "$(pwd)")
    local parent_prompts_link="$worktree_parent/$PROMPTS_DIR_NAME"
    local real_prompts
    real_prompts=$(cd "$PROMPTS_DIR" && pwd)

    if [[ ! -e "$parent_prompts_link" ]]; then
        echo "Creating prompts symlink in worktree parent: $parent_prompts_link -> $real_prompts"
        ln -sf "$real_prompts" "$parent_prompts_link"
    elif [[ -L "$parent_prompts_link" ]]; then
        local current_target
        current_target=$(readlink "$parent_prompts_link")
        if [[ "$current_target" != "$real_prompts" ]]; then
            echo "Updating prompts symlink in worktree parent: $parent_prompts_link -> $real_prompts"
            ln -sf "$real_prompts" "$parent_prompts_link"
        fi
    fi
}

# Check and configure git to handle symlinks properly
check_symlinks_config() {
    local symlinks_setting
    symlinks_setting=$(git config --get core.symlinks 2>/dev/null || echo "")

    if [[ "$symlinks_setting" != "true" ]]; then
        echo "Setting git core.symlinks to true..."
        git config core.symlinks true
        echo "✓ Git configured to handle symlinks properly"
    fi
}

# Check if prompts checkout is clean (no uncommitted changes)
is_checkout_clean() {
    (cd "$PROMPTS_DIR" && [[ -z "$(git status --porcelain)" ]])
}

# Check if prompts checkout is behind remote
is_checkout_behind() {
    (
        cd "$PROMPTS_DIR"
        git fetch origin --quiet 2>/dev/null || return 1
        local LOCAL
        LOCAL=$(git rev-parse HEAD)
        local REMOTE
        REMOTE=$(git rev-parse origin/latest 2>/dev/null || git rev-parse origin/main 2>/dev/null || echo "")
        [[ -n "$REMOTE" && "$LOCAL" != "$REMOTE" ]]
    )
}

# Check if user has access to the prompts repo
has_repo_access() {
    git ls-remote "$PROMPTS_REPO" HEAD >/dev/null 2>&1
}

# Verify external/prompts symlink resolves correctly
# Returns 0 if symlink exists and resolves, 1 if missing/broken (non-fatal)
verify_symlink() {
    if [[ ! -L "$PROMPTS_SYMLINK" ]]; then
        return 1
    fi

    if [[ ! -d "$PROMPTS_SYMLINK" ]]; then
        echo "Note: $PROMPTS_SYMLINK symlink exists but does not resolve"
        echo "  Symlink target: $(readlink "$PROMPTS_SYMLINK")"
        echo "  Expected: $PROMPTS_DIR_NAME checkout at $PROMPTS_DIR"
        return 1
    fi

    echo "✓ $PROMPTS_SYMLINK resolves correctly"
    return 0
}

# Setup the external/prompts symlink to point to the prompts repo
# Adapts path based on whether this is an adjacent checkout or node_modules install
setup_prompts_symlink() {
    local target="$PROMPTS_SYMLINK"

    # Calculate relative path from external/ to the prompts package
    local relative_path
    local main_repo_root
    main_repo_root=$(get_main_repo_root)

    if [[ "$PROMPTS_DIR" == "$main_repo_root/../$PROMPTS_DIR_NAME" || \
          "$PROMPTS_DIR" == "$(cd "$main_repo_root/.." 2>/dev/null && pwd)/$PROMPTS_DIR_NAME" ]]; then
        # Adjacent checkout case - external/prompts -> ../../$PROMPTS_DIR_NAME
        relative_path="../../$PROMPTS_DIR_NAME"
    else
        # node_modules case (via yarn link or direct install)
        relative_path="../node_modules/@ag-grid/$PROMPTS_DIR_NAME"
    fi

    # If target exists and is a symlink pointing to the right place, nothing to do
    if [[ -L "$target" ]]; then
        local current_target
        current_target=$(readlink "$target")
        if [[ "$current_target" == "$relative_path" ]]; then
            echo "✓ external/prompts symlink already configured correctly"
            return 0
        fi
    fi

    # Remove existing (file, symlink, or directory)
    if [[ -e "$target" || -L "$target" ]]; then
        echo "Removing existing external/prompts..."
        rm -rf "$target"
    fi

    # Ensure external directory exists
    mkdir -p "$(dirname "$target")"

    # Create symlink (use relative path for portability)
    ln -sfn "$relative_path" "$target"
    echo "✓ Created symlink: external/prompts -> $relative_path"
}

# Handle external prompts repo - clone or update
handle_external_prompts_repo() {
    # If prompts dir exists, check for updates
    if [[ -d "$PROMPTS_DIR" ]]; then
        if is_checkout_clean && is_checkout_behind; then
            echo "$PROMPTS_DIR_NAME is out of date."
            if prompt_yes_no "Update now?"; then
                echo "Updating $PROMPTS_DIR_NAME..."
                (cd "$PROMPTS_DIR" && git pull --ff-only)
            fi
        fi

        # Verify external/prompts symlink resolves
        verify_symlink || true

        # Setup worktree symlink if needed
        setup_worktree_symlink

        # Setup the prompts symlink
        setup_prompts_symlink
        return 0
    fi

    # Prompts dir doesn't exist - only offer to clone if agentic tools detected
    if ! has_agentic_tools; then
        return 0
    fi

    # Check repo access before offering to clone
    if ! has_repo_access; then
        return 0
    fi

    echo "$PROMPTS_DIR_NAME not found at $PROMPTS_DIR"
    if prompt_yes_no "Clone it now?"; then
        echo "Cloning $PROMPTS_DIR_NAME..."
        git clone "$PROMPTS_REPO" "$PROMPTS_DIR"

        # Verify external/prompts symlink
        verify_symlink || true

        # Setup worktree symlink if needed
        setup_worktree_symlink

        # Setup the prompts symlink
        setup_prompts_symlink
    fi
}
