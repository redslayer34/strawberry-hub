// Each MCP tool against a fake bridge, and the server's tool registration.

import { test } from "node:test";
import assert from "node:assert/strict";
import { TOOLS, registerTools, luaString, RAW } from "../src/tools.js";
import { FakeBridge } from "./helpers.js";

const tool = (name) => TOOLS.find((entry) => entry.name === name);

test("every tool has a name, a description and a runner", () => {
  const names = new Set();
  for (const entry of TOOLS) {
    assert.ok(entry.name && entry.description && typeof entry.run === "function", entry.name);
    assert.ok(!names.has(entry.name), `duplicate ${entry.name}`);
    names.add(entry.name);
  }
});

test("tools map to their in-game ops", async () => {
  const bridge = new FakeBridge({ exec: { returns: [2] }, tree: { name: "Map" }, player: { level: 1500 } });
  assert.deepEqual(await tool("execute_lua").run(bridge, { code: "return 1+1" }), { returns: [2] });
  assert.equal(bridge.calls.at(-1).op, "exec");
  assert.equal(bridge.calls.at(-1).timeout, 30_000);
  await tool("explore").run(bridge, { path: "game.Workspace.Map" });
  assert.deepEqual(bridge.calls.at(-1), { op: "tree", args: { path: "game.Workspace.Map", depth: 1, limit: 200 }, timeout: undefined });
  assert.deepEqual(await tool("get_player").run(bridge, {}), { level: 1500 });
  await tool("fire_remote").run(bridge, { path: "game.ReplicatedStorage.Remotes.CommF_", args: ["GetUnlockables"], invoke: true });
  assert.deepEqual(bridge.calls.at(-1).args, { path: "game.ReplicatedStorage.Remotes.CommF_", args: ["GetUnlockables"], invoke: true });
});

test("the console tool filters and limits", async () => {
  const bridge = new FakeBridge();
  bridge.console.push({ text: "Loaded", type: "output" });
  bridge.console.push({ text: "Failed to load", type: "error" });
  bridge.console.push({ text: "loaded again", type: "output" });
  const errors = await tool("get_console").run(bridge, { type: "error" });
  assert.deepEqual(errors.map((line) => line.text), ["Failed to load"]);
  const loaded = await tool("get_console").run(bridge, { filter: "LOADED", limit: 1 });
  assert.deepEqual(loaded.map((line) => line.text), ["loaded again"]);
});

test("remote spy logs: executor calls hidden by default, filters by name and direction", async () => {
  const bridge = new FakeBridge();
  bridge.remotes.push({ direction: "Outgoing", remote: "game.ReplicatedStorage.Remotes.CommF_", args: ["requestEntrance"] });
  bridge.remotes.push({ direction: "Incoming", remote: "game.ReplicatedStorage.Remotes.Notify", args: ["hi"] });
  bridge.remotes.push({ direction: "Outgoing", remote: "game.ReplicatedStorage.Remotes.CommF_", args: ["x"], isExecutor: true });
  const all = await tool("remote_spy_logs").run(bridge, {});
  assert.equal(all.length, 2);
  const byArg = await tool("remote_spy_logs").run(bridge, { name: "requestentrance" });
  assert.equal(byArg.length, 1);
  const incoming = await tool("remote_spy_logs").run(bridge, { direction: "Incoming" });
  assert.deepEqual(incoming.map((call) => call.args[0]), ["hi"]);
  const withExecutor = await tool("remote_spy_logs").run(bridge, { includeExecutor: true });
  assert.equal(withExecutor.length, 3);
});

test("remote spy clear empties the bridge buffer even when the game cannot answer", async () => {
  const bridge = new FakeBridge({ cobaltClear: new Error("no game") });
  bridge.remotes.push({ remote: "x" });
  const result = await tool("remote_spy_clear").run(bridge, {});
  assert.equal(bridge.remotes.since(0).length, 0);
  assert.equal(result.bridgeCleared, true);
});

test("hub_load builds the loader from the branch, with the Kaitun config", async () => {
  const bridge = new FakeBridge({ exec: { returns: ["loading"] } });
  await tool("hub_load").run(bridge, { which: "kaitun", config: { Team: "Marines" } });
  const code = bridge.calls.at(-1).args.code;
  assert.ok(code.includes(`${RAW}/StrawberryKaitun.lua`));
  assert.ok(code.includes('getgenv().StrawberryKaitun = game:GetService("HttpService"):JSONDecode([[{"Team":"Marines"}]])'));
  await tool("hub_load").run(bridge, { which: "hub" });
  assert.ok(bridge.calls.at(-1).args.code.includes(`${RAW}/StrawberryHub.lua`));
});

test("Lua long strings survive closing brackets in the text", () => {
  assert.equal(luaString("a]]b"), "[=[a]]b]=]");
  assert.equal(luaString("plain"), "[[plain]]");
});

test("registerTools wraps results as text and errors as isError", async () => {
  const registered = new Map();
  const server = { registerTool: (name, meta, handler) => registered.set(name, { meta, handler }) };
  const bridge = new FakeBridge({ player: new Error("no local player") });
  registerTools(server, bridge);
  assert.equal(registered.size, TOOLS.length);
  const status = await registered.get("roblox_status").handler({});
  assert.equal(JSON.parse(status.content[0].text).connected, true);
  const failed = await registered.get("get_player").handler({});
  assert.equal(failed.isError, true);
  assert.match(failed.content[0].text, /no local player/);
});
