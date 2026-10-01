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
--    hop()      optional: what this server lacks for the task (a reason
--               to change server); hopAfter: how long it must hold
--    wake()     optional: ends a rest early (what the task waited for is
--               here)
--    group      optional: a second Skip key (Skip.Godhuman skips every
--               step of the melee chain)
--=============================================================================

local Cdk = require("Features.Items.Cdk")
local Enemies = require("Game.Enemies")
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
local Summons = require("Features.Stack.Summons")
local Swords = require("Features.Items.Swords")

local Tasks = {}

Tasks.MAX_LEVEL = 2800

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

Tasks.RAID_BELI = 1000000

-- A raid chip held, or something to pay one with: a fruit under 1M in the
-- storage (Raids loads it), or money.
function Tasks.canPayRaid()
    return Common.has("Special Microchip") or Raids.cheapFruit() ~= nil
        or (Player.data("Beli") or 0) >= Tasks.RAID_BELI
end

Tasks.COLOUR_FRAGMENTS = 7500

-- Whether rip_indra is wanted (Tushita, Valkyrie Helm) but one of the three
-- legendary haki colours its pads need is missing.
function Tasks.needsColours(level, lateLevel)
    if (level or 0) < lateLevel or Config.skipped("HakiColours") then return false end
    local wanted = (not owned("Tushita") and not Config.skipped("Tushita"))
        or (not owned("Valkyrie Helm") and not Config.skipped("ValkyrieHelm"))
    return wanted and #Summons.missingColours() > 0
end

-- The fragments the next step waits on: a style of the melee chain, the
-- Soul Guitar, a legendary haki colour (late game).
function Tasks.fragmentGoal(lateLevel)
    local goal = 0
    if Tasks.needsColours(Player.level(), lateLevel or 2200) then goal = Tasks.COLOUR_FRAGMENTS end
    if not Config.skipped("Godhuman") then goal = math.max(goal, Melee.fragmentsNeeded()) end
    if not Config.skipped("SoulGuitar") and not owned("Skull Guitar") and Guitar.missing() == nil
        and (Player.level() or 0) >= 2300 then
        goal = math.max(goal, Guitar.FRAGMENTS)
    end
    return goal
end

Tasks.LIST = {
    {
        name = "CDK", priority = 1, seas = { 3 }, mode = Cdk.mode,
        keys = { ItemCDK = true },
        maxTime = 7200,
        ready = function() return Cdk.requirements() == nil end,
        done = function() return owned("Cursed Dual Katana") end,
    },
    {
        -- Tushita and Yama to 350 for the CDK (Teddy's Items Farm Force).
        name = "CdkMastery", group = "CDK", priority = 2, seas = { 3 }, mode = Cdk.mastery,
        keys = { ItemCdkMastery = true },
        ready = function() return Cdk.masteryTarget() ~= nil end,
        done = function() return owned("Cursed Dual Katana") end,
        maxTime = 7200,
    },
    {
        -- Only possible while rip_indra True Form is alive: rests until then.
        name = "Tushita", priority = 1, seas = { 3 }, mode = Swords.tushita,
        keys = { ItemTushita = true },
        done = function() return owned("Tushita") end,
        wake = function() return Enemies.findBoss({ "rip_indra True Form", "Longma" }) ~= nil end,
    },
    {
        name = "SoulGuitar", priority = 3, seas = { 2, 3 }, minLevel = 2300, mode = Guitar.mode,
        keys = function() return { ItemSoulGuitar = true, GuitarHopMoon = Config.get("Hop") == true } end,
        -- Materials need no fragments; the rest does.
        ready = function() return Guitar.missing() ~= nil or (Player.data("Fragments") or 0) >= Guitar.FRAGMENTS end,
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
        keys = function()
            return { RaidAuto = true, FruitAwaken = true, RaidCheapFruit = true, RaidName = Tasks.fruitRaid() or "Flame" }
        end,
        ready = function()
            local raid = Tasks.fruitRaid()
            -- Dough awakens differently (Teddy leaves it out too).
            if not raid or raid == "Dough" or not Tasks.canPayRaid() then return false end
            local can = Tasks.awakening()
            return can
        end,
        done = function()
            local _, all = Tasks.awakening()
            return all
        end,
        maxTime = 1800,
    },
    {
        -- Teddy's Minimum Fragment: raids while fragments hold a step back.
        name = "Fragments", priority = 6, seas = { 2, 3 }, minLevel = Raids.MIN_LEVEL, mode = Raids.solo,
        keys = function()
            local raid = Tasks.fruitRaid()
            if raid == "Dough" then raid = nil end
            return { RaidAuto = true, RaidCheapFruit = true, FruitAwaken = true, RaidName = raid or "Flame" }
        end,
        ready = function()
            return (Player.data("Fragments") or 0) < Tasks.fragmentGoal() and Tasks.canPayRaid()
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
        -- Electric is a Sea 1 quest. Before Saber (priority 3): it is part of
        -- the Godhuman chain, and the quest itself costs nothing, only the
        -- delivery ($500,000). From a later sea only with the money and once
        -- Black Leg and Fishman are ready for Superhuman, so the trip back is
        -- worth it.
        name = "Electric", group = "Godhuman", priority = 3, seas = { 1, 2, 3 }, mode = Electric.mode,
        keys = { ItemElectric = true },
        ready = function()
            local beli = Player.data("Beli") or 0
            if Electric.state() == Electric.STATE_HAS_BOLT and beli < Electric.PRICE then return false end
            if Player.sea() == 1 then return true end
            return beli >= Electric.PRICE
                and Melee.mastery("Black Leg") >= Melee.SUPERHUMAN_NEEDS
                and Melee.mastery("Fishman Karate") >= Melee.SUPERHUMAN_NEEDS
        end,
        done = function() return Electric.owned() end,
        -- The charged clouds are rare: after 3 minutes without one, another
        -- server.
        hop = function()
            if Player.sea() ~= 1 then return nil end
            local state = Electric.state()
            if (state == 1 or state == 2) and not Electric.target() then return "no charged storm cloud" end
            return nil
        end,
        hopAfter = 180,
        maxTime = 3600,
    },
    {
        -- Teddy's Library Key / Water Key and Sea 2 Key Hop: from Sea 3 only
        -- once the key holds the style back; then hop for the boss.
        name = "LibraryKey", group = "Godhuman", priority = 4, seas = { 2, 3 }, minLevel = 850, mode = Melee.libraryKey,
        keys = { ItemLibraryKey = true },
        ready = function() return Player.sea() == 2 or Melee.libraryKey.needed() end,
        done = function() return Melee.unlocked("Death Step") end,
        hop = function() return Melee.libraryKey.needed() and Melee.libraryKey.missing() or nil end,
    },
    {
        name = "WaterKey", group = "Godhuman", priority = 4, seas = { 2, 3 }, minLevel = 850, mode = Melee.waterKey,
        keys = { ItemWaterKey = true },
        ready = function() return Player.sea() == 2 or Melee.waterKey.needed() end,
        done = function() return Melee.unlocked("Sharkman Karate") end,
        hop = function() return Melee.waterKey.needed() and Melee.waterKey.missing() or nil end,
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
        -- Elite hops only at the max level: before, they would replace the
        -- level farm (the task comes up whenever nothing else does).
        keys = function()
            return { ItemYama = true, StackHopElite = Config.get("Hop") == true and (Player.level() or 0) >= Tasks.MAX_LEVEL }
        end,
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
    { label = "Helm", item = "Valkyrie Helm" },
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
