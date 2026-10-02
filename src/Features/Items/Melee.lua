--=============================================================================
-- ITEMS: MELEE PROGRESSION — up to Godhuman
--=============================================================================
--  Godhuman needs Superhuman, Death Step, Sharkman Karate, Electric Claw and
--  Dragon Talon at 400 mastery, 20 Fish Tail, 20 Magma Ore, 10 Dragon Scale,
--  10 Mystic Droplet, 5000 fragments and $5M. Each of those styles needs
--  its first-sea style at 400 (Black Leg, Fishman Karate, Electric, Dragon
--  Claw), and Superhuman all four at 300. So the chain below (the Teddy
--  Kaitun's) takes every style to 400 in order; the farms do the mastery
--  with Weapon = "Melee", this only learns and equips the right style.
--
--  Electric ("Electro") is no longer a plain purchase: the Mad Scientist
--  wants a Lightning Bolt first (Features/Items/Electric). Death Step,
--  Sharkman, Electric Claw and Dragon Talon are locked behind a key, a
--  quest or an item: the unlock modes below get them.
--
--    owned style      LoadItem (styles stay in the inventory)
--    not owned        its teacher (the sea's NPC), the CommF_ purchase
--=============================================================================

local Common = require("Features.Stack.Common")
local Data = require("Game.Data")
local Enemies = require("Game.Enemies")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local World = require("Game.World")

local Melee = {}

Melee.TARGET = 400
Melee.SUPERHUMAN_NEEDS = 300
Melee.UNLOCK_CACHE = 60
Melee.LOAD_EVERY = 6
Melee.BUY_EVERY = 3
Melee.ELECTRIC_CLAW_SPOT = Vector3.new(-12547.1396484375, 337.16827392578125, -7471.8818359375)

-- Teddy's requirements (MeleeV2 tbl12): level, money, fragments, the
-- styles that must be at `mastery` first, and the unlock it waits on.
Melee.CHAIN = {
    { name = "Black Leg", beli = 150000 },
    { name = "Electro", beli = 500000, quest = true },
    { name = "Fishman Karate", beli = 750000 },
    { name = "Dragon Claw", level = 700, fragments = 1500, minSea = 2 },
    { name = "Superhuman", level = 1100, beli = 3000000, minSea = 2,
        needs = { "Black Leg", "Electro", "Fishman Karate", "Dragon Claw" }, mastery = 300 },
    { name = "Death Step", level = 700, beli = 2500000, fragments = 5000, minSea = 2,
        needs = { "Black Leg" }, unlock = "Death Step" },
    { name = "Sharkman Karate", level = 700, beli = 2500000, fragments = 5000, minSea = 2,
        needs = { "Fishman Karate" }, unlock = "Sharkman Karate" },
    { name = "Electric Claw", level = 2000, beli = 3000000, fragments = 5000, minSea = 3,
        needs = { "Electro" }, unlock = "Electric Claw" },
    { name = "Dragon Talon", level = 1500, beli = 3000000, fragments = 5000, minSea = 3,
        needs = { "Dragon Claw" }, unlock = "Dragon Talon" },
    { name = "Godhuman", level = 1500, beli = 5000000, fragments = 5000, minSea = 3,
        needs = { "Superhuman", "Death Step", "Sharkman Karate", "Electric Claw", "Dragon Talon" },
        unlock = "Godhuman", final = true },
}

-- By sea (Sea 3 ones, then Sea 2 ones), so the farm crosses over once.
Melee.GODHUMAN_MATERIALS = {
    { name = "Fish Tail", count = 20 },
    { name = "Dragon Scale", count = 10 },
    { name = "Magma Ore", count = 20 },
    { name = "Mystic Droplet", count = 10 },
}

Melee.MAX_TRIES = 5        -- purchases / loads of one style that change nothing
Melee.GIVE_UP = 600        -- then the style is left alone this long
Melee.WALK_LIMIT = 90      -- seconds flying to a teacher before the style is left alone

local walkSince = {}       -- [style] = when the flight to its teacher started

local unlockCache = {}   -- [style] = { value, at }
local lastLoad, lastBuy = -math.huge, -math.huge
local tries, givenUp = {}, {}   -- [style] = count, [style] = until

-- One more try at `name`; past MAX_TRIES the style is left alone for a
-- while, so a purchase the server keeps refusing (or a teacher that is not
-- there) cannot hold the character at an NPC: this mode runs above the
-- farms.
local function attempt(name)
    tries[name] = (tries[name] or 0) + 1
    if tries[name] >= Melee.MAX_TRIES then
        tries[name], givenUp[name] = 0, os.clock() + Melee.GIVE_UP
    end
end

function Melee.givenUp(name)
    local untilAt = givenUp[name]
    if not untilAt then return false end
    if os.clock() < untilAt then return true end
    givenUp[name] = nil
    return false
end

---------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------

local function aliases(name)
    local style = Data.fightingStyle(name)
    return style and style.inv or { name }
end

-- The inventory entry of a style under any of its names, or nil.
-- Only a fighting style counts: "Electric" or "Dragon Breath" could also be
-- the name of something else in the inventory (a material, an accessory).
local MELEE_TYPES = { Melee = true, ["Fighting Style"] = true, ["Fighting style"] = true }

local function isStyle(item)
    return item.type == nil or item.type == "" or MELEE_TYPES[item.type] == true
end

function Melee.entry(name)
    for _, alias in ipairs(aliases(name)) do
        for _, item in ipairs(Common.inventory()) do
            if item.name == alias and isStyle(item) then return item end
        end
    end
    return nil
end

function Melee.owned(name)
    for _, alias in ipairs(aliases(name)) do
        if Common.owns(alias, "Melee") then return true end
    end
    return false
end

-- Who says the style is owned (for the screen), or nil.
function Melee.ownedBy(name)
    for _, alias in ipairs(aliases(name)) do
        local source = Common.ownedBy(alias, "Melee")
        if source then return source .. " (" .. alias .. ")" end
    end
    return nil
end

function Melee.mastery(name)
    local best = 0
    for _, alias in ipairs(aliases(name)) do
        best = math.max(best, Common.masteryOf(alias))
    end
    return best
end

-- The style held as the Melee weapon right now (its shop name), or nil.
function Melee.equipped()
    local tool = Player.findTool("Melee")
    if not tool then return nil end
    for _, style in ipairs(Data.FIGHTING_STYLES) do
        for _, alias in ipairs(style.inv or { style.name }) do
            if tool.Name == alias then return style.name end
        end
    end
    return tool.Name
end

---------------------------------------------------------------------------
-- Unlocks (Teddy's checks: the purchase call with `true` only asks)
---------------------------------------------------------------------------

local UNLOCK_CHECKS = {
    ["Death Step"] = function()
        local answer = Services.invoke("BuyDeathStep", true)
        return answer == 1 or answer == 2
    end,
    ["Sharkman Karate"] = function()
        local answer = Services.invoke("BuySharkmanKarate", true)
        return answer == 0 or answer == 1 or answer == 2 or answer == 3
    end,
    ["Electric Claw"] = function()
        local answer = Services.invoke("BuyElectricClaw", true)
        return answer == 0 or answer == 1 or answer == 2 or answer == 3
    end,
    ["Dragon Talon"] = function()
        local answer = Services.invoke("BuyDragonTalon", true)
        return answer ~= nil and answer ~= "Set your heart ablaze."
    end,
    -- 0: materials gathered, 1: owned (Teddy's CheckGodhumanMaterialStatus).
    Godhuman = function()
        local answer = Services.invoke("BuyGodhuman", true)
        return answer == 0 or answer == 1
    end,
}

function Melee.unlocked(name)
    if Melee.owned(name) then return true end
    local check = UNLOCK_CHECKS[name]
    if not check then return true end
    local cached = unlockCache[name]
    if cached and os.clock() - cached.at < Melee.UNLOCK_CACHE then return cached.value end
    local ok, value = pcall(check)
    value = ok and value == true
    unlockCache[name] = { value = value, at = os.clock() }
    return value
end

function Melee.forget(name)
    if name then unlockCache[name] = nil else unlockCache = {} end
end

---------------------------------------------------------------------------
-- The plan
---------------------------------------------------------------------------

local function step(name)
    for _, entry in ipairs(Melee.CHAIN) do
        if entry.name == name then return entry end
    end
    return nil
end
Melee.step = step

-- Why `entry` cannot be bought now, or nil.
function Melee.missing(entry)
    local sea = Player.sea() or 1
    if entry.minSea and sea < entry.minSea then return "Sea " .. entry.minSea end
    if entry.level and (Player.level() or 0) < entry.level then return "level " .. entry.level end
    for _, need in ipairs(entry.needs or {}) do
        if Melee.mastery(need) < (entry.mastery or Melee.TARGET) then
            return need .. " " .. (entry.mastery or Melee.TARGET)
        end
    end
    if entry.quest then return "the Lightning Bolt quest" end
    if entry.unlock and not Melee.unlocked(entry.unlock) then return "unlock" end
    if entry.beli and (Player.data("Beli") or 0) < entry.beli then return "$" .. entry.beli end
    if entry.fragments and (Player.data("Fragments") or 0) < entry.fragments then
        return entry.fragments .. " fragments"
    end
    return nil
end

local function finished(entry)
    return Melee.owned(entry.name) and (entry.final or Melee.mastery(entry.name) >= Melee.TARGET)
end

-- Whether a style still matters: Godhuman always, the others while a style
-- that needs them is not finished (no point buying Black Leg back once
-- Death Step and Superhuman are at 400).
function Melee.useful(entry)
    if entry.final then return true end
    for _, later in ipairs(Melee.CHAIN) do
        for _, need in ipairs(later.needs or {}) do
            if need == entry.name and not finished(later) then return true end
        end
    end
    return false
end

-- Whether `name` may be bought now as far as the chain goes: every style
-- before it that is owned (and still useful) is at 400 first. The user's
-- rule for Godhuman: one style at a time, each taken to 400 before the
-- next. Returns ok, and the style still under 400.
function Melee.turnOf(name)
    for _, entry in ipairs(Melee.CHAIN) do
        if entry.name == name then return true end
        if not entry.final and Melee.useful(entry) and Melee.owned(entry.name) and not finished(entry) then
            return false, entry.name
        end
    end
    return true
end

-- The style to work on: the first useful one in the chain that is owned and
-- under 400 (farm it) or can be bought. Otherwise the best owned one.
-- Returns name, "owned" | "buy".
function Melee.current()
    for _, entry in ipairs(Melee.CHAIN) do
        if Melee.useful(entry) then
            if Melee.owned(entry.name) then
                if not finished(entry) or entry.final then return entry.name, "owned" end
            elseif not Melee.missing(entry) then
                return entry.name, "buy"
            end
        end
    end
    for index = #Melee.CHAIN, 1, -1 do
        local name = Melee.CHAIN[index].name
        if Melee.owned(name) then return name, "owned" end
    end
    return nil, nil
end

-- What the mode has to do: "load", "buy", or nil (the farms do the rest).
function Melee.action()
    local name, state = Melee.current()
    if not name or Melee.givenUp(name) then return nil, name end
    if state == "buy" then return "buy", name end
    if Melee.equipped() ~= name then return "load", name end
    tries[name] = 0
    return nil, name
end

local function buy(mode, name)
    local style = Data.fightingStyle(name)
    if not style then return "Unknown style " .. name end
    -- Dragon Claw is Sabi's reward: the call works from anywhere.
    if name == "Dragon Claw" then
        Movement.stop()
        if os.clock() - lastBuy >= Melee.BUY_EVERY then
            lastBuy = os.clock()
            attempt(name)
            for _, call in ipairs(style.calls) do Services.invoke((table.unpack or unpack)(call)) end
            Common.forget()
            Melee.forget()
        end
        return "Claiming Dragon Claw"
    end
    -- The NPC when it is loaded, otherwise the teacher's spot in this sea
    -- (Teddy's table): an NPC out of streaming range is not in the list.
    local where = World.npcPosition(style.npc) or (style.at and style.at[Player.sea() or 0])
    if not where then
        if style.sea and not Common.travel(style.sea) then return "Travelling to Sea " .. style.sea .. " for " .. name end
        Movement.stop()
        if os.clock() - lastBuy >= Melee.BUY_EVERY then
            lastBuy = os.clock()
            attempt(name)
        end
        return "Looking for " .. style.npc
    end
    Common.goTo(CFrame.new(where + Vector3.new(0, 0, 4)))
    if not Common.near(where, 10) then
        -- This mode runs above the farms: a teacher it cannot reach must
        -- not hold the character forever.
        walkSince[name] = walkSince[name] or os.clock()
        if os.clock() - walkSince[name] > Melee.WALK_LIMIT then
            walkSince[name] = nil
            tries[name], givenUp[name] = 0, os.clock() + Melee.GIVE_UP
        end
        return "Going to " .. style.npc .. " for " .. name
    end
    walkSince[name] = nil
    if os.clock() - lastBuy >= Melee.BUY_EVERY then
        lastBuy = os.clock()
        attempt(name)
        for _, call in ipairs(style.calls) do Services.invoke((table.unpack or unpack)(call)) end
        Common.forget()
        Melee.forget()
    end
    return "Buying " .. name
end

local function load(name)
    Movement.stop()
    if os.clock() - lastLoad >= Melee.LOAD_EVERY then
        lastLoad = os.clock()
        attempt(name)
        local item = Melee.entry(name)
        Services.invoke("LoadItem", item and item.name or name)
        Common.forget()
    end
    return "Equipping " .. name
end

Melee.mode = Mode({
    name = "Melee",
    key = "ItemMeleeProgress",
    want = function() return Melee.action() ~= nil end,
    idleStatus = "Farming mastery on the current style",
    tick = function(mode)
        local action, name = Melee.action()
        if action == "buy" then return buy(mode, name) end
        if action == "load" then return load(name) end
        return "Nothing to do"
    end,
})

-- Text for the screens: the style and its mastery, or what it waits on.
function Melee.describe()
    local name, state = Melee.current()
    if not name then return "no style yet" end
    if state == "buy" then return "buying " .. name end
    local entry = step(name)
    if entry and entry.final then return name .. " " .. Melee.mastery(name) end
    return string.format("%s %d/%d", name, Melee.mastery(name), Melee.TARGET)
end

-- The fragments the next style waits on, or 0 (the Kaitun raids for them).
function Melee.fragmentsNeeded()
    for _, entry in ipairs(Melee.CHAIN) do
        if entry.fragments and Melee.useful(entry) and not Melee.owned(entry.name) then
            local missing = Melee.missing(entry)
            if missing == entry.fragments .. " fragments" then return entry.fragments end
        end
    end
    return 0
end

-- The first Godhuman material still short, or nil.
function Melee.missingMaterial()
    for _, material in ipairs(Melee.GODHUMAN_MATERIALS) do
        if Common.itemCount(material.name) < material.count then return material.name end
    end
    return nil
end

---------------------------------------------------------------------------
-- Unlock modes
---------------------------------------------------------------------------

-- A key that a boss drops, then the call that uses it (Teddy's "Library
-- Key" and "Water Key"). The boss lives in Sea 2; from another sea the mode
-- only goes back once the key is what holds the style back (`needs` at
-- 400), otherwise it waits for the boss to show up while passing by.
local function keyMode(spec)
    local function holding()
        return Common.has(spec.item) or Common.itemCount(spec.item) > 0
    end
    local mode = Mode({
        name = spec.name,
        key = spec.key,
        want = function()
            if Melee.unlocked(spec.style) then return false end
            if holding() then return true end
            if Player.sea() ~= 2 then return Melee.mastery(spec.needs) >= Melee.TARGET end
            return Enemies.findBoss(spec.boss) ~= nil
        end,
        idleStatus = "Unlocked, or " .. spec.boss .. " not on this server",
        tick = function(mode)
            if holding() then
                Movement.stop()
                if Common.every(spec.key, 2) then
                    Services.invoke((table.unpack or unpack)(spec.use))
                    Common.forget()
                    Melee.forget(spec.style)
                end
                return "Using the " .. spec.item
            end
            if not Common.travel(2) then return "Travelling to Sea 2 for the " .. spec.item end
            local boss, inWorld = Enemies.findBoss(spec.boss)
            if boss then return Common.fight(mode, boss, inWorld) end
            Movement.stop()
            return "Waiting for " .. spec.boss
        end,
    })
    -- For the Kaitun: the key is what holds the style back now.
    function mode.needed()
        return not Melee.unlocked(spec.style) and Melee.mastery(spec.needs) >= Melee.TARGET
    end
    -- What this server lacks, or nil.
    function mode.missing()
        if Player.sea() ~= 2 or holding() or Enemies.findBoss(spec.boss) then return nil end
        return "no " .. spec.boss
    end
    return mode
end

Melee.libraryKey = keyMode({
    name = "Library Key", key = "ItemLibraryKey", style = "Death Step", needs = "Black Leg",
    item = "Library Key", boss = "Awakened Ice Admiral", use = { "OpenLibrary" },
})

Melee.waterKey = keyMode({
    name = "Water Key", key = "ItemWaterKey", style = "Sharkman Karate", needs = "Fishman Karate",
    item = "Water Key", boss = "Tide Keeper", use = { "BuySharkmanKarate", true },
})

-- The Previous Hero's run (Teddy: at the Mansion, BuyElectricClaw Start).
Melee.electricClaw = Mode({
    name = "Electric Claw quest",
    key = "ItemElectricClaw",
    sea = 3,
    want = function()
        return not Melee.unlocked("Electric Claw") and Melee.mastery("Electro") >= Melee.TARGET
    end,
    idleStatus = "Unlocked, or Electric under 400",
    tick = function()
        Common.goTo(Melee.ELECTRIC_CLAW_SPOT)
        if not Common.near(Melee.ELECTRIC_CLAW_SPOT, 15) then return "Going to the Mansion" end
        if Common.every("ElectricClawStart", 2) then
            Services.invoke("BuyElectricClaw", "Start")
            Melee.forget("Electric Claw")
        end
        return "Electric Claw quest"
    end,
})

Melee.ROLLS_CACHE = 30
local rolls = { at = -math.huge }

-- Rolls the Death King allows right now ("Bones", "Check": the third value,
-- Teddy's CheckRandomBone), or nil when the server does not say.
function Melee.boneRolls()
    if os.clock() - rolls.at < Melee.ROLLS_CACHE then return rolls.left end
    rolls.at = os.clock()
    local commF = Services.commF()
    local ok, _, _, left = false, nil, nil, nil
    if commF then ok, _, _, left = pcall(commF.InvokeServer, commF, "Bones", "Check") end
    rolls.left = ok and tonumber(left) or nil
    return rolls.left
end

-- Dragon Talon wants a Fire Essence, from the Death King's bone gacha.
Melee.dragonTalon = Mode({
    name = "Fire Essence",
    key = "ItemDragonTalon",
    sea = 3,
    want = function()
        if Melee.unlocked("Dragon Talon") then return false end
        if Common.has("Fire Essence") or Common.itemCount("Fire Essence") > 0 then return true end
        local left = Melee.boneRolls()
        return Common.itemCount("Bones") >= 50 and (left == nil or left > 0)
    end,
    idleStatus = "Unlocked, or under 50 bones",
    tick = function()
        if Common.has("Fire Essence") or Common.itemCount("Fire Essence") > 0 then
            local where = World.npcPosition("Uzoth")
            if not where then
                Movement.stop()
                return "Looking for Uzoth"
            end
            Common.goTo(CFrame.new(where + Vector3.new(0, 0, 4)))
            if not Common.near(where, 10) then return "Taking the Fire Essence to Uzoth" end
            if Common.every("DragonTalonUnlock", 2) then
                Services.invoke("BuyDragonTalon", true)
                Common.forget()
                Melee.forget("Dragon Talon")
            end
            return "Giving the Fire Essence"
        end
        Movement.stop()
        if Common.every("FireEssenceRoll", 1) then
            Services.invoke("Bones", "Buy", 1, 1)
            Common.forgetInventory()
            rolls.at = -math.huge
        end
        return string.format("Rolling bones for a Fire Essence (%d bones)", Common.itemCount("Bones"))
    end,
})

-- Test hook.
function Melee.reset()
    unlockCache = {}
    lastLoad, lastBuy = -math.huge, -math.huge
    tries, givenUp, walkSince = {}, {}, {}
    rolls = { at = -math.huge }
end

return Melee
