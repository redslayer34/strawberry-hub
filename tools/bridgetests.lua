--=============================================================================
-- BRIDGE TESTS — mcp/lua/bridge.lua, the in-game side of Strawberry MCP
--=============================================================================
--  Run by tools/test.py with BRIDGE_TEST set: the bridge builds its module
--  (STRAWBERRY_BRIDGE) and does not start its loops.
--=============================================================================

local passed, failed = 0, 0
local failures = {}

local function check(name, condition, detail)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = name .. (detail ~= nil and ("  -- " .. tostring(detail)) or "")
    end
end

local function eq(name, actual, expected)
    check(name, actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local Bridge = STRAWBERRY_BRIDGE
check("module built in test mode", type(Bridge) == "table" and Bridge.ops ~= nil)

local players = game:GetService("Players")
local player = newInstance("Player", "Tester", players)
players.LocalPlayer = player
local map = newInstance("Folder", "Map", workspace)
local castle = newInstance("Model", "Boat Castle", map)
local portal = newInstance("Part", "MapTeleportA", castle)
portal.Position = Vector3.new(1, 2, 3)
portal:SetAttribute("Door", "A")

-- Paths
do
    local parts = Bridge.splitPath('game.Workspace.Map["Boat Castle"]/MapTeleportA')
    eq("split: quoted name kept", parts[4], "Boat Castle")
    eq("split: slash works", parts[5], "MapTeleportA")
    eq("resolve: quoted path", Bridge.resolve('game.Workspace.Map["Boat Castle"].MapTeleportA'), portal)
    eq("resolve: workspace alias", Bridge.resolve("workspace.Map"), map)
    eq("resolve: property child (LocalPlayer)", Bridge.resolve("Players.LocalPlayer"), player)
    local missing, why = Bridge.resolve("game.Workspace.Nope")
    check("resolve: missing says where", missing == nil and tostring(why):find("Nope", 1, true) ~= nil, why)
    eq("path: data model prefix", Bridge.path(portal), "game.Workspace.Map.Boat Castle.MapTeleportA")
end

-- Encoding
do
    local encoded = Bridge.encode({ portal, Vector3.new(1.234, 2, 3), "x", 5 })
    eq("encode: instance path", encoded[1]["$instance"], "game.Workspace.Map.Boat Castle.MapTeleportA")
    eq("encode: vector rounded", encoded[2]["$vector3"][1], 1.23)
    eq("encode: string kept", encoded[3], "x")
    local cyclic = {}
    cyclic.self = cyclic
    eq("encode: cycle cut", Bridge.encode(cyclic).self, "<cycle>")
    local deep = { a = { b = { c = { d = { e = 1 } } } } }
    eq("encode: depth cut", Bridge.encode(deep).a.b.c.d, "<table>")
    local list = Bridge.encodeList({ 1, nil, 3, n = 3 })
    check("encodeList: nil kept as a marker", list[2]["$nil"] == true and list[3] == 3)
    local decoded = Bridge.decode({ { ["$vector3"] = { 1, 2, 3 } }, { ["$instance"] = "game.Workspace.Map" } })
    check("decode: vector", decoded[1].X == 1 and decoded[1].Z == 3)
    eq("decode: instance", decoded[2], map)
end

-- exec
do
    local result = Bridge.ops.exec({ code = 'print("hello", 1) warn("careful") return 1 + 1, "two"' })
    eq("exec: first return", result.returns[1], 2)
    eq("exec: second return", result.returns[2], "two")
    eq("exec: print captured", result.output[1], "hello\t1")
    eq("exec: warn captured", result.output[2], "[warn] careful")
    local failing = Bridge.ops.exec({ code = 'error("boom")' })
    check("exec: runtime error", failing.error and failing.error:find("boom", 1, true) ~= nil, failing.error)
    local broken = Bridge.ops.exec({ code = "return +" })
    check("exec: compile error", broken.error and broken.error:find("compile", 1, true) ~= nil, broken.error)
end

-- tree / props / find
do
    local tree = Bridge.ops.tree({ path = "game.Workspace.Map", depth = 2 })
    eq("tree: child", tree.items[1].name, "Boat Castle")
    eq("tree: grandchild", tree.items[1].items[1].name, "MapTeleportA")
    local props = Bridge.ops.props({ path = 'Workspace.Map["Boat Castle"].MapTeleportA' })
    eq("props: position", props.Position and props.Position["$vector3"][2], 2)
    eq("props: attributes", props.Attributes and props.Attributes.Door, "A")
    local found = Bridge.ops.find({ name = "teleport", root = "game.Workspace" })
    eq("find: by name", found[1] and found[1].path, "game.Workspace.Map.Boat Castle.MapTeleportA")
    local byClass = Bridge.ops.find({ className = "Model", root = "game.Workspace" })
    eq("find: by class", #byClass, 1)
    local ok = pcall(Bridge.ops.tree, { path = "game.Workspace.Nope" })
    check("tree: missing path errors", not ok)
end

-- fire
do
    local remotes = newInstance("Folder", "Remotes", game:GetService("ReplicatedStorage"))
    local commF = newInstance("RemoteFunction", "CommF_", remotes)
    commF.OnInvoke = function(action, where) return action .. ":" .. tostring(where.X) end
    local result = Bridge.ops.fire({ path = "game.ReplicatedStorage.Remotes.CommF_", invoke = true,
        args = { "requestEntrance", { ["$vector3"] = { 5, 6, 7 } } } })
    eq("fire: invoke result", result.returns[1], "requestEntrance:5")
    local event = newInstance("RemoteEvent", "Ping", remotes)
    Bridge.ops.fire({ path = "game.ReplicatedStorage.Remotes.Ping", args = { "a" } })
    eq("fire: FireServer args", event.Fired and event.Fired[1][1], "a")
end

-- player
do
    local data = newInstance("Folder", "Data", player)
    newInstance("IntValue", "Level", data).Value = 1500
    newInstance("StringValue", "Race", data).Value = "Human"
    local info = Bridge.ops.player()
    eq("player: level", info.level, 1500)
    eq("player: race", info.race, "Human")
    eq("player: sea from place", info.sea, 2)
end

-- Cobalt watcher
do
    local env = getgenv and getgenv() or _G
    local remote = newInstance("RemoteFunction", "CommF_", game:GetService("ReplicatedStorage"))
    local log = { Instance = remote, Calls = {} }
    log.ClearCalls = function(self) self.Calls = {} end
    env.Cobalt = { shared = { Logs = { Outgoing = { ["id1"] = log }, Incoming = {} } } }
    log.Calls[1] = { Arguments = { "requestEntrance", Vector3.new(1, 2, 3), n = 2 }, CreationTime = 10,
        Origin = portal, Line = 51, InvokeResult = { Vector3.new(4, 5, 6), n = 1 } }
    local first = Bridge.collectCobalt()
    eq("cobalt: one call", #first, 1)
    eq("cobalt: method", first[1].method, "InvokeServer")
    eq("cobalt: first arg", first[1].args[1], "requestEntrance")
    eq("cobalt: result", first[1].result[1]["$vector3"][3], 6)
    eq("cobalt: origin", first[1].origin, "game.Workspace.Map.Boat Castle.MapTeleportA")
    eq("cobalt: nothing new", #Bridge.collectCobalt(), 0)
    log.Calls[2] = { Arguments = { "GetUnlockables", n = 1 }, IsExecutor = true }
    local second = Bridge.collectCobalt()
    check("cobalt: only the new call", #second == 1 and second[1].args[1] == "GetUnlockables" and second[1].isExecutor)
    Bridge.ops.cobaltClear()
    eq("cobalt: cleared", #log.Calls, 0)
    log.Calls[1] = { Arguments = { "again", n = 1 } }
    local after = Bridge.collectCobalt()
    check("cobalt: after a clear, starts over", #after == 1 and after[1].args[1] == "again")
    env.Cobalt = nil
end

-- hub
do
    local env = getgenv and getgenv() or _G
    eq("hub: none loaded", Bridge.ops.hub().loaded, false)
    local store = {}
    env.StrawberryHub = { Version = "x", Settings = { set = function(k, v) store[k] = v end, get = function(k) return store[k] end } }
    local result = Bridge.ops.setting({ key = "AutoFarmLevel", value = true })
    check("setting: set through the hub", store.AutoFarmLevel == true and result.value == true)
    eq("hub: loaded without Require", Bridge.ops.hub().which, "hub")
    env.StrawberryHub = nil
end

for _, line in ipairs(failures) do print("  FAIL " .. line) end
print(string.format("bridge: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
