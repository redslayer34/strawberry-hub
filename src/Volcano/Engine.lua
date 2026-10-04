--=============================================================================
-- VOLCANO ENGINE — the Prehistoric Island loop, on its own
--=============================================================================
--  Banana's "Fully Event Prehistoric Island" is already the hub's
--  Volcano.fully mode (Features/Sea/Volcano): magnet, sailing out, the
--  event, golems, rocks, eggs, bones, and a reset once the island is done.
--  This engine only sets the hub settings that mode needs from the
--  StrawberryVolcano config, sends the character to Sea 3, and keeps the
--  counts the panel shows. Once a second; nothing here moves the character.
--=============================================================================

local Boat = require("Game.Boat")
local Common = require("Features.Stack.Common")
local Config = require("Volcano.Config")
local Data = require("Game.Data")
local Farm = require("Features.Farm")
local Loop = require("Core.Loop")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local Volcano = require("Features.Sea.Volcano")

local Engine = {}

Engine.EVERY = 1
Engine.SEA = 3
Engine.SEA_LEVEL = 1500
Engine.TRAVEL_EVERY = 60
Engine.LOG_SIZE = 6
Engine.WEAPONS = { Melee = true, Sword = true, ["Blox Fruit"] = true }
Engine.EGG = "Dragon Egg"

local applied = {}
local log = {}
local counts, last = {}, {}
local lastTravel = -math.huge
local seaNote

local function note(text)
    table.insert(log, 1, string.format("[%s] %s", os.date and os.date("%H:%M") or "--:--", text))
    while #log > Engine.LOG_SIZE do table.remove(log) end
end

local function isBoat(name)
    for _, known in ipairs(Boat.NAMES) do
        if known == name then return true end
    end
    return false
end

-- The hub settings for `config` (a key left out: the loaded config's).
function Engine.keys(config)
    local function get(key)
        local value = config and config[key]
        if value == nil then return Config.get(key) end
        return value
    end
    local weapon = Engine.WEAPONS[get("Weapon")] and get("Weapon") or "Melee"
    local boat = isBoat(get("Boat")) and get("Boat") or "Guardian"
    local keys = {
        VolcanoFully = true,
        VolcanoGolemWeapon = weapon,
        Weapon = weapon,
        VolcanoSkipMagnet = get("CraftMagnet") == false,
        VolcanoSkipBones = get("CollectBones") == false,
        VolcanoSkipEggs = get("CollectEggs") == false,
        SeaBoat = boat,
        SeaBoatSpeed = tonumber(get("BoatSpeed")) or 350,
        SeaSkillWeapons = get("SkillWeapons"),
        TweenSpeed = tonumber(get("Speed")) or 300,
        BringMob = true,
        SmartTravel = true,
        ResetTeleport = true,
        AutoKen = true,
        LowHpEscape = true,
        PvpWaterWalk = get("WalkOnWater") ~= false,
        ScreenBlack = get("BlackScreen") == true,
        ScreenBoostFps = get("FpsBoost") == true,
    }
    local url = get("WebhookUrl")
    if type(url) == "string" and url ~= "" then
        keys.WebhookUrl = url
        keys.WebhookPrehistoric = true
    end
    return keys
end

function Engine.apply(keys)
    for key, value in pairs(keys) do
        applied[key] = true
        if Settings.get(key) ~= value then pcall(Settings.set, key, value) end
    end
end

---------------------------------------------------------------------------
-- Loot (read from the inventory)
---------------------------------------------------------------------------

-- The count of the first item whose name holds `pattern` (lower case).
local function countLike(pattern)
    for _, item in ipairs(Common.inventory()) do
        if type(item.name) == "string" and item.name:lower():find(pattern, 1, true) then
            return item.count or 0
        end
    end
    return 0
end

function Engine.eggs()
    return countLike(Engine.EGG:lower())
end

-- The bones' item name is not certain ("Dinosaur Bones", "Dino Bones"...).
function Engine.bones()
    return countLike("dino")
end

---------------------------------------------------------------------------
-- Sea 3
---------------------------------------------------------------------------

-- nil in Sea 3, otherwise what is done about it.
function Engine.seaStep(sea, level)
    if sea == Engine.SEA then return nil end
    -- Not read yet (an unknown place, the realm still answering): no
    -- TravelZou from Sea 3 itself.
    if not sea then return "Reading the sea" end
    if (level or 0) < Engine.SEA_LEVEL then
        return "The Prehistoric Island is in Sea 3 (level " .. Engine.SEA_LEVEL .. ")"
    end
    local now = os.clock()
    if now - lastTravel >= Engine.TRAVEL_EVERY then
        lastTravel = now
        pcall(Services.invoke, Data.TRAVEL[Engine.SEA])
        note("travelling to Sea 3")
    end
    return "Travelling to Sea 3"
end

---------------------------------------------------------------------------
-- Counts, from what changed since the last tick
---------------------------------------------------------------------------

function Engine.track()
    local island = Volcano.island() ~= nil
    local running = Volcano.running() == true
    local eggs = Engine.eggs()
    local bones = Engine.bones()
    local magnet = Common.item("Volcanic Magnet") ~= nil
    if island and last.island == false then
        counts.islands = counts.islands + 1
        note("Prehistoric Island spawned")
    end
    if not running and last.running == true then
        counts.events = counts.events + 1
        note("volcano event over")
    end
    if last.eggs and eggs > last.eggs then
        counts.eggs = counts.eggs + (eggs - last.eggs)
        note("dragon egg collected (" .. eggs .. ")")
    end
    if last.bones and bones > last.bones then counts.bones = counts.bones + (bones - last.bones) end
    if magnet and last.magnet == false then
        counts.magnets = counts.magnets + 1
        note("Volcanic Magnet crafted")
    end
    last.island, last.running, last.eggs, last.bones, last.magnet = island, running, eggs, bones, magnet
end

function Engine.tick()
    local sea, level = Player.sea(), Player.level()
    seaNote = Engine.seaStep(sea, level)
    Engine.apply(Engine.keys())
    pcall(Engine.track)
end

function Engine.start()
    pcall(function()
        require("Game.Router").listener = function(text) note("travel: " .. text) end
    end)
    note("started: craft, find, event" .. (Config.get("CollectEggs") == false and "" or ", eggs")
        .. (Config.get("CollectBones") == false and "" or ", bones")
        .. ", reset, again")
    Engine.tick()
    Loop.start("Volcano", Engine.EVERY, Engine.tick)
end

-- Back to defaults for every key set here.
function Engine.stop()
    Loop.stop("Volcano")
    for key in pairs(applied) do pcall(Settings.set, key, Settings.DEFAULTS[key]) end
    applied = {}
end

---------------------------------------------------------------------------
-- For the panel
---------------------------------------------------------------------------

function Engine.status()
    local island = Volcano.island() ~= nil
    local held = Common.item("Volcanic Magnet") ~= nil
    local scrap, embers = Common.itemCount("Scrap Metal"), Common.itemCount("Blaze Ember")
    local magnet
    if held then
        magnet = "held"
    else
        magnet = string.format("Scrap Metal %d/%d  ·  Blaze Ember %d/%d", scrap, Volcano.SCRAP, embers, Volcano.EMBERS)
    end
    -- What the next magnet still needs.
    local missing = {}
    if scrap < Volcano.SCRAP then missing[#missing + 1] = (Volcano.SCRAP - scrap) .. " Scrap Metal" end
    if embers < Volcano.EMBERS then missing[#missing + 1] = (Volcano.EMBERS - embers) .. " Blaze Ember" end
    return {
        step = seaNote or Farm.status(),
        island = not island and "not here" or (Volcano.running() and "event running" or "here"),
        magnet = magnet,
        magnetHeld = held,
        scrap = scrap,
        embers = embers,
        missing = missing,
        eggs = Engine.eggs(),
        bones = Engine.bones(),
        islands = counts.islands,
        events = counts.events,
        magnets = counts.magnets,
        eggsGained = counts.eggs,
        bonesGained = counts.bones,
        sea = Player.sea(),
        level = Player.level(),
        log = log,
    }
end

-- Test hook.
function Engine.reset()
    applied, log = {}, {}
    counts = { islands = 0, events = 0, eggs = 0, bones = 0, magnets = 0 }
    last = {}
    lastTravel, seaNote = -math.huge, nil
end

Engine.reset()

return Engine
