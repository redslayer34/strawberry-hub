// The real server over stdio, driven by the SDK's MCP client.

import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const server = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "src", "server.js");

test("the server lists its tools and answers without a game", async () => {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [server],
    env: { ...process.env, BRIDGE_PORT: "0" },
    stderr: "ignore",
  });
  const client = new Client({ name: "test", version: "1.0.0" });
  await client.connect(transport);
  try {
    const { tools } = await client.listTools();
    const names = tools.map((tool) => tool.name);
    for (const name of ["roblox_status", "get_loader", "execute_lua", "remote_spy_logs", "hub_status"]) {
      assert.ok(names.includes(name), name);
    }
    const status = await client.callTool({ name: "roblox_status", arguments: {} });
    assert.equal(JSON.parse(status.content[0].text).connected, false);
    const loader = await client.callTool({ name: "get_loader", arguments: { address: "192.168.1.20" } });
    assert.match(loader.content[0].text, /^loadstring\(\(request or http_request\)\(\{Url="http:\/\/192\.168\.1\.20:\d+\/bridge\.lua\?token=\w+",Method="GET"\}\)\.Body\)\(\)$/);
    const exec = await client.callTool({ name: "execute_lua", arguments: { code: "return 1", timeout: 1 } });
    assert.equal(exec.isError, true);
    assert.match(exec.content[0].text, /no game connected/);
  } finally {
    await client.close();
  }
});
