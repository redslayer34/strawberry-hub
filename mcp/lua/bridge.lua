--=============================================================================
-- STRAWBERRY BRIDGE — the in-game side of Strawberry MCP
--=============================================================================
--  Served by the MCP server (GET /bridge.lua) with its address and token
--  filled in, and run in the executor:
--
--      loadstring((request or http_request)({Url="http://<PC IP>:7777/bridge.lua?token=...",Method="GET"}).Body)()
--
--  It long-polls the server for commands (request / http_request), runs each
--  one in its own thread and posts the answer back. The console (LogService)
--  and, once Cobalt is loaded, every remote call Cobalt logs are pushed to
--  the server in batches. Running it again replaces the previous bridge.
--=============================================================================

do
local CONFIG = { host = "{{HOST}}", port = "{{PORT}}", token = "{{TOKEN}}" }
local BASE = "http://" .. CONFIG.host .. ":" .. CONFIG.port

local env = (getgenv and getgenv()) or _G
local Bridge = { alive = true, ops = {}, connections = {} }

Bridge.TABLE_DEPTH = 4       -- nested tables kept when encoding
Bridge.TABLE_ITEMS = 200     -- entries kept per table
Bridge.FLUSH_EVERY = 0.5     -- seconds between two event batches
Bridge.WATCH_EVERY = 1       -- seconds between two looks at Cobalt's logs
Bridge.BATCH = 200           -- console lines / remote calls per batch

local SEAS = {
    [2753915549] = 1, [85211729168715] = 1,
    [4442272183] = 2, [79091703265657] = 2,
    [7449423635] = 3, [100117331123089] = 3,
}

local function service(name)
    local ok, found = pcall(function() return game:GetService(name) end)
    return ok and found or nil
end

local function httpRequest(options)
    local fn = request or http_request or (syn and syn.request) or (http and http.request)
    if not fn then error("this executor has no request function", 0) end
    return fn(options)
end

---------------------------------------------------------------------------
-- Paths
---------------------------------------------------------------------------

-- "game.Workspace.Map.Sky", "Workspace/Map", 'Workspace.Map["Boat Castle"]',
-- "Players.LocalPlayer.Data" -> the parts.
function Bridge.splitPath(path)
    local parts, i, text = {}, 1, tostring(path or "game")
    while i <= #text do
        local char = text:sub(i, i)
        if char == "." or char == "/" then
            i = i + 1
        elseif char == "[" then
            local quote = text:sub(i + 1, i + 1)
            local close = text:find(quote .. "]", i + 2, true)
            if (quote == '"' or quote == "'") and close then
                parts[#parts + 1] = text:sub(i + 2, close - 1)
                i = close + 2
            else
                parts[#parts + 1] = text:sub(i)
                break
            end
        else
            local stop = text:find("[%./%[]", i) or (#text + 1)
            parts[#parts + 1] = text:sub(i, stop - 1)
            i = stop
        end
    end
    return parts
end

local function child(node, name)
    local found = node:FindFirstChild(name)
    if found then return found end
    local ok, value = pcall(function() return node[name] end)
    if ok and typeof(value) == "Instance" then return value end
    return nil
end

-- The instance at `path`, or nil and where it stopped.
function Bridge.resolve(path)
    local parts = Bridge.splitPath(path)
    local index, node = 1, nil
    if parts[1] == "game" then index = 2 end
    local first = parts[index]
    if first == nil then return game end
    if first == "workspace" or first == "Workspace" then
        node = workspace
    else
        node = service(first)
    end
    if not node then return nil, "no service " .. tostring(first) end
    for i = index + 1, #parts do
        local nextNode = child(node, parts[i])
        if not nextNode then return nil, "no " .. parts[i] .. " in " .. Bridge.path(node) end
        node = nextNode
    end
    return node
end

local function topOf(instance)
    local node = instance
    while node.Parent and node.Parent ~= game do node = node.Parent end
    return node
end

-- An instance's path, "game." first when it is in the data model.
function Bridge.path(instance)
    local ok, full = pcall(function() return instance:GetFullName() end)
    if not ok then return tostring(instance) end
    local top = topOf(instance)
    if top.Parent == game or service(top.ClassName) == top then return "game." .. full end
    return full .. " (not in game)"
end

---------------------------------------------------------------------------
-- Encoding (Lua values -> JSON-ready tables) and decoding
---------------------------------------------------------------------------

local function round(n) return math.floor(n * 100 + 0.5) / 100 end

function Bridge.encode(value, depth, seen)
    depth, seen = depth or 0, seen or {}
    local kind = typeof(value)
    if value == nil then return nil end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return tostring(value) end
        return value
    end
    if kind == "string" or kind == "boolean" then return value end
    if kind == "Instance" then return { ["$instance"] = Bridge.path(value), class = value.ClassName } end
    if kind == "Vector3" then return { ["$vector3"] = { round(value.X), round(value.Y), round(value.Z) } } end
    if kind == "CFrame" then
        local p = value.Position
        return { ["$cframe"] = { round(p.X), round(p.Y), round(p.Z) } }
    end
    if kind == "function" then return "<function>" end
    if kind == "table" then
        if seen[value] then return "<cycle>" end
        if depth >= Bridge.TABLE_DEPTH then return "<table>" end
        seen[value] = true
        local count, isArray = 0, true
        for key in pairs(value) do
            count = count + 1
            if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #value then isArray = false end
        end
        local out = {}
        if isArray then
            for i = 1, math.min(#value, Bridge.TABLE_ITEMS) do
                local item = Bridge.encode(value[i], depth + 1, seen)
                if item == nil then item = { ["$nil"] = true } end
                out[i] = item
            end
            if #value > Bridge.TABLE_ITEMS then out[#out + 1] = "<" .. (#value - Bridge.TABLE_ITEMS) .. " more>" end
        else
            local kept = 0
            for key, item in pairs(value) do
                kept = kept + 1
                if kept > Bridge.TABLE_ITEMS then
                    out["<more>"] = count - Bridge.TABLE_ITEMS
                    break
                end
                out[tostring(key)] = Bridge.encode(item, depth + 1, seen)
            end
        end
        seen[value] = nil
        return out
    end
    return tostring(value)
end

-- A call's argument list ({ n = ... } or plain) -> a JSON array.
function Bridge.encodeList(list, n)
    local out = {}
    for i = 1, n or (list and list.n) or #(list or {}) do
        local item = Bridge.encode(list[i])
        if item == nil then item = { ["$nil"] = true } end
        out[i] = item
    end
    return out
end

-- Tagged JSON values back to game values.
function Bridge.decode(value)
    if type(value) ~= "table" then return value end
    if value["$vector3"] then return Vector3.new(table.unpack(value["$vector3"])) end
    if value["$cframe"] then return CFrame.new(table.unpack(value["$cframe"])) end
    if value["$instance"] then return (Bridge.resolve(value["$instance"])) end
    if value["$nil"] then return nil end
    local out = {}
    for key, item in pairs(value) do out[key] = Bridge.decode(item) end
    return out
end

---------------------------------------------------------------------------
-- Ops
---------------------------------------------------------------------------

local ops = Bridge.ops

local function compile(code, chunkEnv)
    if setfenv then
        local fn, err = loadstring(code, "=mcp")
        if fn then setfenv(fn, chunkEnv) end
        return fn, err
    end
    return load(code, "=mcp", "t", chunkEnv)
end

-- Runs Luau; print / warn inside go to `output`.
function ops.exec(args)
    local output = {}
    local function collect(prefix)
        return function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
            output[#output + 1] = prefix .. table.concat(parts, "\t")
        end
    end
    local base = (getfenv and getfenv(0)) or _G
    local chunkEnv = setmetatable({ print = collect(""), warn = collect("[warn] ") }, { __index = base })
    local fn, err = compile(tostring(args.code or ""), chunkEnv)
    if not fn then return { error = "compile: " .. tostring(err), output = output } end
    local results = table.pack(pcall(fn))
    if not results[1] then return { error = tostring(results[2]), output = output } end
    local returns = Bridge.encodeList(results, results.n)
    table.remove(returns, 1)
    return { returns = returns, output = output }
end

local function resolveOrFail(path)
    local instance, why = Bridge.resolve(path)
    if not instance then error(why or ("not found: " .. tostring(path)), 0) end
    return instance
end

local function node(instance, depth, limit)
    local children = instance:GetChildren()
    local entry = { name = instance.Name, class = instance.ClassName, children = #children }
    if depth > 0 then
        entry.items = {}
        for i = 1, math.min(#children, limit) do
            entry.items[i] = node(children[i], depth - 1, limit)
        end
        if #children > limit then entry.more = #children - limit end
    end
    return entry
end

function ops.tree(args)
    local instance = resolveOrFail(args.path)
    local result = node(instance, math.max(1, tonumber(args.depth) or 1), tonumber(args.limit) or 200)
    result.path = Bridge.path(instance)
    return result
end

Bridge.COMMON_PROPS = { "Position", "Size", "Value", "Text", "Visible", "Enabled", "Transparency",
    "Health", "MaxHealth", "Anchored", "CanCollide", "Team", "DisplayName", "UserId" }

function ops.props(args)
    local instance = resolveOrFail(args.path)
    local out = { Name = instance.Name, ClassName = instance.ClassName, path = Bridge.path(instance) }
    if instance.Parent then out.Parent = Bridge.path(instance.Parent) end
    local wanted = {}
    for _, name in ipairs(Bridge.COMMON_PROPS) do wanted[#wanted + 1] = name end
    for _, name in ipairs(args.props or {}) do wanted[#wanted + 1] = name end
    for _, name in ipairs(wanted) do
        local ok, value = pcall(function() return instance[name] end)
        if ok and value ~= nil and typeof(value) ~= "function" and typeof(value) ~= "RBXScriptSignal"
            and not (typeof(value) == "Instance" and value.Parent == instance and value.Name == name) then
            out[name] = Bridge.encode(value)
        end
    end
    local ok, attributes = pcall(function() return instance:GetAttributes() end)
    if ok and next(attributes) then out.Attributes = Bridge.encode(attributes) end
    return out
end

function ops.find(args)
    local root = resolveOrFail(args.root or "game.Workspace")
    local name = args.name and tostring(args.name):lower()
    local className = args.className
    local limit = tonumber(args.limit) or 50
    local found = {}
    for i, instance in ipairs(root:GetDescendants()) do
        if (not name or instance.Name:lower():find(name, 1, true))
            and (not className or instance.ClassName == className or instance:IsA(className)) then
            found[#found + 1] = { path = Bridge.path(instance), class = instance.ClassName }
            if #found >= limit then break end
        end
        if i % 5000 == 0 then task.wait() end
    end
    return found
end

function ops.source(args)
    local instance = resolveOrFail(args.path)
    if not decompile then error("this executor has no decompile", 0) end
    local ok, source = pcall(decompile, instance)
    if not ok then error("decompile failed: " .. tostring(source), 0) end
    return { path = Bridge.path(instance), source = source }
end

local function value(folder, name)
    local item = folder and folder:FindFirstChild(name)
    if item == nil then return nil end
    local ok, got = pcall(function() return item.Value end)
    return ok and got or nil
end

function ops.player()
    local Players = service("Players")
    local player = Players and Players.LocalPlayer
    if not player then error("no local player", 0) end
    local data = player:FindFirstChild("Data")
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local tools = {}
    for _, container in ipairs({ player:FindFirstChild("Backpack"), character }) do
        for _, item in ipairs(container and container:GetChildren() or {}) do
            if item:IsA("Tool") then tools[#tools + 1] = item.Name end
        end
    end
    return {
        name = player.Name,
        userId = player.UserId,
        placeId = game.PlaceId,
        jobId = game.JobId,
        sea = SEAS[game.PlaceId],
        team = player.Team and player.Team.Name or nil,
        position = root and Bridge.encode(root.Position) or nil,
        health = humanoid and humanoid.Health or nil,
        maxHealth = humanoid and humanoid.MaxHealth or nil,
        level = value(data, "Level"),
        beli = value(data, "Beli"),
        fragments = value(data, "Fragments"),
        race = value(data, "Race"),
        devilFruit = value(data, "DevilFruit"),
        spawnPoint = value(data, "LastSpawnPoint"),
        tools = tools,
    }
end

function ops.fire(args)
    local remote = resolveOrFail(args.path)
    local list = {}
    for i, item in ipairs(args.args or {}) do list[i] = Bridge.decode(item) end
    local n = #(args.args or {})
    if args.invoke then
        local results = table.pack(pcall(function()
            return remote:InvokeServer(table.unpack(list, 1, n))
        end))
        if not results[1] then error(tostring(results[2]), 0) end
        local returns = Bridge.encodeList(results, results.n)
        table.remove(returns, 1)
        return { returns = returns }
    end
    remote:FireServer(table.unpack(list, 1, n))
    return { fired = true }
end

---------------------------------------------------------------------------
-- Cobalt
---------------------------------------------------------------------------

local seenCalls = setmetatable({}, { __mode = "k" })   -- [Log] = calls already sent
local outbox = { console = {}, remotes = {} }

local METHODS = {
    Outgoing = { RemoteEvent = "FireServer", UnreliableRemoteEvent = "FireServer", RemoteFunction = "InvokeServer",
        BindableEvent = "Fire", BindableFunction = "Invoke" },
    Incoming = { RemoteEvent = "OnClientEvent", UnreliableRemoteEvent = "OnClientEvent",
        RemoteFunction = "OnClientInvoke", BindableEvent = "Event", BindableFunction = "OnInvoke" },
}

local function cobaltLogs()
    local cobalt = env.Cobalt
    local shared = type(cobalt) == "table" and cobalt.shared
    return type(shared) == "table" and shared.Logs or nil
end

-- One Cobalt call as a JSON-ready table.
function Bridge.encodeCall(log, info, direction)
    local instance = log.Instance
    local class = instance and instance.ClassName or "?"
    local fn = type(info.Function) == "table" and info.Function or nil
    return {
        direction = direction,
        remote = instance and Bridge.path(instance) or "?",
        class = class,
        method = (METHODS[direction] or {})[class] or "?",
        args = Bridge.encodeList(info.Arguments or {}, info.Arguments and info.Arguments.n),
        result = info.InvokeResult and Bridge.encodeList(info.InvokeResult, info.InvokeResult.n) or nil,
        error = info.Error,
        origin = info.Origin and Bridge.path(info.Origin) or nil,
        line = info.Line,
        functionName = fn and fn.Name or nil,
        isExecutor = info.IsExecutor == true,
        time = info.CreationTime,
    }
end

-- New calls in Cobalt's logs since the last look. A log whose calls went
-- down was cleared: it starts over.
function Bridge.collectCobalt(limit)
    local logs = cobaltLogs()
    if not logs then return {} end
    local out = {}
    limit = limit or 500
    for direction, list in pairs(logs) do
        for _, log in pairs(list) do
            local calls = type(log) == "table" and log.Calls
            if type(calls) == "table" then
                local sent = seenCalls[log] or 0
                if #calls < sent then sent = 0 end
                while sent < #calls and #out < limit do
                    sent = sent + 1
                    local ok, entry = pcall(Bridge.encodeCall, log, calls[sent], direction)
                    if ok then out[#out + 1] = entry end
                end
                seenCalls[log] = sent
            end
        end
    end
    return out
end

function ops.cobalt()
    if not cobaltLogs() then
        local response = httpRequest({ Url = BASE .. "/cobalt?token=" .. CONFIG.token, Method = "GET" })
        local source = response and response.Body or ""
        if source == "" then error("Cobalt download failed (HTTP " .. tostring(response and response.StatusCode) .. ")", 0) end
        if source:sub(1, 2) == "--" and source:find("not found", 1, true) then error(source, 0) end
        local fn, err = loadstring(source, "=Cobalt")
        if not fn then error("Cobalt does not compile: " .. tostring(err), 0) end
        task.spawn(fn)
        for _ = 1, 120 do
            if cobaltLogs() then break end
            task.wait(0.5)
        end
        if not cobaltLogs() then error("Cobalt started but its logs never showed up", 0) end
    end
    Bridge.watching = true
    return { watching = true, executor = identifyexecutor and identifyexecutor() or nil }
end

function ops.cobaltClear()
    local logs = cobaltLogs()
    if not logs then return { cleared = false, why = "Cobalt not loaded" } end
    for _, list in pairs(logs) do
        for _, log in pairs(list) do
            if type(log) == "table" and log.ClearCalls then pcall(log.ClearCalls, log) end
            seenCalls[log] = 0
        end
    end
    return { cleared = true }
end

---------------------------------------------------------------------------
-- Strawberry Hub / Kaitun
---------------------------------------------------------------------------

local function hubTable()
    if type(env.StrawberryKaitunHub) == "table" then return env.StrawberryKaitunHub, "kaitun" end
    if type(env.StrawberryHub) == "table" then return env.StrawberryHub, "hub" end
    return nil
end

local function try(fn)
    local ok, result = pcall(fn)
    if ok then return Bridge.encode(result) end
    return "error: " .. tostring(result)
end

function ops.hub()
    local hub, which = hubTable()
    if not hub then return { loaded = false } end
    local out = { loaded = true, which = which, version = hub.Version }
    local req = hub.Require
    if which == "kaitun" and hub.Engine then out.kaitun = try(hub.Engine.status) end
    if req then
        out.farm = try(function() return req("Features.Farm").status() end)
        out.quest = try(function() return req("Game.Quests").describe() end)
        out.travel = try(function() return req("Game.Router").logText() end)
        out.route = try(function() return req("Game.Router").describe() end)
    else
        out.note = "this hub build has no Require: reload it from the branch for farm / quest / travel details"
    end
    return out
end

function ops.setting(args)
    local hub = hubTable()
    if not hub or not hub.Settings then error("no Strawberry Hub / Kaitun running", 0) end
    hub.Settings.set(args.key, Bridge.decode(args.value))
    return { key = args.key, value = Bridge.encode(hub.Settings.get(args.key)) }
end

---------------------------------------------------------------------------
-- Session and transport
---------------------------------------------------------------------------

function Bridge.session()
    local Players = service("Players")
    local player = Players and Players.LocalPlayer
    local hub, which = hubTable()
    return {
        placeId = game.PlaceId,
        jobId = game.JobId,
        sea = SEAS[game.PlaceId],
        player = player and player.Name or nil,
        executor = identifyexecutor and identifyexecutor() or nil,
        hub = hub and which or nil,
        cobalt = cobaltLogs() ~= nil,
        watching = Bridge.watching == true,
    }
end

local function json(data) return service("HttpService"):JSONEncode(data) end
local function unjson(text) return service("HttpService"):JSONDecode(text) end

local function post(path, data)
    local ok, response = pcall(httpRequest, {
        Url = BASE .. path .. "?token=" .. CONFIG.token,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = json(data),
    })
    return ok and response and (response.StatusCode or 0) < 300
end

-- Runs one command in its own thread and posts the answer.
function Bridge.run(command)
    local op = ops[command.op]
    local ok, result
    if not op then
        ok, result = false, "unknown op " .. tostring(command.op)
    else
        ok, result = pcall(op, command.args or {})
    end
    local answer = { id = command.id, ok = ok }
    if ok then answer.result = result else answer.error = tostring(result) end
    if not post("/result", answer) then
        post("/result", { id = command.id, ok = false, error = "the answer could not be encoded or sent" })
    end
end

function Bridge.flush()
    if #outbox.console == 0 and #outbox.remotes == 0 then return end
    local batch = { console = {}, remotes = {} }
    for _, key in ipairs({ "console", "remotes" }) do
        local list = outbox[key]
        for i = 1, math.min(#list, Bridge.BATCH) do batch[key][i] = list[i] end
        for _ = 1, #batch[key] do table.remove(list, 1) end
    end
    post("/events", batch)
end

function Bridge.stop()
    Bridge.alive = false
    for _, connection in ipairs(Bridge.connections) do pcall(function() connection:Disconnect() end) end
end

function Bridge.start()
    if type(env.StrawberryBridge) == "table" and env.StrawberryBridge.stop then pcall(env.StrawberryBridge.stop) end
    env.StrawberryBridge = Bridge

    local logService = service("LogService")
    if logService then
        Bridge.connections[#Bridge.connections + 1] = logService.MessageOut:Connect(function(message, kind)
            if #outbox.console < 5000 then
                outbox.console[#outbox.console + 1] = {
                    text = message, type = (tostring(kind):gsub("^Enum%.MessageType%.Message", ""):lower()),
                }
            end
        end)
    end
    if cobaltLogs() then Bridge.watching = true end

    task.spawn(function()
        while Bridge.alive do
            task.wait(Bridge.FLUSH_EVERY)
            pcall(Bridge.flush)
        end
    end)
    task.spawn(function()
        local last = 0
        while Bridge.alive do
            task.wait(Bridge.WATCH_EVERY)
            if Bridge.watching then
                local ok, calls = pcall(Bridge.collectCobalt)
                if ok then
                    for _, call in ipairs(calls) do
                        if #outbox.remotes < 20000 then outbox.remotes[#outbox.remotes + 1] = call end
                    end
                end
            end
            last = last + Bridge.WATCH_EVERY
            if last >= 10 then
                last = 0
                post("/events", { session = Bridge.session() })
            end
        end
    end)
    task.spawn(function()
        local connected = false
        while Bridge.alive do
            if not connected then
                connected = post("/hello", Bridge.session())
                if connected then
                    pcall(function()
                        service("StarterGui"):SetCore("SendNotification",
                            { Title = "Strawberry MCP", Text = "Connected to " .. CONFIG.host, Duration = 5 })
                    end)
                else
                    task.wait(3)
                end
            else
                local ok, response = pcall(httpRequest, { Url = BASE .. "/poll?token=" .. CONFIG.token, Method = "GET" })
                if not ok or not response or (response.StatusCode ~= 200 and response.StatusCode ~= 204) then
                    connected = false
                    task.wait(2)
                elseif response.StatusCode == 200 and response.Body and response.Body ~= "" then
                    local decoded, command = pcall(unjson, response.Body)
                    if decoded and type(command) == "table" then task.spawn(Bridge.run, command) end
                end
            end
        end
    end)
end

if BRIDGE_TEST then
    STRAWBERRY_BRIDGE = Bridge
else
    Bridge.start()
end
end
