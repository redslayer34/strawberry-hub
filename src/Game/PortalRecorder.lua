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
PortalRecorder.CALL_WINDOW = 1.5    -- seconds a call stays linked to a jump
PortalRecorder.TOUCH_RADIUS = 25    -- studs around the entrance for its part
PortalRecorder.KEEP_CALLS = 20
PortalRecorder.SAME_ENTRANCE = 50
PortalRecorder.SAME_EXIT = 200

-- Filled by the modules that own the character, so the recorder never
-- learns the hub's own flights or jumps.
PortalRecorder.busyCheck = function() return false end
PortalRecorder.movingCheck = function() return false end

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

local function describe(entry)
    if entry.t == "Vector3" or entry.t == "CFrame" then
        return string.format("%s(%.1f, %.1f, %.1f)", entry.t, entry.v[1], entry.v[2], entry.v[3])
    end
    if entry.t == "string" then return string.format("%q", entry.v) end
    return tostring(entry.v)
end

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
                        call = saved.call,
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
function PortalRecorder.observe(remote, method, args, fromGame)
    if not fromGame or not PortalRecorder.enabled() then return end
    local ok, path = pcall(function() return remote:GetFullName() end)
    local serialised = {}
    for index = 1, args.n or #args do
        serialised[index] = serialise(args[index])
    end
    calls[#calls + 1] = {
        at = os.clock(),
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
        if now - call.at <= PortalRecorder.CALL_WINDOW then
            return { path = call.path, method = call.method, args = call.args }
        end
    end
    return nil
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

    local list = portals[sea]
    for index, known in ipairs(list) do
        if (known.entrance - entrance).Magnitude <= PortalRecorder.SAME_ENTRANCE
            and (known.exit - exit).Magnitude <= PortalRecorder.SAME_EXIT then
            list[index] = portal
            save()
            return portal
        end
    end
    list[#list + 1] = portal
    save()
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

-- The part with a touch interest nearest the entrance: walking into it is
-- what the game's own portal reacts to.
local function touchPart(entrance)
    local best, bestDistance = nil, PortalRecorder.TOUCH_RADIUS
    local ok, parts = pcall(function()
        return workspace:GetPartBoundsInRadius(entrance, PortalRecorder.TOUCH_RADIUS)
    end)
    if not ok or type(parts) ~= "table" then return nil end
    for _, part in ipairs(parts) do
        if part:FindFirstChildOfClass("TouchTransmitter") then
            local distance = (part.Position - entrance).Magnitude
            if distance <= bestDistance then best, bestDistance = part, distance end
        end
    end
    return best
end

-- Triggers a learned portal while standing on its entrance: replays the
-- game's call when one was recorded, and touches the portal part.
function PortalRecorder.trigger(portal)
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
            answer = ok and result or nil
        end
    end

    local part = touchPart(portal.entrance)
    local hrp = Player.hrp()
    if part and hrp and firetouchinterest then
        pcall(firetouchinterest, hrp, part, 0)
        pcall(firetouchinterest, hrp, part, 1)
    end
    return answer
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
        lines[#lines + 1] = portal.name .. ", " .. how
    end
    if #lines == 0 then return "No portal learned in this sea yet." end
    return table.concat(lines, "\n")
end

function PortalRecorder.log()
    local lines = { "Learned portals (sea " .. tostring(Player.sea() or "?") .. "):", PortalRecorder.describe(), "", "Recent game calls:" }
    for _, call in ipairs(calls) do
        local args = {}
        for index, entry in ipairs(call.args) do args[index] = describe(entry) end
        lines[#lines + 1] = string.format("%.1f  %s:%s(%s)", call.at, call.path, call.method, table.concat(args, ", "))
    end
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
