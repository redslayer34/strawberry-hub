--=============================================================================
-- PORTAL RECORDER — learns the game's teleports by watching the player
--=============================================================================
--  Calling requestEntrance from anywhere no longer teleports (the server
--  answers nil). The real portals work by walking into them, so instead of
--  guessing, the hub watches the player take a portal once:
--
--    - every remote call the game's own scripts make is kept for a moment;
--    - when the character jumps more than JUMP studs in one frame, a portal
--      is learned: where the player stood (entrance), where they landed
--      (exit), and the game call made just before the jump, if any.
--
--  Learned portals are saved per sea and replayed by the Router: fly to the
--  entrance, trigger it the way the game did, continue from the exit.
--=============================================================================

local Hook = require("Game.Hook")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local World = require("Game.World")

local PortalRecorder = {}

PortalRecorder.FILE = "StrawberryHub/portals.json"
PortalRecorder.JUMP = 300           -- studs in one frame that mean a teleport
PortalRecorder.CALL_WINDOW = 5      -- seconds a call stays linked to a jump
PortalRecorder.TOUCH_RADIUS = 30    -- studs around the entrance whose touch parts count
PortalRecorder.MAX_PARTS = 5
PortalRecorder.KEEP_CALLS = 20
PortalRecorder.SAME_ENTRANCE = 50
PortalRecorder.SAME_EXIT = 200
PortalRecorder.AT_ENTRANCE = 60     -- studs: standing in the portal

-- Filled by the modules that own the character, so the recorder never
-- learns the hub's own flights or jumps.
PortalRecorder.busyCheck = function() return false end
PortalRecorder.movingCheck = function() return false end
PortalRecorder.onLearned = function() end
PortalRecorder.stateOf = function() return nil end
PortalRecorder.decisionText = function() return nil end

local calls = {}        -- recent game calls { at, path, method, args }
local portals = {}      -- [sea] = { portal, ... }
local loaded = false
local lastPosition, lastCharacter
local connection
local hooked = false

---------------------------------------------------------------------------
-- Serialising arguments
---------------------------------------------------------------------------

local function serialise(value)
    local kind = typeof(value)
    if kind == "Vector3" then return { t = "Vector3", v = { value.X, value.Y, value.Z } } end
    if kind == "CFrame" then
        local p = value.Position
        return { t = "CFrame", v = { p.X, p.Y, p.Z } }
    end
    if kind == "Instance" then
        local ok, name = pcall(function() return value:GetFullName() end)
        return { t = "Instance", v = ok and name or tostring(value) }
    end
    if kind == "string" or kind == "number" or kind == "boolean" then
        return { t = kind, v = value }
    end
    if kind == "table" then
        local parts = {}
        for key, item in pairs(value) do
            parts[#parts + 1] = tostring(key) .. "=" .. tostring(item)
            if #parts >= 6 then break end
        end
        return { t = "other", v = "{" .. table.concat(parts, ", ") .. "}" }
    end
    return { t = "other", v = tostring(value) }
end

-- GetFullName paths start with the service ("ReplicatedStorage.Remotes.CommF_").
local function resolve(path)
    path = tostring(path or "")
    local service, rest = path:match("^([^%.]+)%.?(.*)$")
    if not service then return nil end
    local ok, root = pcall(function() return game:GetService(service) end)
    if not ok or not root then
        root, rest = workspace, path
    end
    if rest == "" then return root end
    return Services.find(root, rest)
end

local function deserialise(entry)
    if type(entry) ~= "table" then return nil end
    if entry.t == "Vector3" then return Vector3.new(entry.v[1], entry.v[2], entry.v[3]) end
    if entry.t == "CFrame" then return CFrame.new(entry.v[1], entry.v[2], entry.v[3]) end
    if entry.t == "Instance" then
        return resolve(entry.v)
    end
    return entry.v
end

local function describe(entry, precise)
    if entry.t == "Vector3" or entry.t == "CFrame" then
        local format = precise and "%s(%.4f, %.4f, %.4f)" or "%s(%.1f, %.1f, %.1f)"
        return string.format(format, entry.t, entry.v[1], entry.v[2], entry.v[3])
    end
    if entry.t == "string" then return string.format("%q", entry.v) end
    return tostring(entry.v)
end

-- Only calls that look like a teleport are linked to a portal: the game
-- also sends telemetry, clock pings and profile requests all the time.
-- Seen in game: RF/BoatCastleTeleporters:InvokeServer("InitiateTeleport", part).
local TELEPORT_WORDS = { "teleport", "entrance", "portal", "travel" }

local function teleportLike(call)
    local texts = { tostring(call.path) }
    for _, entry in ipairs(call.args or {}) do
        if entry.t == "string" or entry.t == "Instance" then texts[#texts + 1] = tostring(entry.v) end
    end
    for _, text in ipairs(texts) do
        local lower = text:lower()
        for _, word in ipairs(TELEPORT_WORDS) do
            if lower:find(word, 1, true) then return true end
        end
    end
    return false
end
PortalRecorder.teleportLike = teleportLike

local function toVector(xyz) return Vector3.new(xyz[1], xyz[2], xyz[3]) end
local function fromVector(v) return { v.X, v.Y, v.Z } end

---------------------------------------------------------------------------
-- Persistence
---------------------------------------------------------------------------

local function load()
    if loaded then return end
    loaded = true
    if not (isfile and readfile) then return end
    local ok, data = pcall(function()
        if not isfile(PortalRecorder.FILE) then return nil end
        return Services.get("HttpService"):JSONDecode(readfile(PortalRecorder.FILE))
    end)
    if not ok or type(data) ~= "table" then return end
    for sea, list in pairs(data) do
        local number = tonumber(sea)
        if number and type(list) == "table" then
            portals[number] = {}
            for _, saved in ipairs(list) do
                if type(saved.entrance) == "table" and type(saved.exit) == "table" then
                    portals[number][#portals[number] + 1] = {
                        name = saved.name,
                        entrance = toVector(saved.entrance),
                        exit = toVector(saved.exit),
                        -- Portals learned before the filter may carry a
                        -- telemetry call: those are touch portals.
                        call = type(saved.call) == "table" and teleportLike(saved.call) and saved.call or nil,
                        reach = tonumber(saved.reach),
                        tooFar = tonumber(saved.tooFar),
                        parts = type(saved.parts) == "table" and saved.parts or nil,
                    }
                end
            end
        end
    end
end

local function save()
    if not writefile then return end
    local data = {}
    for sea, list in pairs(portals) do
        local out = {}
        for _, portal in ipairs(list) do
            out[#out + 1] = {
                name = portal.name,
                entrance = fromVector(portal.entrance),
                exit = fromVector(portal.exit),
                call = portal.call,
                reach = portal.reach,
                tooFar = portal.tooFar,
                parts = portal.parts,
            }
        end
        data[tostring(sea)] = out
    end
    pcall(function()
        if makefolder and isfolder and not isfolder("StrawberryHub") then makefolder("StrawberryHub") end
        writefile(PortalRecorder.FILE, Services.get("HttpService"):JSONEncode(data))
    end)
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

function PortalRecorder.enabled()
    return Settings.get("LearnPortals") == true
end

-- Hook observer: keeps the game's own remote calls for a moment.
function PortalRecorder.observe(remote, method, args, fromGame, at)
    if not fromGame or not PortalRecorder.enabled() then return end
    local ok, path = pcall(function() return remote:GetFullName() end)
    local serialised = {}
    for index = 1, args.n or #args do
        serialised[index] = serialise(args[index])
    end
    calls[#calls + 1] = {
        at = at or os.clock(),
        path = ok and path or tostring(remote),
        method = method,
        args = serialised,
    }
    while #calls > PortalRecorder.KEEP_CALLS do table.remove(calls, 1) end
end

local function nearestIsland(position)
    local best, bestDistance = nil, math.huge
    for name, where in pairs(World.islands()) do
        local distance = (where - position).Magnitude
        if distance < bestDistance then best, bestDistance = name, distance end
    end
    return best or string.format("(%d, %d, %d)", position.X, position.Y, position.Z)
end

local function recentCall(now)
    for index = #calls, 1, -1 do
        local call = calls[index]
        if now - call.at <= PortalRecorder.CALL_WINDOW and teleportLike(call) then
            return { path = call.path, method = call.method, args = call.args }
        end
    end
    return nil
end

-- Parts with a touch interest around the entrance, nearest first. The
-- query is on bounds, so a big portal part whose centre is far still counts.
local function touchParts(entrance)
    local found = {}
    local ok, parts = pcall(function()
        return workspace:GetPartBoundsInRadius(entrance, PortalRecorder.TOUCH_RADIUS)
    end)
    if not ok or type(parts) ~= "table" then return found end
    for _, part in ipairs(parts) do
        local character = Player.character()
        if part:FindFirstChildOfClass("TouchTransmitter")
            and not (character and part:IsDescendantOf(character)) then
            found[#found + 1] = part
        end
    end
    table.sort(found, function(a, b)
        return (a.Position - entrance).Magnitude < (b.Position - entrance).Magnitude
    end)
    while #found > PortalRecorder.MAX_PARTS do table.remove(found) end
    return found
end

-- Records one teleport from `entrance` to `exit`. Returns the portal.
function PortalRecorder.learn(entrance, exit, now)
    load()
    local sea = Player.sea() or 0
    portals[sea] = portals[sea] or {}
    local portal = {
        name = nearestIsland(entrance) .. " -> " .. nearestIsland(exit),
        entrance = entrance,
        exit = exit,
        call = recentCall(now or os.clock()),
    }
    local paths = {}
    for _, part in ipairs(touchParts(entrance)) do
        local okName, name = pcall(function() return part:GetFullName() end)
        if okName then paths[#paths + 1] = name end
    end
    portal.parts = #paths > 0 and paths or nil

    local list = portals[sea]
    for index, known in ipairs(list) do
        if (known.entrance - entrance).Magnitude <= PortalRecorder.SAME_ENTRANCE
            and (known.exit - exit).Magnitude <= PortalRecorder.SAME_EXIT then
            list[index] = portal
            save()
            pcall(PortalRecorder.onLearned, portal)
            return portal
        end
    end
    list[#list + 1] = portal
    save()
    pcall(PortalRecorder.onLearned, portal)
    return portal
end

-- Called every frame: a one-frame jump of more than JUMP studs, with the
-- same character and no hub movement going on, is the player taking a portal.
function PortalRecorder.step()
    local character = Player.character()
    local here = Player.position()
    if not character or not here then
        lastPosition = nil
        return
    end
    if character ~= lastCharacter then
        lastCharacter, lastPosition = character, here
        return
    end
    local before = lastPosition
    lastPosition = here
    if not before or not PortalRecorder.enabled() then return end
    if PortalRecorder.busyCheck() or PortalRecorder.movingCheck() then return end
    if (here - before).Magnitude > PortalRecorder.JUMP then
        PortalRecorder.learn(before, here, os.clock())
    end
end

---------------------------------------------------------------------------
-- Replaying
---------------------------------------------------------------------------

function PortalRecorder.portals()
    load()
    return portals[Player.sea() or 0] or {}
end

-- Triggers a learned portal while standing on its entrance: touches the
-- portal parts (the ones seen when it was learned, else the ones around),
-- replays the game's call, then ends the touch. `callOnly` skips the touch
-- (used to test the call from far away). The try is kept for the panel.
function PortalRecorder.trigger(portal, callOnly)
    local hrp = Player.hrp()
    local here = Player.position()
    local parts = {}
    if not callOnly then
        for _, path in ipairs(portal.parts or {}) do
            local part = resolve(path)
            if part then parts[#parts + 1] = part end
        end
        if #parts == 0 then parts = touchParts(portal.entrance) end
    end
    local canTouch = hrp and firetouchinterest
    if canTouch then
        for _, part in ipairs(parts) do pcall(firetouchinterest, hrp, part, 0) end
    end

    local answer
    if portal.call then
        local remote = resolve(portal.call.path)
        if remote then
            local args = {}
            for index, entry in ipairs(portal.call.args or {}) do args[index] = deserialise(entry) end
            local method = portal.call.method == "FireServer" and "FireServer" or "InvokeServer"
            local ok, result = pcall(function()
                return remote[method](remote, (table.unpack or unpack)(args, 1, #portal.call.args))
            end)
            answer = ok and result or (not ok and ("error: " .. tostring(result))) or nil
        else
            answer = "remote not found"
        end
    end

    if canTouch then
        for _, part in ipairs(parts) do pcall(firetouchinterest, hrp, part, 1) end
    end
    portal.lastTry = {
        distance = here and (here - portal.entrance).Magnitude or -1,
        answer = tostring(answer),
        touched = canTouch and #parts or 0,
    }
    return answer
end

-- Result of the last try, once the Router knows whether it worked.
function PortalRecorder.recordTry(portal, worked)
    if portal.lastTry then portal.lastTry.worked = worked end
end

-- The server accepts a portal's call only within some distance of its
-- entrance. Each replay from `distance` studs narrows that distance down:
-- reach is the farthest it worked from, tooFar the nearest it failed from.
function PortalRecorder.canUseFrom(portal, distance)
    if distance <= PortalRecorder.AT_ENTRANCE then return true end
    if not portal.call or not portal.reach then return false end
    return distance <= portal.reach and distance < (portal.tooFar or math.huge)
end

function PortalRecorder.recordUse(portal, distance, worked)
    if distance <= PortalRecorder.AT_ENTRANCE then return end
    if worked then
        portal.reach = math.max(portal.reach or 0, distance)
        if portal.tooFar and portal.tooFar <= distance then portal.tooFar = nil end
    else
        portal.tooFar = math.min(portal.tooFar or math.huge, distance)
        if portal.reach and portal.reach >= distance then portal.reach = nil end
    end
    save()
end

-- Parts of the map named like a teleporter, for the log: they show every
-- portal of the sea, even the ones not taken yet.
function PortalRecorder.scan()
    local lines = {}
    local map = workspace:FindFirstChild("Map")
    if not map then return lines end
    for _, descendant in ipairs(map:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant.Name:lower():find("teleport", 1, true) then
            local position = descendant.Position
            lines[#lines + 1] = string.format("%s (%.0f, %.0f, %.0f)",
                descendant:GetFullName(), position.X, position.Y, position.Z)
            if #lines >= 40 then break end
        end
    end
    return lines
end

function PortalRecorder.forget()
    portals = {}
    loaded = true
    save()
end

-- Text for the panel and for "Copy log".
function PortalRecorder.describe()
    local lines = {}
    for _, portal in ipairs(PortalRecorder.portals()) do
        local how = "by touch"
        if portal.call then
            local args = {}
            for index, entry in ipairs(portal.call.args or {}) do args[index] = describe(entry) end
            how = "by " .. tostring(portal.call.path):match("[^%.]+$") .. " " .. portal.call.method
                .. "(" .. table.concat(args, ", ") .. ")"
        end
        if portal.reach then how = how .. string.format(" (works up to %d studs away)", portal.reach)
        elseif portal.tooFar then how = how .. " (only at the entrance)" end
        local at = portal.entrance
        lines[#lines + 1] = string.format("%s, %s, entrance (%.0f, %.0f, %.0f)",
            portal.name, how, at.X, at.Y, at.Z)
        local okState, state = pcall(PortalRecorder.stateOf, portal)
        if okState and state then lines[#lines + 1] = "  " .. state end
        local try = portal.lastTry
        if try then
            local result = try.worked == true and "teleported"
                or try.worked == false and "no teleport" or "waiting"
            lines[#lines + 1] = string.format("  last try: %.1f studs away, answer %s, %d parts touched, %s",
                try.distance, try.answer, try.touched, result)
        end
    end
    if #lines == 0 then lines[1] = "No portal learned in this sea yet." end
    local okDecision, text = pcall(PortalRecorder.decisionText)
    if okDecision and text then
        lines[#lines + 1] = "Last route: " .. (text:match("^[^\n]*") or text)
    end
    return table.concat(lines, "\n")
end

function PortalRecorder.log()
    local lines = { "Learned portals (sea " .. tostring(Player.sea() or "?") .. "):", PortalRecorder.describe(), "", "Recent game calls:" }
    for _, call in ipairs(calls) do
        local args = {}
        for index, entry in ipairs(call.args) do args[index] = describe(entry) end
        lines[#lines + 1] = string.format("%.1f  %s:%s(%s)", call.at, call.path, call.method, table.concat(args, ", "))
    end
    local okDecision, text = pcall(PortalRecorder.decisionText)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Last route decision:"
    lines[#lines + 1] = okDecision and text or "none yet"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Exact portals:"
    for _, portal in ipairs(PortalRecorder.portals()) do
        local e, x = portal.entrance, portal.exit
        local line = string.format("%s | in (%.4f, %.4f, %.4f) | out (%.4f, %.4f, %.4f)",
            portal.name, e.X, e.Y, e.Z, x.X, x.Y, x.Z)
        if portal.call then
            local args = {}
            for index, entry in ipairs(portal.call.args or {}) do args[index] = describe(entry, true) end
            line = line .. " | " .. tostring(portal.call.path) .. ":" .. portal.call.method
                .. "(" .. table.concat(args, ", ") .. ")"
        end
        if portal.parts then line = line .. " | parts: " .. table.concat(portal.parts, ", ") end
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Teleporter parts:"
    local ok, found = pcall(PortalRecorder.scan)
    for _, line in ipairs(ok and found or {}) do lines[#lines + 1] = line end
    return table.concat(lines, "\n")
end

function PortalRecorder.start()
    if not hooked then
        hooked = true
        Hook.observe(PortalRecorder.observe)
    end
    if Settings.get("LearnPortals") then Hook.install() end
    if not PortalRecorder.listening then
        PortalRecorder.listening = true
        Settings.onChanged(function(key, value)
            if key == "LearnPortals" and value then Hook.install() end
        end)
    end
    if connection then return end
    connection = Services.get("RunService").Heartbeat:Connect(PortalRecorder.step)
end

function PortalRecorder.destroy()
    if connection then
        connection:Disconnect()
        connection = nil
    end
end

-- Test hooks.
function PortalRecorder.reset()
    calls, portals = {}, {}
    loaded = true
    lastPosition, lastCharacter = nil, nil
end

function PortalRecorder.resetLoaded()
    loaded = false
end

return PortalRecorder
