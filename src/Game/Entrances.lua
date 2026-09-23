--=============================================================================
-- ENTRANCES — the game's own teleport points
--=============================================================================
--  CommF_:InvokeServer("requestEntrance", position) moves the player
--  straight to one of these points, from anywhere in the sea. Which points
--  exist depends on the sea and on what the player has unlocked
--  (CommF_ GetUnlockables): Doflamingo's rooms need FlamingoAccess, the Rip
--  Indra portals need DefeatedIndraTrueForm. Points and rules come from the
--  reference script.
--=============================================================================

local Player = require("Core.Player")
local Services = require("Core.Services")

local Entrances = {}

local function v(x, y, z) return Vector3.new(x, y, z) end

-- unlock: the GetUnlockables flag the point needs (nil = always open).
Entrances.POINTS = {
    [1] = {
        { name = "Upper Sky", position = v(-7894.6, 5545.5, -380.2) },
        { name = "Sky Island", position = v(-4607.8, 872.5, -1667.6) },
        { name = "Underwater City", position = v(61163.9, 11.8, 1819.8) },
        { name = "Whirlpool", position = v(3876.3, 35.1, -1939.3) },
    },
    [2] = {
        { name = "Cursed Ship", position = v(923.2, 127.0, 32852.8) },
        { name = "Graveyard", position = v(-6508.6, 89.0, -132.8) },
        { name = "Doflamingo Mansion", position = v(-288.5, 306.1, 598.0), unlock = "FlamingoAccess" },
        { name = "Flamingo Room", position = v(2284.9, 15.2, 905.5), unlock = "FlamingoAccess" },
    },
    [3] = {
        { name = "Temple of Time", position = v(28282.6, 14896.9, 105.1), temple = true },
        { name = "Castle on the Sea", position = v(-4967.7, 314.9, -3157.1), unlock = "DefeatedIndraTrueForm" },
        { name = "Hydra", position = v(5661.5, 1013.4, -334.9), unlock = "DefeatedIndraTrueForm" },
        { name = "Turtle Mansion", position = v(-12463.9, 374.9, -7523.8), unlock = "DefeatedIndraTrueForm" },
    },
}

Entrances.TAG_TIME = 1.5
Entrances.UNLOCK_RETRY = 5
Entrances.UNLOCK_TRIES = 10

local unlocks   -- GetUnlockables result, nil until known

function Entrances.unlocks()
    return unlocks
end

-- Fetches the unlockables once, in the background, retrying a few times.
function Entrances.refresh()
    task.spawn(function()
        for _ = 1, Entrances.UNLOCK_TRIES do
            local result = Services.invoke("GetUnlockables")
            if type(result) == "table" then
                unlocks = result
                return
            end
            task.wait(Entrances.UNLOCK_RETRY)
        end
    end)
end

-- Whether the unlockables confirm this point (points without a
-- requirement are always confirmed).
function Entrances.confirmed(point)
    if not point.unlock then return true end
    return unlocks ~= nil and unlocks[point.unlock] == true
end

-- Every point of the current sea. The unlock flag is only a hint: its name
-- may differ on a given server, and a player who owns the portal must not
-- lose it to a missing flag. A point the game refuses is soft-locked by the
-- Router after two misses.
function Entrances.available()
    return Entrances.POINTS[Player.sea() or 0] or {}
end

-- The Temple of Time map lives in ReplicatedStorage.MapStash until the
-- client loads it; the entrance only works once it is in workspace.Map.
local function borrowTemple()
    local stash = Services.replicated():FindFirstChild("MapStash")
    local temple = stash and stash:FindFirstChild("Temple of Time")
    local map = workspace:FindFirstChild("Map")
    if not temple or not map then return end
    temple:SetAttribute("ClientBorrowed", true)
    temple.Parent = map
    task.delay(30, function()
        pcall(function()
            temple:SetAttribute("ClientBorrowed", nil)
            if temple.Parent == map and Player.distanceTo(temple:GetPivot().Position) > 3000 then
                temple.Parent = stash
            end
        end)
    end)
end

-- Sends the teleport request. The "Teleporting" tag is what the game's own
-- teleports carry; without it the jump looks like a speed hack.
function Entrances.use(point)
    local player = Services.player()
    local tags = Services.get("CollectionService")
    pcall(function() tags:AddTag(player, "Teleporting") end)
    task.delay(Entrances.TAG_TIME, function()
        pcall(function() tags:RemoveTag(player, "Teleporting") end)
    end)
    if point.temple then pcall(borrowTemple) end
    return Services.invoke("requestEntrance", point.position)
end

-- Test hook.
function Entrances.reset(value)
    unlocks = value
end

return Entrances
