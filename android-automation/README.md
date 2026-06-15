# Android AI Automation with Claude Code

An MCP (Model Context Protocol) server that gives Claude Code direct access to
Android hardware and system features via Termux:API. Claude can call these tools
autonomously — no copy-paste, no manual steps.

## Available Tools

| Tool | What it does |
|---|---|
| `battery_status` | Battery level, health, temperature, charging state |
| `get_location` | GPS coordinates (lat, lng, altitude) |
| `send_notification` | Push a notification to the device |
| `clipboard_get` | Read current clipboard content |
| `clipboard_set` | Write text to clipboard |
| `vibrate` | Vibrate the device for N milliseconds |
| `torch` | Turn flashlight on or off |
| `wifi_info` | SSID, IP address, signal strength |
| `send_sms` | Send an SMS to a phone number |
| `take_photo` | Capture photo from front or back camera |
| `device_info` | Device model, IMEI, carrier |
| `list_contacts` | All contacts on the device |

## Architecture

```
Termux (native)          Ubuntu proot
  MCP Server     <--->   Claude Code
  port 8080              ~/.claude.json → SSE
  termux-api cmds
  Android system
```

The server runs in native Termux (where termux-api works).
Claude Code runs in Ubuntu proot and connects via localhost:8080.
Both share the same network stack so localhost is accessible from both sides.

## Setup

### 1. Prerequisites

- Termux from F-Droid
- Termux:API app from F-Droid
- `pkg install termux-api` (in Termux)
- Node.js in Termux: `pkg install nodejs-lts`
- Claude Code installed in Ubuntu proot (see docs/claude-code-termux-runbook.md)

### 2. Install the MCP server

In Termux (not inside Ubuntu):

```bash
cd android-automation/mcp-server
npm install
```

### 3. Start the MCP server

Open a Termux session and run:

```bash
cd android-automation/mcp-server
node server.js
```

Keep this session open. The server must be running before you start Claude Code.

### 4. Connect Claude Code

Inside Ubuntu proot, register the MCP server:

```bash
claude mcp add android-tools --transport sse http://localhost:8080/sse
```

Or add it manually to `~/.claude.json`:

```json
{
  "mcpServers": {
    "android-tools": {
      "type": "sse",
      "url": "http://localhost:8080/sse"
    }
  }
}
```

### 5. Use it

Start Claude Code inside Ubuntu:

```bash
claude
```

Claude now has access to all Android tools. Try asking:

- "What is my battery percentage?"
- "Send a notification saying the build is done"
- "Where am I right now?"
- "Take a photo with the back camera"
- "Send an SMS to +1234567890 saying hello"

## Daily Workflow

**Terminal 1 (Termux native):**
```bash
cd android-automation/mcp-server && node server.js
```

**Terminal 2 (Ubuntu proot):**
```bash
proot-distro login ubuntu
claude
```
