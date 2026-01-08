#!/usr/bin/env bash
#
# setup-prompts.sh - Dynamic tool detection and rulesync configuration
#
# This script detects installed AI coding tools and generates configuration
# only for those that are present, using rulesync as the underlying engine.
#
# Usage:
#   ./setup-prompts.sh           # Auto-detect and generate
#   ./setup-prompts.sh --all     # Generate for all supported tools
#   ./setup-prompts.sh --list    # List detected tools
#   ./setup-prompts.sh --help    # Show help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Tool detection functions
# Each function returns 0 if tool is detected, 1 otherwise

detect_claudecode() {
    command -v claude &>/dev/null && return 0
    [[ -d "$HOME/.claude" ]] && return 0
    return 1
}

detect_cursor() {
    command -v cursor &>/dev/null && return 0
    [[ -d "/Applications/Cursor.app" ]] && return 0
    [[ -d "$HOME/.cursor" ]] && return 0
    return 1
}

detect_copilot() {
    command -v code &>/dev/null && return 0
    [[ -d "/Applications/Visual Studio Code.app" ]] && return 0
    return 1
}

detect_codexcli() {
    command -v codex &>/dev/null && return 0
    return 1
}

detect_geminicli() {
    command -v gemini &>/dev/null && return 0
    return 1
}

detect_opencode() {
    command -v opencode &>/dev/null && return 0
    [[ -f "$HOME/.opencode/config.json" ]] && return 0
    return 1
}

detect_antigravity() {
    command -v antigravity &>/dev/null && return 0
    command -v ag &>/dev/null && return 0
    [[ -d "$HOME/.config/antigravity" ]] && return 0
    return 1
}

detect_cline() {
    local vscode_ext="$HOME/.vscode/extensions"
    [[ -d "$vscode_ext" ]] && ls "$vscode_ext" 2>/dev/null | grep -q "saoudrizwan.claude-dev" && return 0
    return 1
}

detect_windsurf() {
    command -v windsurf &>/dev/null && return 0
    [[ -d "/Applications/Windsurf.app" ]] && return 0
    return 1
}

detect_roo() {
    command -v roo &>/dev/null && return 0
    local vscode_ext="$HOME/.vscode/extensions"
    [[ -d "$vscode_ext" ]] && ls "$vscode_ext" 2>/dev/null | grep -q "roo" && return 0
    return 1
}

detect_kilo() {
    command -v kilo &>/dev/null && return 0
    return 1
}

detect_warp() {
    command -v warp &>/dev/null && return 0
    [[ -d "/Applications/Warp.app" ]] && return 0
    return 1
}

detect_junie() {
    [[ -d "$HOME/.config/JetBrains" ]] && return 0
    [[ -d "$HOME/Library/Application Support/JetBrains" ]] && return 0
    return 1
}

detect_augmentcode() {
    command -v augment &>/dev/null && return 0
    return 1
}

detect_qwencode() {
    command -v qwen &>/dev/null && return 0
    return 1
}

detect_kiro() {
    command -v kiro &>/dev/null && return 0
    return 1
}

# Tool configurations (bash 3 compatible - no associative arrays)
# Format: tool_id:display_name:detector_function
TOOLS="
claudecode:Claude Code:detect_claudecode
cursor:Cursor:detect_cursor
copilot:GitHub Copilot:detect_copilot
codexcli:Codex CLI:detect_codexcli
geminicli:Gemini CLI:detect_geminicli
opencode:OpenCode:detect_opencode
antigravity:Google Antigravity:detect_antigravity
cline:Cline:detect_cline
windsurf:Windsurf:detect_windsurf
roo:Roo Code:detect_roo
kilo:Kilo Code:detect_kilo
warp:Warp:detect_warp
junie:JetBrains Junie:detect_junie
augmentcode:AugmentCode:detect_augmentcode
qwencode:Qwen Code:detect_qwencode
kiro:Kiro IDE:detect_kiro
"

# Detect all installed tools
detect_tools() {
    local detected=""

    while IFS=: read -r tool_id display_name detector; do
        [[ -z "$tool_id" ]] && continue
        if $detector 2>/dev/null; then
            if [[ -z "$detected" ]]; then
                detected="$tool_id"
            else
                detected="$detected,$tool_id"
            fi
        fi
    done <<< "$TOOLS"

    # Always include agentsmd for the open standard
    if [[ -z "$detected" ]]; then
        detected="agentsmd"
    else
        detected="agentsmd,$detected"
    fi

    echo "$detected"
}

# Print detected tools
print_detected_tools() {
    echo -e "${BLUE}Detecting installed AI coding tools...${NC}"
    echo ""

    while IFS=: read -r tool_id display_name detector; do
        [[ -z "$tool_id" ]] && continue
        if $detector 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $display_name ($tool_id)"
        else
            echo -e "  ${YELLOW}○${NC} $display_name ($tool_id) - not detected"
        fi
    done <<< "$TOOLS"

    echo ""
    echo -e "  ${GREEN}✓${NC} AGENTS.md (agentsmd) - always included"
    echo ""
}

# Generate rulesync configuration
generate_config() {
    local targets="$1"

    cd "$REPO_ROOT"

    echo -e "${BLUE}Generating configurations for: ${NC}$targets"
    echo ""

    # Run rulesync with detected targets
    npx rulesync generate \
        --targets="$targets" \
        --features="rules,ignore,mcp,commands,subagents" \
        --delete

    echo ""
    echo -e "${GREEN}✓ Configuration generated successfully${NC}"
}

# Show help
show_help() {
    echo "Usage: setup-prompts.sh [OPTIONS]"
    echo ""
    echo "Detects installed AI coding tools and generates rulesync configuration"
    echo "only for those that are present."
    echo ""
    echo "Options:"
    echo "  --all       Generate for all supported tools"
    echo "  --list      List detected tools without generating"
    echo "  --targets   Comma-separated list of specific targets"
    echo "  --help      Show this help message"
    echo ""
    echo "Supported tools:"
    while IFS=: read -r tool_id display_name detector; do
        [[ -z "$tool_id" ]] && continue
        echo "  - $display_name ($tool_id)"
    done <<< "$TOOLS"
    echo "  - AGENTS.md (agentsmd)"
    echo ""
    echo "Examples:"
    echo "  ./setup-prompts.sh                    # Auto-detect and generate"
    echo "  ./setup-prompts.sh --all              # Generate for all tools"
    echo "  ./setup-prompts.sh --list             # Show detected tools"
    echo "  ./setup-prompts.sh --targets=claudecode,cursor  # Specific tools"
}

# Main
main() {
    local mode="auto"
    local custom_targets=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                mode="all"
                shift
                ;;
            --list)
                mode="list"
                shift
                ;;
            --targets=*)
                mode="custom"
                custom_targets="${1#*=}"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done

    case $mode in
        list)
            print_detected_tools
            ;;
        all)
            echo -e "${BLUE}Generating for all supported tools...${NC}"
            generate_config "*"
            ;;
        custom)
            generate_config "$custom_targets"
            ;;
        auto)
            print_detected_tools

            local detected
            detected=$(detect_tools)

            if [[ -z "$detected" || "$detected" == "agentsmd" ]]; then
                echo -e "${YELLOW}No tools detected beyond AGENTS.md. Use --all to generate for all tools.${NC}"
            fi

            generate_config "$detected"
            ;;
    esac
}

main "$@"
