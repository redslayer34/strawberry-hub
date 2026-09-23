--=============================================================================
-- SERVER — hop, rejoin, join a JobId
--=============================================================================
--  Hops use the game's own server list, ReplicatedStorage.__ServerBrowser:
--  InvokeServer(page) returns { [jobId] = info }, and
--  InvokeServer("teleport", jobId) moves there (as the reference does).
--  Servers already tried are remembered for an hour so a hop never lands
--  back where it came from.
--
--  Before any teleport, the loader is queued with queue_on_teleport when
--  AutoExecute is on, so the hub starts again in the new server.
--=============================================================================

local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Server = {}

Server.LOADER = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/redslayer34/strawberry-hub/claude/repo-exploration-ez26bn/StrawberryHub.lua"))()'
Server.VISITED_FILE = "StrawberryHub/visited.json"
Server.MAX_PAGES = 20
Server.LOW_PLAYERS = 3

local visited = { hour = -1, ids = {} }

local function currentHour()
    return math.floor(os.time() / 3600)
end

local function loadVisited()
    if visited.loaded then return end
    visited.loaded = true
    if not (isfile and readfile and isfile(Server.VISITED_FILE)) then return end
    local ok, data = pcall(function()
        return Services.get("HttpService"):JSONDecode(readfile(Server.VISITED_FILE))
    end)
    if ok and type(data) == "table" and data.hour == currentHour() and type(data.ids) == "table" then
        visited.hour, visited.ids = data.hour, data.ids
    end
end

local function remember(id)
    loadVisited()
    if visited.hour ~= currentHour() then
        visited.hour, visited.ids = currentHour(), {}
    end
    visited.ids[#visited.ids + 1] = id
    if writefile then
        pcall(function()
            if makefolder and isfolder and not isfolder("StrawberryHub") then makefolder("StrawberryHub") end
            writefile(Server.VISITED_FILE, Services.get("HttpService"):JSONEncode({
                hour = visited.hour, ids = visited.ids,
            }))
        end)
    end
end

function Server.isVisited(id)
    loadVisited()
    if visited.hour ~= currentHour() then return false end
    return table.find(visited.ids, id) ~= nil
end

-- Queues the loader for the next server, when AutoExecute is on.
function Server.queueReload()
    if not Settings.get("AutoExecute") then return false end
    local queue = queue_on_teleport or (syn and syn.queue_on_teleport)
    if not queue then return false end
    return (pcall(queue, Server.LOADER))
end

local function browser()
    return Services.replicated():FindFirstChild("__ServerBrowser")
end

-- Teleports to a JobId. Returns true when the request was sent.
function Server.join(id)
    id = tostring(id or ""):gsub("%s", "")
    if id == "" then return false end
    remember(game.JobId)
    Server.queueReload()
    local remote = browser()
    if remote then
        return (pcall(remote.InvokeServer, remote, "teleport", id))
    end
    return (pcall(function()
        Services.get("TeleportService"):TeleportToPlaceInstance(game.PlaceId, id, Services.player())
    end))
end

-- The first server of the game's list that is neither this one nor one
-- already tried, or nil.
function Server.pick()
    local remote = browser()
    if not remote then return nil end
    for page = 1, Server.MAX_PAGES do
        local ok, list = pcall(remote.InvokeServer, remote, page)
        if not ok or type(list) ~= "table" or next(list) == nil then break end
        for id in pairs(list) do
            if id ~= game.JobId and not Server.isVisited(id) then return id end
        end
    end
    return nil
end

function Server.hop()
    local id = Server.pick()
    if not id then return false end
    remember(id)
    return Server.join(id)
end

-- A server with at most LOW_PLAYERS players, from Roblox's public server list.
function Server.pickLow()
    local url = "https://games.roblox.com/v1/games/" .. game.PlaceId
        .. "/servers/Public?sortOrder=Asc&limit=100"
    local ok, data = pcall(function()
        return Services.get("HttpService"):JSONDecode(game:HttpGet(url))
    end)
    if not ok or type(data) ~= "table" or type(data.data) ~= "table" then return nil end
    for _, server in ipairs(data.data) do
        local id = tostring(server.id)
        local playing, max = tonumber(server.playing) or 0, tonumber(server.maxPlayers) or 0
        if id ~= game.JobId and playing < max and playing <= Server.LOW_PLAYERS and not Server.isVisited(id) then
            return id
        end
    end
    return nil
end

function Server.hopLow()
    local id = Server.pickLow()
    if not id then return false end
    remember(id)
    return Server.join(id)
end

function Server.rejoin()
    Server.queueReload()
    return (pcall(function()
        Services.get("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, Services.player())
    end))
end

-- Test hook.
function Server.reset()
    visited = { hour = -1, ids = {} }
end

return Server
