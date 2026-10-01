--=============================================================================
-- KAITUN TASKS — the long jobs, in the Teddy Kaitun's priority order
--=============================================================================
--  Teddy keeps a task list (tbl11) and a priority per task (tbl12, lower
--  first). Here each task drives an existing hub mode by switching its
--  settings on; the mode itself already knows how to do the job and when
--  there is nothing left to do (Mode want()).
--
--  A task is:
--    name       shown on the screen, and the Skip key in the config
--    priority   Teddy's number, lower runs first (ties: list order)
--    seas       the seas it runs in
--    minLevel   optional
--    mode       the hub mode it drives (the watchdog asks it enabled())
--    keys       settings switched on while it runs (a function may build them)
--    ready()    optional: extra condition to start
--    done()     optional: finished for good (the screen's checklist)
--    maxTime    optional: seconds before the watchdog gives it a rest
--    group      optional: a second Skip key (Skip.Godhuman skips every
--               step of the melee chain)
--=============================================================================

local Cdk = require("Features.Items.Cdk")
local Common = require("Features.Stack.Common")
local Config = require("Kaitun.Config")
local Electric = require("Features.Items.Electric")
local Guitar = require("Features.Items.Guitar")
local MaterialFarm = require("Features.MaterialFarm")
local Melee = require("Features.Items.Melee")
local Player = require("Core.Player")
local RaceUpgrade = require("Features.Races.Upgrade")
local Raids = require("Features.Raids")
local Saber = require("Features.Items.Saber")
local Swords = require("Features.Items.Swords")

local Tasks = {}

local function owned(name)
    return Common.has(name) or Common.itemCount(name) > 0
end
Tasks.owned = owned

-- The raid that matches the eaten fruit ("Flame-Flame" -> "Flame"), or nil.
function Tasks.fruitRaid()
    local fruit = Player.data("DevilFruit")
    if type(fruit) ~= "string" or fruit == "" then return nil end
    local base = fruit:match("^([^%-]+)") or fruit
    for _, name in ipairs(Raids.names()) do
        if name == base then return name end
    end
    return nil
end

-- Teddy's CanAwaken: an ability not awakened yet that the fragments pay for.
-- Returns can, allDone.
function Tasks.awakening()
    local list = Common.invoke("getAwakenedAbilities")
    if type(list) ~= "table" then return false, false end
    local fragments = Player.data("Fragments") or 0
    local can, any, all = false, false, true
    for _, ability in pairs(list) do
        if type(ability) == "table" then
            any = true
            if not ability.Awakened then
                all = false
                if fragments >= (tonumber(ability.Cost) or math.huge) then can = true end
            end
        end
    end
    return can, any and all
end

Tasks.LIST = {
    {
        name = "CDK", priority = 1, seas = { 3 }, mode = Cdk.mode,
        keys = { ItemCDK = true },
        ready = function() return Cdk.requirements() == nil end,
        done = function() return owned("Cursed Dual Katana") end,
    },
    {
        name = "Tushita", priority = 1, seas = { 3 }, mode = Swords.tushita,
        keys = { ItemTushita = true },
        done = function() return owned("Tushita") end,
    },
    {
        name = "SoulGuitar", priority = 3, seas = { 2, 3 }, minLevel = 2300, mode = Guitar.mode,
        keys = function() return { ItemSoulGuitar = true, GuitarHopMoon = Config.get("Hop") == true } end,
        done = function() return owned("Skull Guitar") end,
        maxTime = 3600,
    },
    {
        name = "Saber", priority = 4, seas = { 1 }, minLevel = Saber.MIN_LEVEL, mode = Saber.mode,
        keys = { ItemSaber = true },
        done = function() return owned("Saber") end,
    },
    {
        name = "Race", priority = 5, seas = { 2, 3 }, mode = RaceUpgrade.v2v3,
        keys = { RaceV2V3 = true },
        done = function() return RaceUpgrade.version() >= 3 end,
        maxTime = 2400,
    },
    {
        name = "AwakenFruit", priority = 6, seas = { 2, 3 }, minLevel = Raids.MIN_LEVEL, mode = Raids.solo,
        keys = function() return { RaidAuto = true, FruitAwaken = true, RaidName = Tasks.fruitRaid() or "Flame" } end,
        ready = function()
            if not Tasks.fruitRaid() then return false end
            local can = Tasks.awakening()
            return can
        end,
        done = function()
            local _, all = Tasks.awakening()
            return all
        end,
        maxTime = 1800,
    },
    -- The melee chain to Godhuman (Melee.mode itself runs in the background
    -- layer: it only learns and equips styles).
    {
        name = "ElectricClaw", group = "Godhuman", priority = 3, seas = { 3 }, mode = Melee.electricClaw,
        keys = { ItemElectricClaw = true },
        done = function() return Melee.unlocked("Electric Claw") end,
        maxTime = 600,
    },
    {
        -- Electric is a Sea 1 quest: from a later sea only once Black Leg and
        -- Fishman are ready for Superhuman, so the trip back is worth it.
        name = "Electric", group = "Godhuman", priority = 4, seas = { 1, 2, 3 }, mode = Electric.mode,
        keys = { ItemElectric = true },
        ready = function()
            if (Player.data("Beli") or 0) < Electric.PRICE then return false end
            if Player.sea() == 1 then return true end
            return Melee.mastery("Black Leg") >= Melee.SUPERHUMAN_NEEDS
                and Melee.mastery("Fishman Karate") >= Melee.SUPERHUMAN_NEEDS
        end,
        done = function() return Electric.owned() end,
        maxTime = 1800,
    },
    {
        name = "LibraryKey", group = "Godhuman", priority = 4, seas = { 2 }, mode = Melee.libraryKey,
        keys = { ItemLibraryKey = true },
        done = function() return Melee.unlocked("Death Step") end,
    },
    {
        name = "WaterKey", group = "Godhuman", priority = 4, seas = { 2 }, mode = Melee.waterKey,
        keys = { ItemWaterKey = true },
        done = function() return Melee.unlocked("Sharkman Karate") end,
    },
    {
        name = "FireEssence", group = "Godhuman", priority = 6, seas = { 3 }, mode = Melee.dragonTalon,
        keys = { ItemDragonTalon = true },
        done = function() return Melee.unlocked("Dragon Talon") end,
    },
    {
        name = "GodhumanMaterials", group = "Godhuman", priority = 7, seas = { 2, 3 }, mode = MaterialFarm,
        keys = function() return { AutoMaterial = true, Material = Melee.missingMaterial() or "" } end,
        ready = function() return Melee.owned("Dragon Talon") and Melee.missingMaterial() ~= nil end,
        done = function() return Melee.owned("Godhuman") end,
        maxTime = 3600,
    },
    {
        name = "Rainbow", priority = 8, seas = { 3 }, mode = Swords.rainbow,
        keys = { ItemRainbowHaki = true },
        done = function() return Common.invoke("HornedMan") == 1 end,
    },
    {
        name = "Yama", priority = 9, seas = { 3 }, mode = Swords.yama,
        keys = { ItemYama = true },
        done = function() return owned("Yama") end,
    },
}

-- The items the screen ticks off, in order.
Tasks.CHECKLIST = {
    { label = "Saber", item = "Saber" },
    { label = "Yama", item = "Yama" },
    { label = "Tushita", item = "Tushita" },
    { label = "CDK", item = "Cursed Dual Katana" },
    { label = "Soul Guitar", item = "Skull Guitar" },
    { label = "Godhuman", item = "Godhuman" },
}

function Tasks.keysOf(task)
    if type(task.keys) == "function" then return task.keys() end
    return task.keys or {}
end

-- Sorted copy of the list: priority, then list order.
function Tasks.ordered(list)
    list = list or Tasks.LIST
    local out = {}
    for index, task in ipairs(list) do out[#out + 1] = { task = task, index = index } end
    table.sort(out, function(a, b)
        if a.task.priority ~= b.task.priority then return a.task.priority < b.task.priority end
        return a.index < b.index
    end)
    for index, entry in ipairs(out) do out[index] = entry.task end
    return out
end

return Tasks
