#!/usr/bin/env node
// Strawberry MCP: Claude Code <-> (stdio) this server <-> (HTTP bridge) the
// executor in game. stdout belongs to the MCP protocol: logs go to stderr.
//
//   BRIDGE_PORT   bridge port (default 7777)
//   COBALT_PATH   the user's Cobalt.luau (default mcp/Cobalt.luau)

import path from "node:path";
import { fileURLToPath } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { Bridge, lanAddresses, loadToken } from "./bridge.js";
import { registerTools } from "./tools.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const log = (message) => process.stderr.write(`[strawberry-mcp] ${message}\n`);

const bridge = new Bridge({
  port: process.env.BRIDGE_PORT !== undefined ? Number(process.env.BRIDGE_PORT) : 7777,
  token: loadToken(path.join(root, ".bridge-token")),
  luaPath: path.join(root, "lua", "bridge.lua"),
  cobaltPath: process.env.COBALT_PATH || path.join(root, "Cobalt.luau"),
  log,
});

try {
  await bridge.start();
  log(`bridge listening on port ${bridge.port} (LAN: ${lanAddresses().join(", ") || "none"})`);
  log(`in the executor: ${bridge.loader()}`);
} catch (error) {
  log(`bridge could not start on port ${bridge.port}: ${error.message}`);
}

const server = new McpServer({ name: "strawberry-roblox", version: "1.0.0" });
registerTools(server, bridge);
await server.connect(new StdioServerTransport());
