--=============================================================================
-- STACK COMMON — what every stack task needs
--=============================================================================
--  Stack tasks are asked "is there something to do?" every frame, and most
--  answers come from the server (quest progress, NPC replies). Those calls
--  go through `cached`, so the server is asked at most once per CACHE_TIME.
--=============================================================================

local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Server = require("Game.Server")
local Services = require("Core.Services")

local Common = {}

Common.CACHE_TIME = 5      -- seconds a server answer is reused
Common.HOP_AFTER = 15      -- seconds a hop reason must hold before hopping
Common.HOP_COOLDOWN = 30   -- seconds between two hops
Common.REACHED = 8         -- studs: close enough to talk or touch

local cache, inventoryCache = {}, nil
local hopSince, lastHop = {}, nil
local cooldowns = {}

---------------------------------------------------------------------------
-- Server answers
---------------------------------------------------------------------------

-- CommF_ answer for these arguments, asked at most once per CACHE_TIME.
function Common.invoke(...)
    local parts = { ... }
    for index = 1, select("#", ...) do parts[index] = tostring(parts[index]) end
    local key = table.concat(parts, "|")
    local entry = cache[key]
    local now = os.clock()
    if entry and now - entry.at < Common.CACHE_TIME then return entry.value end
    local value = Services.invoke(...)
    cache[key] = { at = now, value = value }
    return value
end

-- Forgets cached answers (after an action that changes them).
function Common.forget()
    cache, inventoryCache = {}, nil
end

-- True at most once every `seconds` for `key`: paces actions such as
-- asking for a quest or travelling.
function Common.every(key, seconds)
    local now = os.clock()
    if cooldowns[key] and now - cooldowns[key] < seconds then return false end
    cooldowns[key] = now
    return true
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

function Common.tool(name)
    local character = Player.character()
    local player = Services.player()
    local backpack = player and player:FindFirstChild("Backpack")
    return (character and character:FindFirstChild(name)) or (backpack and backpack:FindFirstChild(name))
end

function Common.has(name)
    return Common.tool(name) ~= nil
end

-- Equips the tool called `name`. Returns it, or nil when not owned.
function Common.equip(name)
    local tool = Common.tool(name)
    if not tool then return nil end
    local character = Player.character()
    local humanoid = Player.humanoid()
    if tool.Parent ~= character and humanoid and not humanoid.Sit then
        pcall(function() humanoid:EquipTool(tool) end)
    end
    return tool
end

-- The inventory as { name, type, count } entries. The game's item service
-- first (what the reference reads), the older getInventory call otherwise.
function Common.inventory()
    local now = os.clock()
    if inventoryCache and now - inventoryCache.at < Common.CACHE_TIME then return inventoryCache.items end
    local items = {}
    inventoryCache = { at = now, items = items }
    local ok = pcall(function()
        local service = Services.module("ItemReplicationService")
        local config = Services.module("ItemConfig")
        if type(service) ~= "table" or type(config) ~= "table" then error("no item service") end
        local keys = service.KEYS
        for _, item in ipairs(service:GetItems(keys.QUANTITY)) do
            if item.Value and item.Value > 0 then
                local found, info = pcall(function() return config.match(item.ItemId):unwrap() end)
                if found and info and info.Display then
                    local kind = info.Display.Category
                    local storage = info.Index and info.Index.StorageKey
                    local name = kind == "Blox Fruit" and (storage or info.Display.Name) or (info.Display.Name or storage)
                    items[#items + 1] = { name = name, type = kind, count = item.Value }
                end
            end
        end
    end)
    if ok and #items > 0 then return items end
    for index = #items, 1, -1 do items[index] = nil end

    local list = Common.invoke("getInventory")
    if type(list) == "table" then
        for _, item in ipairs(list) do
            if type(item) == "table" and item.Name then
                items[#items + 1] = { name = item.Name, type = item.Type, count = item.Count or 1 }
            end
        end
    end
    return items
end

function Common.itemCount(name)
    for _, item in ipairs(Common.inventory()) do
        if item.name == name then return item.count or 0 end
    end
    return 0
end

---------------------------------------------------------------------------
-- Moving and fighting
---------------------------------------------------------------------------

local function toCFrame(where)
    if typeof(where) == "CFrame" then return where end
    return CFrame.new(where)
end

-- Flies to `where` (Vector3 or CFrame). Returns the distance left.
function Common.goTo(where)
    local target = toCFrame(where)
    Movement.to(target)
    return Player.distanceTo(target.Position)
end

function Common.near(where, radius)
    local position = typeof(where) == "CFrame" and where.Position or where
    return Player.distanceTo(position) <= (radius or Common.REACHED)
end

-- Fights a boss or mob found by Enemies.findBoss: a boss parked out of
-- streaming range is flown to first, which loads it.
function Common.fight(mode, mob, inWorld)
    if inWorld == false then
        mode.target = nil
        Movement.to(mob.HumanoidRootPart.CFrame * CFrame.new(0, Fight.SPAWN_HEIGHT, 0))
        return "Going to " .. mob.Name
    end
    return Fight.status(mob, Fight.engage(mode, mob))
end

-- Fights the nearest mob of `names`, or tours their spawn points.
function Common.farm(mode, names, search)
    local mob = Enemies.nearest(names)
    if mob then return Common.fight(mode, mob, true) end
    if search:run(mode, names) then return "Looking for " .. table.concat(names, ", ") end
    Movement.stop()
    return "Waiting for " .. table.concat(names, ", ")
end

-- A part's BrickColor name ("Lime green"), or "".
function Common.colorName(part)
    local ok, name = pcall(function() return part.BrickColor.Name end)
    return ok and tostring(name) or ""
end

-- Touches `part` with the character (and with `tool`'s handle if given).
function Common.touch(part, tool)
    if not firetouchinterest or not part then return end
    local touchers = {}
    local handle = tool and tool:FindFirstChild("Handle")
    if handle then touchers[#touchers + 1] = handle end
    touchers[#touchers + 1] = Player.hrp()
    for _, toucher in ipairs(touchers) do
        pcall(firetouchinterest, toucher, part, 0)
        pcall(firetouchinterest, toucher, part, 1)
    end
end

---------------------------------------------------------------------------
-- Hopping
---------------------------------------------------------------------------

-- Asks for a hop because of `reason`. The hop happens once the reason has
-- held for HOP_AFTER seconds, at most once per HOP_COOLDOWN. Returns true
-- when a hop was started.
function Common.hop(reason)
    local now = os.clock()
    hopSince[reason] = hopSince[reason] or now
    if now - hopSince[reason] < Common.HOP_AFTER then return false end
    if lastHop and now - lastHop < Common.HOP_COOLDOWN then return false end
    lastHop = now
    hopSince = {}
    return Server.hop()
end

-- The reasons that no longer hold start counting from zero again.
function Common.keepHopReasons(active)
    for reason in pairs(hopSince) do
        if not active[reason] then hopSince[reason] = nil end
    end
end

-- Test hook.
function Common.reset()
    cache, hopSince, lastHop, cooldowns = {}, {}, nil, {}
    inventoryCache = nil
end

return Common
