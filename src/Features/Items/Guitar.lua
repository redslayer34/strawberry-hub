--=============================================================================
-- ITEMS: SOUL GUITAR
--=============================================================================
--  Materials first (the mode travels between seas by itself):
--    Dark Fragment  Sea 2, Darkbeard (fought, summoned with a Fist of
--                   Darkness, or chests collected until a Fist drops)
--    250 Ectoplasm  Sea 2 ship mobs
--    500 Bones      Sea 3 Haunted Castle mobs
--  then 5000 fragments to buy it, and the Haunted Castle puzzle
--  (GuitarPuzzleProgress Check):
--    start      a full moon at night, at the gravestone (gravestoneEvent 2)
--    Swamp      kill the 6 Living Zombies at once: lowered to 30 % first,
--               then all hit in the same instant (Meyy's way)
--    Gravestones  click the placards the reference lists
--    Ghost      talk to the ghost
--    Trophies   turn the tablets to match the trophies
--    Pipes      paint the lab floor with the right colours
--=============================================================================

local Bosses = require("Features.Stack.Bosses")
local Bring = require("Game.Bring")
local Combat = require("Game.Combat")
local ChestHunt = require("Features.ChestHunt")
local Common = require("Features.Stack.Common")
local Data = require("Game.Data")
local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local World = require("Game.World")

local Guitar = {}

Guitar.OWNED = "[You already own this item.]"
Guitar.FRAGMENTS = 5000
Guitar.ECTOPLASM = 250
Guitar.BONES = 500
Guitar.SHIP_MOBS = { "Ship Deckhand", "Ship Steward", "Ship Officer", "Ship Engineer" }
Guitar.GRAVESTONE = Vector3.new(-8654.314453125, 140.9499053955078, 6167.5283203125)
Guitar.SWAMP = Vector3.new(-10171.7607421875, 158.62667846679688, 6008.0654296875)
Guitar.ZOMBIES = 6
Guitar.SYNC_SHARE = 0.3       -- every zombie at or under this share of health, then the final blow
Guitar.SYNC_HITS = 15         -- hits sent at once for the final blow
Guitar.LOWER_EVERY = 0.2
Guitar.SWAMP_HEIGHT = 12
Guitar.SWAMP_REACH = 40
Guitar.PLACARDS_SPOT = Vector3.new(-8761.4765625, 142.10487365722656, 6086.07861328125)
Guitar.GHOST = Vector3.new(-9755.6591796875, 271.0661315917969, 6290.61474609375)
Guitar.TABLETS_SPOT = Vector3.new(-9530.0126953125, 6.104853630065918, 6054.83349609375)
Guitar.PLACARDS = {
    { "Placard1", "Right" }, { "Placard2", "Right" }, { "Placard3", "Left" }, { "Placard4", "Right" },
    { "Placard5", "Left" }, { "Placard6", "Left" }, { "Placard7", "Left" },
}
Guitar.BLANK_TABLETS = { "Segment6", "Segment2", "Segment8", "Segment9", "Segment5" }
Guitar.TROPHIES = { Segment1 = "Trophy1", Segment3 = "Trophy2", Segment4 = "Trophy3", Segment7 = "Trophy4", Segment10 = "Trophy5" }
Guitar.BLANK_X = -9707.86328125
Guitar.PIPES = {
    Part1 = "Really black", Part2 = "Really black", Part3 = "Dusty Rose", Part4 = "Storm blue",
    Part5 = "Really black", Part6 = "Parsley green", Part7 = "Really black", Part8 = "Dusty Rose",
    Part9 = "Really black", Part10 = "Storm blue",
}

local search = Fight.newSearch()
local chests = ChestHunt.new()
local syncing = false   -- the final blow has started: keep at it while zombies are left

local function castle(path)
    return Services.find(workspace, "Map.Haunted Castle" .. (path and ("." .. path) or ""))
end

local function click(detector)
    if detector and fireclickdetector and Common.every("GuitarClick", 0.3) then
        pcall(fireclickdetector, detector)
        return true
    end
    return false
end

-- What the materials still need, or nil when they are all there.
function Guitar.missing()
    if Common.itemCount("Dark Fragment") < 1 then return "Dark Fragment" end
    if Common.itemCount("Ectoplasm") < Guitar.ECTOPLASM then return "Ectoplasm" end
    if Common.itemCount("Bones") < Guitar.BONES then return "Bones" end
    return nil
end

local function darkFragment(mode)
    if not Common.travel(2) then return "Travelling to Sea 2" end
    if Enemies.findBoss("Darkbeard") or Common.has("Fist of Darkness") then
        return "Dark Fragment: " .. Bosses.darkbeard.tick(mode)
    end
    local found = chests:step(false)
    return found == "chest" and "Chests for a Fist of Darkness" or "Looking for chests"
end

local function materials(mode, need)
    if need == "Dark Fragment" then return darkFragment(mode) end
    if need == "Ectoplasm" then
        if not Common.travel(2) then return "Travelling to Sea 2" end
        return string.format("Ectoplasm %d/%d: %s", Common.itemCount("Ectoplasm"), Guitar.ECTOPLASM,
            Common.farm(mode, Guitar.SHIP_MOBS, search))
    end
    if not Common.travel(3) then return "Travelling to Sea 3" end
    return string.format("Bones %d/%d: %s", Common.itemCount("Bones"), Guitar.BONES,
        Common.farm(mode, Data.BONE_MOBS, search))
end

---------------------------------------------------------------------------
-- Puzzle
---------------------------------------------------------------------------

local function night()
    local time = Services.get("Lighting").ClockTime or 12
    return time > 16 or time < 5
end

local function strongestZombie()
    local best, bestHealth
    for _, zombie in ipairs(Enemies.all("Living Zombie")) do
        local health = zombie.Humanoid.Health
        if not bestHealth or health > bestHealth then best, bestHealth = zombie, health end
    end
    return best
end

-- The zombies must all die at once (Meyy's way): those above 30 % health
-- are lowered two at a time, only them; once every one is under, all of
-- them are hit together, several times in the same instant.
local function share(zombie)
    local humanoid = zombie:FindFirstChildOfClass("Humanoid")
    if not humanoid or not humanoid.MaxHealth or humanoid.MaxHealth <= 0 then return 1 end
    return humanoid.Health / humanoid.MaxHealth
end

-- The zombies to hit now, and whether it is the final, synchronised blow.
function Guitar.swampTargets(zombies)
    local above = {}
    for _, zombie in ipairs(zombies) do
        if share(zombie) > Guitar.SYNC_SHARE then above[#above + 1] = zombie end
    end
    if #above == 0 then return zombies, true end
    table.sort(above, function(a, b) return share(a) > share(b) end)
    return { above[1], above[2] }, false
end

function Guitar.swampStep(zombies)
    local strongest = strongestZombie() or zombies[1]
    local root = strongest:FindFirstChild("HumanoidRootPart")
    if not root then return "waiting for the zombies" end
    Common.goTo(root.CFrame * CFrame.new(0, Guitar.SWAMP_HEIGHT, 0))
    -- Pulled together, so one blow reaches all of them.
    Bring.run(strongest, Guitar.ZOMBIES)
    Player.equip(Settings.get("Weapon"))
    local targets, final = Guitar.swampTargets(zombies)
    syncing = syncing or final
    if not Common.near(root.Position, Guitar.SWAMP_REACH) then return "flying over the zombies" end
    if final then
        Combat.hitRigs(targets, Guitar.SYNC_HITS)
        return "killing all the zombies at once"
    end
    if Common.every("GuitarLower", Guitar.LOWER_EVERY) then Combat.hitRigs(targets, 1) end
    return "lowering the zombies to 30%"
end

local function trophyAngle(trophy)
    local handle = castle("Trophies.Quest." .. trophy .. ".Handle")
    if not handle then return nil end
    local parts = tostring(handle.CFrame):split(", ")
    local value = parts[4]
    return (value == "1" or value == "-1") and "90" or "180"
end

local function puzzle(mode, progress)
    if not progress then
        if World.moon() == "Full Moon" and night() then
            Common.goTo(Guitar.GRAVESTONE)
            if Common.near(Guitar.GRAVESTONE, 50) and Common.every("Gravestone", 1) then
                Services.invoke("gravestoneEvent", 2)
                Services.invoke("gravestoneEvent", 2, true)
                Common.forget()
            end
            return "Starting the puzzle at the gravestone"
        end
        Movement.stop()
        if Settings.get("GuitarHopMoon") then Common.hop("no full moon night") end
        return "Waiting for a full moon night"
    end
    if not progress.Swamp then
        if not Common.near(Guitar.SWAMP, 100) then
            Common.goTo(Guitar.SWAMP)
            return "Going to the swamp"
        end
        local zombies = Enemies.all("Living Zombie")
        if #zombies >= Guitar.ZOMBIES or (syncing and #zombies > 0) then
            return "Swamp: " .. Guitar.swampStep(zombies)
        end
        syncing = false
        Movement.stop()
        return "Swamp: waiting for the 6 zombies"
    end
    if not progress.Gravestones then
        Common.goTo(Guitar.PLACARDS_SPOT)
        if Common.near(Guitar.PLACARDS_SPOT, 50) and fireclickdetector and Common.every("Placards", 2) then
            for _, placard in ipairs(Guitar.PLACARDS) do
                local detector = castle(placard[1] .. "." .. placard[2] .. ".ClickDetector")
                if detector then pcall(fireclickdetector, detector) end
            end
            Common.forget()
        end
        return "Gravestones"
    end
    if not progress.Ghost then
        Common.goTo(Guitar.GHOST)
        if Common.near(Guitar.GHOST, 50) and Common.every("GuitarGhost", 3) then
            Services.invoke("GuitarPuzzleProgress", "Ghost")
            Common.forget()
        end
        return "Talking to the ghost"
    end
    if not progress.Trophies then
        Common.goTo(Guitar.TABLETS_SPOT)
        local tablet = castle("Tablet")
        if not tablet or not Common.near(Guitar.TABLETS_SPOT, 50) then return "Going to the tablets" end
        for _, name in ipairs(Guitar.BLANK_TABLETS) do
            local segment = tablet:FindFirstChild(name)
            local line = segment and segment:FindFirstChild("Line")
            if line and line.Position.X ~= Guitar.BLANK_X then
                click(segment:FindFirstChild("ClickDetector"))
                return "Turning " .. name
            end
        end
        for name, trophy in pairs(Guitar.TROPHIES) do
            local segment = tablet:FindFirstChild(name)
            local line = segment and segment:FindFirstChild("Line")
            local angle = trophyAngle(trophy)
            if line and angle and not tostring(line.Rotation.Z):find(angle, 1, true) then
                click(segment:FindFirstChild("ClickDetector"))
                return "Turning " .. name
            end
        end
        Common.forget()
        return "Trophies set"
    end
    if not progress.Pipes then
        local floor = castle("Lab Puzzle.ColorFloor.Model")
        if not floor then
            Common.goTo(Guitar.TABLETS_SPOT)
            return "Going to the lab"
        end
        for name, colour in pairs(Guitar.PIPES) do
            local part = floor:FindFirstChild(name)
            if part and Common.colorName(part) ~= colour then
                Common.goTo(part.CFrame * CFrame.new(0, 5, 0))
                click(part:FindFirstChild("ClickDetector"))
                return "Painting " .. name
            end
        end
        Common.forget()
        return "Pipes set"
    end
    Movement.stop()
    return "Puzzle done: collect the guitar"
end

Guitar.mode = Mode({
    name = "Soul Guitar",
    key = "ItemSoulGuitar",
    want = function() return Common.invoke("soulGuitarBuy", true) ~= Guitar.OWNED end,
    idleStatus = "Owned",
    tick = function(mode)
        -- Materials first: they need no fragments, so the wait for 5000
        -- fragments does not hold them up.
        local need = Guitar.missing()
        if need then return materials(mode, need) end
        if (Player.data("Fragments") or 0) < Guitar.FRAGMENTS then
            Movement.stop()
            return "Needs 5000 fragments"
        end
        if Common.every("GuitarBuy", 5) then
            Services.invoke("soulGuitarBuy", true)
            Services.invoke("soulGuitarBuy")
        end
        if not Common.travel(3) then return "Travelling to Sea 3" end
        local progress = Common.invoke("GuitarPuzzleProgress", "Check")
        return puzzle(mode, type(progress) == "table" and progress or nil)
    end,
    stop = function() search:reset() end,
})

function Guitar.reset()
    search:reset()
    chests:reset()
    syncing = false
end

return Guitar
