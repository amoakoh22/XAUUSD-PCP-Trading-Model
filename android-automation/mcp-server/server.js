import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import { ListToolsRequestSchema, CallToolRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { spawn } from "child_process";
import http from "http";

function runTermux(cmd, args = []) {
  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, args);
    let stdout = "";
    let stderr = "";
    proc.stdout.on("data", (d) => (stdout += d));
    proc.stderr.on("data", (d) => (stderr += d));
    proc.on("close", (code) => {
      if (code !== 0 && stderr) reject(new Error(stderr.trim()));
      else resolve(stdout.trim());
    });
  });
}

const TOOLS = [
  {
    name: "battery_status",
    description: "Get the current battery level, health, temperature and charging status of the device",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "get_location",
    description: "Get the current GPS location of the device (latitude, longitude, altitude)",
    inputSchema: {
      type: "object",
      properties: {
        provider: {
          type: "string",
          enum: ["gps", "network", "passive"],
          description: "Location provider — gps is most accurate (default: gps)",
        },
      },
    },
  },
  {
    name: "send_notification",
    description: "Push a notification to the Android device",
    inputSchema: {
      type: "object",
      properties: {
        title: { type: "string", description: "Notification title" },
        content: { type: "string", description: "Notification body text" },
      },
      required: ["title", "content"],
    },
  },
  {
    name: "clipboard_get",
    description: "Read the current text content of the Android clipboard",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "clipboard_set",
    description: "Write text to the Android clipboard",
    inputSchema: {
      type: "object",
      properties: {
        text: { type: "string", description: "Text to copy to clipboard" },
      },
      required: ["text"],
    },
  },
  {
    name: "vibrate",
    description: "Vibrate the device",
    inputSchema: {
      type: "object",
      properties: {
        duration_ms: {
          type: "number",
          description: "Vibration duration in milliseconds (default: 300)",
        },
      },
    },
  },
  {
    name: "torch",
    description: "Turn the device flashlight on or off",
    inputSchema: {
      type: "object",
      properties: {
        on: { type: "boolean", description: "true to turn on, false to turn off" },
      },
      required: ["on"],
    },
  },
  {
    name: "wifi_info",
    description: "Get current WiFi connection details (SSID, IP, signal strength)",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "send_sms",
    description: "Send an SMS text message to a phone number",
    inputSchema: {
      type: "object",
      properties: {
        number: { type: "string", description: "Recipient phone number" },
        message: { type: "string", description: "SMS message text" },
      },
      required: ["number", "message"],
    },
  },
  {
    name: "take_photo",
    description: "Take a photo with the device camera and save it to a file",
    inputSchema: {
      type: "object",
      properties: {
        camera: {
          type: "number",
          enum: [0, 1],
          description: "0 = back camera, 1 = front camera (default: 0)",
        },
        output_file: {
          type: "string",
          description: "Output file path (default: /sdcard/photo.jpg)",
        },
      },
    },
  },
  {
    name: "device_info",
    description: "Get device hardware and telephony information (model, IMEI, carrier)",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "list_contacts",
    description: "List all contacts stored on the device",
    inputSchema: { type: "object", properties: {} },
  },
];

async function handleTool(name, args) {
  switch (name) {
    case "battery_status":
      return await runTermux("termux-battery-status");

    case "get_location": {
      const provider = args?.provider || "gps";
      return await runTermux("termux-location", ["-p", provider]);
    }

    case "send_notification":
      await runTermux("termux-notification", [
        "--title", args.title,
        "--content", args.content,
      ]);
      return "Notification sent";

    case "clipboard_get":
      return await runTermux("termux-clipboard-get");

    case "clipboard_set":
      await runTermux("termux-clipboard-set", [args.text]);
      return "Clipboard updated";

    case "vibrate": {
      const duration = String(args?.duration_ms || 300);
      await runTermux("termux-vibrate", ["-d", duration]);
      return `Vibrated for ${duration}ms`;
    }

    case "torch":
      await runTermux("termux-torch", [args.on ? "on" : "off"]);
      return `Torch turned ${args.on ? "on" : "off"}`;

    case "wifi_info":
      return await runTermux("termux-wifi-connectioninfo");

    case "send_sms":
      await runTermux("termux-sms-send", ["-n", args.number, args.message]);
      return `SMS sent to ${args.number}`;

    case "take_photo": {
      const camera = String(args?.camera ?? 0);
      const file = args?.output_file || "/sdcard/photo.jpg";
      await runTermux("termux-camera-photo", ["-c", camera, file]);
      return `Photo saved to ${file}`;
    }

    case "device_info":
      return await runTermux("termux-telephony-deviceinfo");

    case "list_contacts":
      return await runTermux("termux-contact-list");

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

const server = new Server(
  { name: "android-tools", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  try {
    const result = await handleTool(name, args);
    return {
      content: [{ type: "text", text: typeof result === "string" ? result : JSON.stringify(result, null, 2) }],
    };
  } catch (err) {
    return {
      content: [{ type: "text", text: `Error: ${err.message}` }],
      isError: true,
    };
  }
});

const httpServer = http.createServer();
const transports = {};

httpServer.on("request", async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");

  if (req.url === "/sse" && req.method === "GET") {
    const transport = new SSEServerTransport("/messages", res);
    transports[transport.sessionId] = transport;
    res.on("close", () => delete transports[transport.sessionId]);
    await server.connect(transport);
  } else if (req.url?.startsWith("/messages") && req.method === "POST") {
    const sessionId = new URL(req.url, "http://localhost").searchParams.get("sessionId");
    const transport = transports[sessionId];
    if (transport) {
      await transport.handlePostMessage(req, res);
    } else {
      res.writeHead(404);
      res.end("Session not found");
    }
  } else {
    res.writeHead(200);
    res.end("Android MCP Server is running. SSE endpoint: /sse\n");
  }
});

const PORT = 8080;
httpServer.listen(PORT, "127.0.0.1", () => {
  console.log(`Android MCP Server running on http://localhost:${PORT}`);
  console.log(`Connect Claude Code to: http://localhost:${PORT}/sse`);
});
