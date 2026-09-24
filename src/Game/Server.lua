--=============================================================================
-- SERVER — hop, rejoin, join a JobId
--=============================================================================
--  Servers are listed from Roblox's public server API and joined through
--  the game's own ReplicatedStorage.__ServerBrowser:InvokeServer("teleport",
--  jobId), as the reference does. Servers already tried are remembered for
--  an hour so a hop never lands back where it came from.
--
--  Before any teleport, the loader is queued with queue_on_teleport when
--  AutoExecute is on, so the hub starts again in the new server.
--=============================================================================

local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Server = {}

Server.LOADER = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/redslayer34/strawberry-hub/claude/repo-exploration-ez26bn/StrawberryHub.lua"))()'
Server.VISITED_FILE = "StrawberryHub/visited.json"
Server.MAX_PAGES = 3
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

-- Teleports to a JobId through the game's own server (__ServerBrowser).
-- A client-side TeleportToPlaceInstance is refused with "attempted to join
-- a restricted place": each sea runs as several places (and the anti-cheat
-- Badlands places), which only the game server may send players into.
-- Returns true when the request was sent.
function Server.join(id)
    id = tostring(id or ""):gsub("%s", "")
    if id == "" then return false end
    local remote = browser()
    if not remote then return false end
    remember(game.JobId)
    Server.queueReload()
    return (pcall(remote.InvokeServer, remote, "teleport", id))
end

Server.SPAM_EVERY = 0.5

-- The reference's "Spam Join": the join is asked again every SPAM_EVERY
-- seconds while the JoinSpam setting stays on (a full server lets you in
-- once a slot frees). Returns true when the repeat started.
function Server.spamJoin(id)
    local Settings = require("Core.Settings")
    if not Settings.get("JoinSpam") then return false end
    task.spawn(function()
        while Settings.get("JoinSpam") do
            task.wait(Server.SPAM_EVERY)
            if not Settings.get("JoinSpam") then break end
            Server.join(id)
        end
    end)
    return true
end

-- One page of Roblox's public server list for this place, or nil.
local function servers(cursor)
    local url = "https://games.roblox.com/v1/games/" .. game.PlaceId
        .. "/servers/Public?sortOrder=Asc&limit=100"
    if cursor then url = url .. "&cursor=" .. cursor end
    local ok, data = pcall(function()
        return Services.get("HttpService"):JSONDecode(game:HttpGet(url))
    end)
    if ok and type(data) == "table" and type(data.data) == "table" then return data end
    return nil
end

-- Walks up to MAX_PAGES pages and returns every joinable server that
-- `accept(playing, max)` keeps.
local function candidates(accept)
    local found, cursor = {}, nil
    for _ = 1, Server.MAX_PAGES do
        local page = servers(cursor)
        if not page then break end
        for _, server in ipairs(page.data) do
            local id = tostring(server.id)
            local playing, max = tonumber(server.playing) or 0, tonumber(server.maxPlayers) or 0
            if id ~= game.JobId and playing < max and not Server.isVisited(id) and accept(playing, max) then
                found[#found + 1] = id
            end
        end
        cursor = page.nextPageCursor
        if not cursor or cursor == "" or cursor == "null" or #found >= 20 then break end
    end
    return found
end

-- A random server with a free slot that is neither this one nor one tried
-- in the last hour, or nil.
function Server.pick()
    local list = candidates(function() return true end)
    if #list == 0 then return nil end
    return list[math.random(1, #list)]
end

function Server.hop()
    local id = Server.pick()
    if not id then return false end
    remember(id)
    return Server.join(id)
end

-- A server with at most LOW_PLAYERS players.
function Server.pickLow()
    local list = candidates(function(playing) return playing <= Server.LOW_PLAYERS end)
    return list[1]
end

function Server.hopLow()
    local id = Server.pickLow()
    if not id then return false end
    remember(id)
    return Server.join(id)
end

-- Same server again, through the game server for the same reason as join.
-- With no server browser at all, a plain Teleport to the place is the only
-- request left (it lands in any server).
function Server.rejoin()
    if browser() then return Server.join(game.JobId) end
    Server.queueReload()
    return (pcall(function()
        Services.get("TeleportService"):Teleport(game.PlaceId, Services.player())
    end))
end

-- Test hook.
function Server.reset()
    visited = { hour = -1, ids = {} }
end

return Server
