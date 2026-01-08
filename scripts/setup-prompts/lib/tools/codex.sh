#!/bin/bash
# lib/tools/codex.sh - OpenAI Codex CLI specific setup
# Note: Codex config is user-scoped, not project-scoped

setup_codex() {
    echo "Setting up Codex CLI..."
    echo "WARNING: Codex config is user-scoped, not project-scoped."

    # Setup commands as copies (user-scoped path)
    setup_commands ~/.codex/prompts md copy

    # Setup MCP configuration in TOML format
    setup_codex_mcp ~/.codex/config.toml

    echo "✓ Codex CLI setup complete"
}
