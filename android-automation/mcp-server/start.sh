#!/data/data/com.termux/files/usr/bin/bash
# Run this in Termux (NOT inside Ubuntu proot) before starting Claude Code

cd "$(dirname "$0")"
echo "Starting Android MCP Server..."
node server.js
