// The MCP tools: each one is a bridge call (an op run in game) or a read of
// the buffers the game fills (console, remote calls).

import { z } from "zod";

export const RAW = "https://raw.githubusercontent.com/redslayer34/strawberry-hub/claude/repo-exploration-ez26bn";

const text = (value) => ({
  content: [{ type: "text", text: typeof value === "string" ? value : JSON.stringify(value, null, 2) }],
});

const lower = (value) => String(value ?? "").toLowerCase();

// A Lua string literal (long brackets cannot be broken by the content).
export function luaString(value) {
  const source = String(value);
  let level = 0;
  while (source.includes("]" + "=".repeat(level) + "]")) level += 1;
  const eq = "=".repeat(level);
  return `[${eq}[${source}]${eq}]`;
}

export const TOOLS = [
  {
    name: "roblox_status",
    description: "Is a game connected to the bridge? Place, sea, player, executor, and whether Strawberry Hub, the Kaitun and Cobalt are loaded.",
    schema: {},
    run: async (bridge) => ({
      connected: bridge.connected(),
      lastSeenSecondsAgo: bridge.lastSeen ? Math.round((Date.now() - bridge.lastSeen) / 1000) : null,
      session: bridge.session,
      consoleLines: bridge.console.seq,
      remoteCalls: bridge.remotes.seq,
    }),
  },
  {
    name: "get_loader",
    description: "The one line to run in the executor (Arceus X) to connect the game to this bridge. Uses the PC's LAN address unless `address` is given.",
    schema: { address: z.string().optional().describe("IP the emulator reaches the PC at (default: first LAN IPv4)") },
    run: async (bridge, { address }) => bridge.loader(address),
  },
  {
    name: "execute_lua",
    description: "Runs Luau in the game client (executor environment). Returns the values returned, everything printed, and the error if any. Use `return` to get values back.",
    schema: {
      code: z.string().describe("Luau source"),
      timeout: z.number().min(1).max(300).optional().describe("seconds (default 30)"),
    },
    run: async (bridge, { code, timeout = 30 }) => bridge.call("exec", { code }, timeout * 1000),
  },
  {
    name: "get_console",
    description: "Game console lines (prints, warnings, errors from LogService), newest last.",
    schema: {
      since: z.number().optional().describe("only lines after this sequence number"),
      filter: z.string().optional().describe("substring, case-insensitive"),
      type: z.enum(["output", "info", "warning", "error"]).optional(),
      limit: z.number().min(1).max(2000).optional().describe("default 100"),
    },
    run: async (bridge, { since, filter, type, limit = 100 }) => {
      let lines = bridge.console.since(since);
      if (filter) lines = lines.filter((line) => lower(line.text).includes(lower(filter)));
      if (type) lines = lines.filter((line) => lower(line.type).includes(type));
      return lines.slice(-limit);
    },
  },
  {
    name: "explore",
    description: "The children of an instance, as a tree (name, class, child count). Paths look like game.Workspace.Map or Players.LocalPlayer.Data.",
    schema: {
      path: z.string().optional().describe("default game"),
      depth: z.number().min(1).max(5).optional().describe("default 1"),
      limit: z.number().min(1).max(1000).optional().describe("children per level, default 200"),
    },
    run: async (bridge, { path = "game", depth = 1, limit = 200 }) => bridge.call("tree", { path, depth, limit }),
  },
  {
    name: "get_properties",
    description: "Properties and attributes of an instance (common ones, plus any listed in `props`).",
    schema: {
      path: z.string(),
      props: z.array(z.string()).optional(),
    },
    run: async (bridge, { path, props }) => bridge.call("props", { path, props: props || [] }),
  },
  {
    name: "find_instances",
    description: "Descendants of `root` whose name contains `name` and/or whose class is `className`.",
    schema: {
      name: z.string().optional(),
      className: z.string().optional(),
      root: z.string().optional().describe("default game.Workspace"),
      limit: z.number().min(1).max(500).optional().describe("default 50"),
    },
    run: async (bridge, { name, className, root = "game.Workspace", limit = 50 }) =>
      bridge.call("find", { name, className, root, limit }, 60_000),
  },
  {
    name: "get_script_source",
    description: "The decompiled source of a LocalScript / ModuleScript (needs the executor's decompile).",
    schema: { path: z.string() },
    run: async (bridge, { path }) => bridge.call("source", { path }, 60_000),
  },
  {
    name: "get_player",
    description: "The local player: position, level, sea, Beli, fragments, race, fruit, team, health, tools held.",
    schema: {},
    run: async (bridge) => bridge.call("player"),
  },
  {
    name: "fire_remote",
    description: "FireServer / InvokeServer on a remote. Args are JSON; tagged values are decoded: {\"$vector3\":[x,y,z]}, {\"$cframe\":[x,y,z]}, {\"$instance\":\"game.Workspace.X\"}.",
    schema: {
      path: z.string().describe("e.g. game.ReplicatedStorage.Remotes.CommF_"),
      args: z.array(z.any()).optional(),
      invoke: z.boolean().optional().describe("InvokeServer (RemoteFunction) instead of FireServer"),
    },
    run: async (bridge, { path, args = [], invoke = false }) => bridge.call("fire", { path, args, invoke }),
  },
  {
    name: "remote_spy_start",
    description: "Loads Cobalt (the user's Cobalt.luau, served by this bridge) in game and starts sending every remote call it logs to this bridge.",
    schema: {},
    run: async (bridge) => bridge.call("cobalt", {}, 120_000),
  },
  {
    name: "remote_spy_logs",
    description: "Remote calls logged by Cobalt, newest last: direction, remote path, method, arguments, result, calling script and line.",
    schema: {
      name: z.string().optional().describe("remote path or argument text, substring, case-insensitive"),
      direction: z.enum(["Outgoing", "Incoming"]).optional(),
      includeExecutor: z.boolean().optional().describe("include calls made by scripts run in the executor (default false)"),
      since: z.number().optional(),
      limit: z.number().min(1).max(1000).optional().describe("default 50"),
    },
    run: async (bridge, { name, direction, includeExecutor = false, since, limit = 50 }) => {
      let calls = bridge.remotes.since(since);
      if (!includeExecutor) calls = calls.filter((call) => !call.isExecutor);
      if (direction) calls = calls.filter((call) => call.direction === direction);
      if (name) {
        const wanted = lower(name);
        calls = calls.filter((call) => lower(call.remote).includes(wanted) || lower(JSON.stringify(call.args)).includes(wanted));
      }
      return calls.slice(-limit);
    },
  },
  {
    name: "remote_spy_clear",
    description: "Forgets the remote calls kept by the bridge and clears Cobalt's own logs.",
    schema: {},
    run: async (bridge) => {
      bridge.remotes.clear();
      return bridge.call("cobaltClear").catch((error) => ({ bridgeCleared: true, game: String(error.message) }));
    },
  },
  {
    name: "hub_load",
    description: "Loads Strawberry Hub or the Strawberry Kaitun (this repo's branch) in game. For the Kaitun, `config` becomes getgenv().StrawberryKaitun.",
    schema: {
      which: z.enum(["hub", "kaitun"]),
      config: z.record(z.any()).optional(),
    },
    run: async (bridge, { which, config }) => {
      const file = which === "kaitun" ? "StrawberryKaitun.lua" : "StrawberryHub.lua";
      const setup = which === "kaitun" && config
        ? `getgenv().StrawberryKaitun = game:GetService("HttpService"):JSONDecode(${luaString(JSON.stringify(config))})\n`
        : "";
      const code = `${setup}task.spawn(function() loadstring(game:HttpGet("${RAW}/${file}"))() end)\nreturn "loading ${file}"`;
      return bridge.call("exec", { code }, 60_000);
    },
  },
  {
    name: "hub_status",
    description: "What Strawberry Hub / the Kaitun is doing: Kaitun task and plan, farm status, quest read, travel log.",
    schema: {},
    run: async (bridge) => bridge.call("hub"),
  },
  {
    name: "hub_set_setting",
    description: "Sets one Strawberry Hub setting (Settings.set) in the running hub or Kaitun.",
    schema: { key: z.string(), value: z.any() },
    run: async (bridge, { key, value }) => bridge.call("setting", { key, value }),
  },
];

export function registerTools(server, bridge) {
  for (const tool of TOOLS) {
    server.registerTool(
      tool.name,
      { description: tool.description, inputSchema: tool.schema },
      async (args) => {
        try {
          return text(await tool.run(bridge, args || {}));
        } catch (error) {
          return { ...text(`Error: ${error.message || error}`), isError: true };
        }
      },
    );
  }
}
