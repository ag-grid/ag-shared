#!/bin/bash
# lib/tools/gemini.sh - Gemini CLI specific setup

setup_gemini() {
    echo "Setting up Gemini CLI..."

    # Setup commands in TOML format
    setup_commands .gemini/commands toml

    # Setup MCP configuration (uses settings.json)
    setup_mcp .gemini/settings.json

    echo "✓ Gemini CLI setup complete"
}
