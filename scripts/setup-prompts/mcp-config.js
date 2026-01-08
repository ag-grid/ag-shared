#!/usr/bin/env node
/**
 * MCP Configuration Generator
 *
 * Merges MCP server configurations from multiple sources and outputs
 * tool-specific formats for Claude, Cursor, Gemini, VS Code, and Codex.
 *
 * Usage:
 *   node mcp-config.js --tool <tool> --output <path> [--sources <paths>] [--project-prefix <prefix>] [--repo-root <path>]
 *
 * Tools: claude, cursor, gemini, vscode, codex
 */

const fs = require('fs');
const path = require('path');

// Parse command line arguments
function parseArgs() {
    const args = process.argv.slice(2);
    const result = {
        tool: null,
        output: null,
        sources: [],
        projectPrefix: 'ag-grid',
        repoRoot: process.cwd(),
    };

    for (let i = 0; i < args.length; i++) {
        switch (args[i]) {
            case '--tool':
                result.tool = args[++i];
                break;
            case '--output':
                result.output = args[++i];
                break;
            case '--sources':
                result.sources = args[++i].split(',').filter(Boolean);
                break;
            case '--project-prefix':
                result.projectPrefix = args[++i];
                break;
            case '--repo-root':
                result.repoRoot = args[++i];
                break;
        }
    }

    return result;
}

// Read and parse a JSON file, returning null if it doesn't exist
function readJsonFile(filePath) {
    try {
        const content = fs.readFileSync(filePath, 'utf8');
        return JSON.parse(content);
    } catch {
        return null;
    }
}

// Merge MCP configurations from multiple sources
// Later sources override earlier ones
function mergeMcpConfigs(sources) {
    const merged = { mcpServers: {} };

    for (const source of sources) {
        const config = readJsonFile(source);
        if (config?.mcpServers) {
            Object.assign(merged.mcpServers, config.mcpServers);
        }
    }

    return merged;
}

// Transform config for specific tools
const toolTransformers = {
    // Claude and Cursor use standard format
    claude: (config) => config,
    cursor: (config) => config,

    // Gemini doesn't support the 'type' field
    gemini: (config) => {
        const result = { mcpServers: {} };
        for (const [name, server] of Object.entries(config.mcpServers)) {
            const { type, ...rest } = server;
            result.mcpServers[name] = rest;
        }
        return result;
    },

    // VS Code uses 'servers' instead of 'mcpServers'
    vscode: (config) => {
        return { servers: config.mcpServers };
    },

    // Codex uses TOML format with project prefix
    codex: (config, options) => {
        // Return a special format that will be converted to TOML
        return {
            _format: 'toml',
            servers: Object.entries(config.mcpServers).map(([name, server]) => ({
                name: `${options.projectPrefix}-${name}`,
                ...server,
                cwd: options.repoRoot,
            })),
        };
    },
};

// Convert Codex config to TOML string
function toToml(config, projectName) {
    const lines = [];
    lines.push(`# ${projectName} MCP Servers (auto-generated)`);

    for (const server of config.servers) {
        lines.push('');
        lines.push(`[mcp_servers."${server.name}"]`);
        lines.push(`command = "${server.command}"`);
        lines.push(`cwd = "${server.cwd}"`);

        if (server.args?.length) {
            const argsStr = server.args.map((a) => `"${a}"`).join(', ');
            lines.push(`args = [${argsStr}]`);
        } else {
            lines.push('args = []');
        }

        if (server.env && Object.keys(server.env).length > 0) {
            const envStr = Object.entries(server.env)
                .map(([k, v]) => `${k} = "${v}"`)
                .join(', ');
            lines.push(`env = { ${envStr} }`);
        }

        if (server.type) {
            lines.push(`type = "${server.type}"`);
        }
    }

    return lines.join('\n') + '\n';
}

// Read existing Codex config and preserve non-project sections
function mergeCodexConfig(existingPath, newToml, projectPrefix) {
    if (!fs.existsSync(existingPath)) {
        return newToml;
    }

    const existing = fs.readFileSync(existingPath, 'utf8');
    const lines = existing.split('\n');
    const preserved = [];
    let inProjectSection = false;

    for (const line of lines) {
        // Check if entering a project MCP server section
        if (
            line.startsWith(`[mcp_servers."${projectPrefix}-`) ||
            line.includes('MCP Servers (auto-generated)')
        ) {
            inProjectSection = true;
            continue;
        }

        // Check if entering a different section
        if (line.match(/^\[.*\]/) && !line.startsWith(`[mcp_servers."${projectPrefix}-`)) {
            inProjectSection = false;
        }

        if (!inProjectSection) {
            preserved.push(line);
        }
    }

    // Remove trailing empty lines from preserved content
    while (preserved.length > 0 && preserved[preserved.length - 1].trim() === '') {
        preserved.pop();
    }

    return preserved.join('\n') + '\n' + newToml;
}

// Main function
function main() {
    const options = parseArgs();

    if (!options.tool || !options.output) {
        console.error('Usage: mcp-config.js --tool <tool> --output <path> [--sources <paths>]');
        console.error('Tools: claude, cursor, gemini, vscode, codex');
        process.exit(1);
    }

    const transformer = toolTransformers[options.tool];
    if (!transformer) {
        console.error(`Unknown tool: ${options.tool}`);
        console.error('Valid tools: claude, cursor, gemini, vscode, codex');
        process.exit(1);
    }

    // If no sources provided, exit silently (no MCP config to process)
    if (options.sources.length === 0) {
        return;
    }

    // Filter to only existing source files
    const existingSources = options.sources.filter((s) => fs.existsSync(s));
    if (existingSources.length === 0) {
        return;
    }

    // Merge all source configs
    const merged = mergeMcpConfigs(existingSources);

    // Apply tool-specific transformation
    const transformed = transformer(merged, options);

    // Ensure output directory exists
    const outputDir = path.dirname(options.output);
    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
    }

    // Write output
    if (transformed._format === 'toml') {
        // Codex TOML format
        const projectName = options.projectPrefix
            .split('-')
            .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
            .join(' ');
        const tomlContent = toToml(transformed, projectName);
        const finalContent = mergeCodexConfig(options.output, tomlContent, options.projectPrefix);
        fs.writeFileSync(options.output, finalContent);
    } else {
        // JSON format
        fs.writeFileSync(options.output, JSON.stringify(transformed, null, 2) + '\n');
    }

    console.log(`✓ Generated ${options.tool} MCP config: ${options.output}`);
}

main();
