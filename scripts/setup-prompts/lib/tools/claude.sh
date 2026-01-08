#!/bin/bash
# lib/tools/claude.sh - Claude Code specific setup

setup_claude() {
    echo "Setting up Claude Code..."

    # Setup commands, agents, skills from all sources
    setup_commands .claude/commands
    setup_agents .claude/agents
    setup_skills .claude/skills

    # Setup rules (guides with frontmatter) from all sources
    setup_rules .claude/rules

    # Setup package-agents from tools/prompts only
    setup_package_agents .claude/rules

    # Setup MCP configuration
    setup_mcp .mcp.json

    echo "✓ Claude Code setup complete"
}
