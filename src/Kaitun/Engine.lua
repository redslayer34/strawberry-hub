--=============================================================================
-- KAITUN ENGINE — decides which hub settings are on, once a second
--=============================================================================
--  The Teddy Kaitun pops tasks from a priority queue and farms levels when
--  the queue is empty. Here the same idea drives the hub's own modes through
--  their settings, in three layers (Farm.MODES already runs the first
--  enabled mode, so the layers only have to switch the right keys on):
--
--    background  stack events of the current sea (bosses, elites, factory,
--                the Sea 2 / Sea 3 quests) and the helpers: they only take
--                the character when something is up
--    task        one long job at a time (Tasks.LIST), the first by priority
--                that is ready and not resting
--    idle        Teddy's fn22: level farm until the max level, then bones
--                while Dragon Talon is locked, then Katakuri
--
--  God's Chalice (elites, chests) can summon rip_indra or, as a Sweet
--  Chalice, Dough King; both summons would take it. The chalice plan picks
--  one, in Teddy's order: rip_indra while Tushita is missing (its torches
--  need rip_indra alive), Dough King while there is no Mirror Fractal,
--  rip_indra again for the Valkyrie Helm. rip_indra's pads need the three
--  legendary haki colours, bought from the Colors Dealer.
--
--  Hops (with Hop on), Teddy's targeted ones:
--    task.hop()     what this server lacks for the current task (the Sea 2
--                   keys' bosses, a charged storm cloud)
--    Swan door      a fruit worth 1M for Trevor (Sea 2, level 1500), when
--                   the money for one on sale is far off
--    max level      the haki colour dealer, Mirror Fractal (an elite for a
--                   chalice), the Valkyrie Helm / Tushita (an elite or
--                   rip_indra)
--  A reason must hold HOP_AFTER seconds (task.hopAfter for a task); the late
--  game ones only while no task is working and no stack event is on.
--
--  Watchdog, so one job can never hold the Kaitun forever:
--    its mode says "nothing to do" for IDLE_LIMIT s   -> rests IDLE_PAUSE s
--    the same status for STUCK_LIMIT s, or maxTime    -> rests STUCK_PAUSE s
--  Each new rest of the same task lasts twice as long (up to REST_MAX), so a
--  job that cannot be done (a race V3 the Kaitun cannot do) fades out.
--=============================================================================

local Cdk = require("Features.Items.Cdk")
local Common = require("Features.Stack.Common")
local Config = require("Kaitun.Config")
local Data = require("Game.Data")
local Enemies = require("Game.Enemies")
local EliteHunter = require("Features.Stack.EliteHunter")
local Farm = require("Features.Farm")
local Fruits = require("Features.Fruits")
local Loop = require("Core.Loop")
local Melee = require("Features.Items.Melee")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local SkipLevel = require("Features.SkipLevel")
local StackFarm = require("Features.StackFarm")
local StackWorld = require("Features.Stack.World")
local Summons = require("Features.Stack.Summons")
local Tasks = require("Kaitun.Tasks")

local Engine = {}

Engine.EVERY = 1
Engine.MAX_LEVEL = Tasks.MAX_LEVEL
Engine.LATE_LEVEL = 2200       -- chalice plan, haki colours, late hops (Teddy's CDK gate)
Engine.IDLE_LIMIT = 30
Engine.IDLE_PAUSE = 300
Engine.STUCK_LIMIT = 300
Engine.STUCK_PAUSE = 600
Engine.REST_MAX = 3600
Engine.DEFAULT_MAX_TIME = 1800
Engine.DONE_CACHE = 15
Engine.TRAVEL_EVERY = 60
Engine.HOP_AFTER = 20
Engine.LOG_SIZE = 10
Engine.SEA_LEVEL = { [2] = 700, [3] = 1500 }
Engine.COCOA = 10
Engine.COLOUR_FRAGMENTS = Tasks.COLOUR_FRAGMENTS
Engine.ROLL_BELI = 10000000    -- the Cousin's gacha only with money to spare
Engine.BUY_EVERY = 5

local current, startedAt
local currentWorking = false
local planCache = { at = -math.huge, list = {} }
local idleSince, lastStatus, statusSince
local rest = {}        -- [task name] = { untilAt, why, count }
local doneCache = {}   -- [task name] = { done, at }
local applied = {}     -- keys the Kaitun has set
local log = {}
local lastTravel, lastBuy = -math.huge, -math.huge
local idleName = "Idle"
local taskHop, taskHopAfter
local hopReason, hopSince, hopNote

local function now() return os.clock() end

local function note(text)
    table.insert(log, 1, string.format("[%s] %s", os.date and os.date("%H:%M") or "--:--", text))
    while #log > Engine.LOG_SIZE do table.remove(log) end
end

local function has(name)
    return Tasks.owned(name)
end

---------------------------------------------------------------------------
-- Late game: the chalice plan and the haki colours
---------------------------------------------------------------------------

-- "rip" or "dough" and what it is for, or nil.
function Engine.chalicePlan(level)
    if level < Engine.LATE_LEVEL then return nil end
    local colours = #Summons.missingColours() == 0
    if colours and not has("Tushita") and not Config.skipped("Tushita") then return "rip", "Tushita" end
    if Common.itemCount("Mirror Fractal") == 0 and not Config.skipped("MirrorFractal") then
        return "dough", "Mirror Fractal"
    end
    if colours and not has("Valkyrie Helm") and not Config.skipped("ValkyrieHelm") then
        return "rip", "Valkyrie Helm"
    end
    return nil
end

-- Whether rip_indra is wanted but a legendary colour is missing.
function Engine.needsColours(level)
    return Tasks.needsColours(level, Engine.LATE_LEVEL)
end

-- The legendary colour the dealer sells on this server, if it is missing.
function Engine.dealerColour()
    local reply = Common.invoke("ColorsDealer", "1")
    if type(reply) ~= "string" then return nil end
    for _, colour in ipairs(Summons.missingColours()) do
        if reply:find(colour, 1, true) then return colour end
    end
    return nil
end

---------------------------------------------------------------------------
-- Layers
---------------------------------------------------------------------------

-- Helpers and the stack events of the current sea. `anchored`: something
-- is being done in this sea on purpose (a task of this sea, the melee chain
-- at a teacher), so the quests that send the player to the next sea (New
-- World, Third World) wait: they would take the player away mid-job.
function Engine.background(sea, level, anchored)
    local keys = {
        AutoStats = true,
        StatTargets = Config.get("Stats"),
        FruitStore = Config.get("StoreFruits") == true,
        FruitRandom = level >= 1100 and (Player.data("Beli") or 0) >= Engine.ROLL_BELI,
        AutoKen = true,
        AutoV3 = true,
        BringMob = true,
        SmartTravel = true,
        ResetTeleport = true,
        LowHpEscape = true,
        TweenSpeed = Config.get("Speed"),
        ScreenBlack = Config.get("BlackScreen") == true,
        ScreenBoostFps = Config.get("FpsBoost") == true,
        StackFruit = true,
        ItemMeleeProgress = not Config.skipped("Godhuman"),
    }
    -- CDK and Tushita (priority 1) come before every event, as in Teddy:
    -- while one of them works, no elite, chest, fruit or Dough King pulls
    -- the character away, and no style purchase either (a trial left half
    -- way fails). The castle raid stays: CDK's good trial 4 is one.
    if current and currentWorking and current.priority <= 1 then
        keys.StackEliteHunter, keys.StackChests, keys.StackFruit = false, false, false
        keys.StackDoughKing, keys.StackSummonDoughKing = false, false
        keys.ItemMeleeProgress = false
    end
    local url = Config.get("WebhookUrl")
    if type(url) == "string" and url ~= "" then
        keys.WebhookUrl = url
        keys.WebhookProfile = true
        keys.WebhookStoreFruit = true
    end
    if sea == 1 then
        keys.StackNewWorld = level >= Engine.SEA_LEVEL[2] and not anchored
    elseif sea == 2 then
        keys.StackThirdWorld = level >= Engine.SEA_LEVEL[3] and not anchored
        keys.StackFactory = true
        keys.StackDarkbeard = true
        keys.StackSummonDarkbeard = true
        keys.StackChests = true
    elseif sea == 3 then
        keys.StackEliteHunter = true
        keys.StackPirateRaid = true
        keys.StackChests = true
        -- rip_indra, Dough King and Soul Reaper are far above the level farm
        -- before the late game. And while Tushita is missing rip_indra must stay alive:
        -- its torches are lit while it is up (Teddy: Tushita before Rip Indra).
        local late = level >= Engine.LATE_LEVEL
        keys.StackRipIndra = late and (has("Tushita") or Config.skipped("Tushita"))
        keys.StackDoughKing = late
        keys.StackSoulReaper = late
        keys.StackSummonSoulReaper = late
        -- CDK's evil trial 4 / 5 needs Soul Reaper alive (it sends the player
        -- to Hell): no fighting it then, no summoning it before (Teddy).
        local _, evil = Cdk.progress()
        if evil == -4 or evil == -5 then keys.StackSoulReaper = false end
        if type(evil) == "number" and evil < -1 then keys.StackSummonSoulReaper = false end
        -- The summons only as the chalice plan says; the pads only with a
        -- chalice in hand (otherwise they mean a trip to the Boat Castle
        -- every few minutes for nothing).
        local plan = Engine.chalicePlan(level)
        local chalice = Common.has("God's Chalice")
        keys.StackHakiPads = plan == "rip" and chalice
        keys.StackSummonRipIndra = plan == "rip" and chalice
        keys.StackSummonDoughKing = plan == "dough"
    end
    return keys
end

-- Teddy's fn22: levels first, then in Sea 3 bones while Dragon Talon is
-- locked (its Fire Essence comes from the bone gacha), then Katakuri. The
-- idle mode stays on under the task (it is last in Farm.MODES), so a task
-- with nothing to do falls back to it at once.
function Engine.idle(sea, level)
    local keys = { Weapon = Engine.weapon() }
    if level < Engine.MAX_LEVEL or sea ~= 3 then
        keys.AutoFarmLevel = true
        keys.FarmBossQuests = true
        keys.DoubleQuest = true
        -- Teddy's skip under 150; the level farm (still on) takes over after.
        if sea == 1 and level < SkipLevel.UNTIL and Config.get("SkipLevel") ~= false then
            keys.AutoSkipLevel = true
            return keys, SkipLevel.describe() or "Level farm"
        end
        return keys, "Level farm"
    end
    -- Bones only while the Death King still rolls today (Teddy's
    -- CheckRandomBone); otherwise Katakuri.
    local rolls = Melee.boneRolls()
    if not Config.skipped("Godhuman") and not Melee.unlocked("Dragon Talon") and (rolls == nil or rolls > 0) then
        keys.AutoBone = true
        return keys, "Bones (Fire Essence)"
    end
    keys.AutoKatakuri = true
    return keys, "Katakuri"
end

-- The farms' weapon: the melee chain does the mastery through it.
function Engine.weapon()
    return "Melee"
end

---------------------------------------------------------------------------
-- Picking the task
---------------------------------------------------------------------------

local function inSea(task, sea)
    for _, s in ipairs(task.seas or {}) do
        if s == sea then return true end
    end
    return task.seas == nil
end

function Engine.isDone(task)
    if not task.done then return false end
    local cached = doneCache[task.name]
    local t = now()
    if cached and t - cached.at < Engine.DONE_CACHE then return cached.done end
    local ok, done = pcall(task.done)
    done = ok and done == true
    doneCache[task.name] = { done = done, at = t }
    return done
end

-- Why `task` cannot run now, or nil.
function Engine.blocked(task, sea, level)
    if Config.skipped(task.name) or (task.group and Config.skipped(task.group)) then return "skipped" end
    if not inSea(task, sea) then return "other sea" end
    if task.minLevel and level < task.minLevel then return "level " .. task.minLevel end
    local resting = rest[task.name]
    if resting and now() < resting.untilAt then
        -- Something the task waited for turned up (rip_indra for Tushita).
        local woke = task.wake and select(2, pcall(task.wake)) == true
        if not woke then return "resting" end
        resting.untilAt = 0
        note(task.name .. ": back early")
    end
    if Engine.isDone(task) then return "done" end
    if task.ready then
        local ok, ready = pcall(task.ready)
        if not (ok and ready) then return "not ready" end
    end
    -- Its mode has nothing to do right now: picking it would only take the
    -- character from a working task for the watchdog's 30 s.
    if task.mode and task.mode.wanted and task ~= current then
        local ok, wanted = pcall(task.mode.wanted)
        if ok and wanted == false then return "nothing to do" end
    end
    return nil
end

-- The first ready task by priority. A task that is working keeps the
-- character until it is done, rests, or a strictly more urgent one is
-- ready: a task of the same priority coming back from its rest (Saber and
-- Electric, say) must not cut a running quest in the middle.
function Engine.pick(sea, level, list)
    local keep = currentWorking and current and not Engine.blocked(current, sea, level) and current or nil
    for _, task in ipairs(Tasks.ordered(list)) do
        if keep and task.priority >= keep.priority then return keep end
        if task == keep or not Engine.blocked(task, sea, level) then return task end
    end
    return keep
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

-- Every task's keys go back to their default unless `wanted` sets them.
local function taskKeysOff(wanted, list)
    for _, task in ipairs(list or Tasks.LIST) do
        local ok, keys = pcall(Tasks.keysOf, task)
        for key in pairs(ok and keys or {}) do
            if wanted[key] == nil then wanted[key] = Settings.DEFAULTS[key] end
        end
    end
end

-- Keys only some seas or layers set: off when they do not.
Engine.LAYER_KEYS = {
    "StackNewWorld", "StackThirdWorld", "StackFactory", "StackDarkbeard", "StackSummonDarkbeard",
    "StackChests", "StackEliteHunter", "StackPirateRaid", "StackRipIndra", "StackSummonRipIndra",
    "StackHakiPads", "StackSoulReaper", "StackSummonSoulReaper", "StackDoughKing", "StackSummonDoughKing",
    "AutoFarmLevel", "AutoKatakuri", "AutoBone", "AutoSkipLevel", "FarmBossQuests",
}

-- Whether the player should stay in this sea for now.
function Engine.anchored(sea, task)
    if task and inSea(task, sea) then return true end
    return Farm.current() == Melee.mode
end

function Engine.desired(sea, level, list)
    local task = Engine.pick(sea, level, list)
    local wanted = Engine.background(sea, level, Engine.anchored(sea, task))
    local idleKeys, name = Engine.idle(sea, level)
    for key, value in pairs(idleKeys) do wanted[key] = value end
    if task then
        for key, value in pairs(Tasks.keysOf(task)) do wanted[key] = value end
    end
    for _, key in ipairs(Engine.LAYER_KEYS) do
        if wanted[key] == nil then wanted[key] = false end
    end
    taskKeysOff(wanted, list)
    return wanted, task, name
end

function Engine.apply(wanted)
    for key, value in pairs(wanted) do
        if Settings.DEFAULTS[key] ~= nil then
            applied[key] = true
            if Settings.get(key) ~= value then pcall(Settings.set, key, value) end
        end
    end
end

---------------------------------------------------------------------------
-- Watchdog
---------------------------------------------------------------------------

function Engine.rest(task, seconds, why)
    local previous = rest[task.name]
    local count = (previous and previous.count or 0) + 1
    seconds = math.min(seconds * 2 ^ (count - 1), Engine.REST_MAX)
    rest[task.name] = { untilAt = now() + seconds, why = why, count = count }
    note(task.name .. " rests " .. math.floor(seconds / 60) .. " min: " .. why)
end

-- Returns true while the task's mode is working.
local function watch(task)
    local t = now()
    taskHop, taskHopAfter = nil, nil
    if task ~= current then
        if current then note("done with " .. current.name) end
        current, startedAt, idleSince, lastStatus, statusSince = task, t, nil, nil, t
        if task then note("task: " .. task.name) end
    end
    if not task then return false end

    if Config.get("Hop") == true and task.hop then
        local ok, reason = pcall(task.hop)
        if ok and type(reason) == "string" then
            -- Waiting for a hop is not being stuck.
            taskHop, taskHopAfter = reason, task.hopAfter
            idleSince, statusSince = nil, t
            return false
        end
    end

    local mode = task.mode
    if mode then
        local ok, enabled = pcall(mode.enabled)
        if not (ok and enabled) then
            idleSince = idleSince or t
            if t - idleSince >= Engine.IDLE_LIMIT then
                Engine.rest(task, Engine.IDLE_PAUSE, "nothing to do (" .. tostring(mode.status) .. ")")
                current = nil
            end
            return false
        end
        idleSince = nil
    end

    if t - startedAt >= (task.maxTime or Engine.DEFAULT_MAX_TIME) then
        Engine.rest(task, Engine.STUCK_PAUSE, "took too long")
        current = nil
        return false
    end
    -- Only the task's own status counts: a stack event in between is not
    -- the task being stuck.
    if mode and Farm.current() == mode then
        local status = tostring(mode.status)
        if status ~= lastStatus then
            lastStatus, statusSince = status, t
        elseif t - statusSince >= Engine.STUCK_LIMIT then
            Engine.rest(task, Engine.STUCK_PAUSE, "stuck on \"" .. status .. "\"")
            current = nil
            return false
        end
    else
        statusSince = t
    end
    return true
end

---------------------------------------------------------------------------
-- Late game hops and purchases
---------------------------------------------------------------------------

-- A reason to change server, or nil (Teddy's Swan Door / haki colour /
-- Mirror Fractal / Valkyrie Helm hops).
function Engine.lateHop(sea, level)
    if sea == 2 and level >= Engine.SEA_LEVEL[3] and StackWorld.needsTrevorFruit() then
        -- A fruit worth 1M on sale is bought (purchases) once the level farm
        -- has made the money; only when none is on sale at all may a fruit on
        -- the ground of another server do.
        local _, price = StackWorld.cheapestTrevorFruit()
        if not price then return "Swan door: no fruit worth 1M on sale" end
    end
    -- Hopping instead of levelling would slow everything else down: the
    -- late game hops wait for the max level, as in Teddy.
    if sea ~= 3 or level < Engine.MAX_LEVEL then return nil end
    if Engine.needsColours(level) and (Player.data("Fragments") or 0) >= Engine.COLOUR_FRAGMENTS
        and not Engine.dealerColour() then
        return "haki colour dealer"
    end
    local plan, goal = Engine.chalicePlan(level)
    if not plan then return nil end
    if Common.has("God's Chalice") or Common.has("Sweet Chalice") or EliteHunter.find() then return nil end
    if plan == "dough" then
        if Common.itemCount("Conjured Cocoa") < Engine.COCOA or Enemies.findBoss("Dough King") then return nil end
        return goal .. ": no elite for a chalice"
    end
    if Enemies.findBoss("rip_indra True Form") then return nil end
    return goal .. ": no elite for a chalice"
end

-- Purchases that unblock a step: Trevor's fruit, a legendary haki colour.
-- The haki abilities (Teddy's Items.Abilities), bought from anywhere when
-- the character does not carry their tag yet. Geppo and Buso at once (cheap,
-- Buso makes Auto Buso work); Soru and Ken once Electric is owned or Sea 2
-- is reached, as Teddy keeps the money for the styles first.
Engine.ABILITIES = {
    { name = "Geppo", call = { "BuyHaki", "Geppo" }, beli = 10000 },
    { name = "Buso", call = { "BuyHaki", "Buso" }, beli = 25000 },
    { name = "Soru", call = { "BuyHaki", "Soru" }, beli = 100000, late = true },
    { name = "Ken", call = { "KenTalk", "Buy" }, beli = 150000, late = true },
}

local function hasAbility(name)
    local character = Player.character()
    if not character then return true end
    local ok, tagged = pcall(function()
        return Services.get("CollectionService"):HasTag(character, name)
    end)
    return not ok or tagged == true
end

function Engine.nextAbility(sea)
    local beli = Player.data("Beli") or 0
    local late = sea >= 2 or Melee.owned("Electro")
    for _, ability in ipairs(Engine.ABILITIES) do
        if (late or not ability.late) and beli >= ability.beli and not hasAbility(ability.name) then
            return ability
        end
    end
    return nil
end

local function purchases(sea, level)
    local t = now()
    if t - lastBuy < Engine.BUY_EVERY then return end
    if sea == 2 and level >= Engine.SEA_LEVEL[3] and StackWorld.needsTrevorFruit() then
        local fruit, price = StackWorld.cheapestTrevorFruit()
        if fruit and (Player.data("Beli") or 0) >= price then
            lastBuy = t
            Fruits.keep(fruit, 120)
            Services.invoke("PurchaseRawFruit", fruit)
            Common.forget()
            note("bought " .. fruit .. " for Trevor")
        end
        return
    end
    if sea >= 2 and Engine.needsColours(level) then
        local colour = Engine.dealerColour()
        if colour and (Player.data("Fragments") or 0) >= Engine.COLOUR_FRAGMENTS then
            lastBuy = t
            Services.invoke("ColorsDealer", "2")
            Common.forget()
            note("bought the haki colour " .. colour)
        end
    end
    -- Abilities last: Trevor's fruit and a haki colour unblock more.
    local ability = Engine.nextAbility(sea)
    if ability and Common.every("Ability" .. ability.name, 30) then
        lastBuy = t
        Services.invoke((table.unpack or unpack)(ability.call))
        note("bought " .. ability.name)
    end
end

local function hopFor(reason, after)
    hopNote = reason
    if not reason then
        hopReason, hopSince = nil, nil
        return
    end
    local t = now()
    if reason ~= hopReason then hopReason, hopSince = reason, t end
    if t - hopSince >= (after or Engine.HOP_AFTER) and Common.hop(reason, true) then
        note("hop: " .. reason)
        hopSince = t
    end
end

---------------------------------------------------------------------------
-- Sea
---------------------------------------------------------------------------

-- The sea the level belongs to. Travelling there is harmless while it is
-- still locked (the server ignores it); the stack quests unlock it.
function Engine.wantedSea(level)
    if level >= Engine.SEA_LEVEL[3] then return 3 end
    if level >= Engine.SEA_LEVEL[2] then return 2 end
    return 1
end

local function travel(sea, level, task)
    local target = Engine.wantedSea(level)
    if sea >= target or Engine.anchored(sea, task) then return end
    local t = now()
    if t - lastTravel < Engine.TRAVEL_EVERY then return end
    lastTravel = t
    local action = Data.TRAVEL[target]
    if action then pcall(Services.invoke, action) end
end

---------------------------------------------------------------------------

function Engine.tick()
    if not Player.alive() then return end
    local sea, level = Player.sea() or 1, Player.level() or 1
    local wanted, task, name = Engine.desired(sea, level)
    idleName = name
    Engine.apply(wanted)
    local working = watch(task)
    currentWorking = working
    pcall(purchases, sea, level)

    local reason, after = taskHop, taskHopAfter
    if not reason and not working and Config.get("Hop") == true and Farm.current() ~= StackFarm then
        local ok, late = pcall(Engine.lateHop, sea, level)
        reason = ok and late or nil
    end
    hopFor(reason, after)
    travel(sea, level, task)
    pcall(Engine.plan)
end

function Engine.start()
    -- The travel events (entrances, doors, resets) on the screen's Last row.
    pcall(function()
        require("Game.Router").listener = function(text) note("travel: " .. text) end
    end)
    -- Skip = { X = true } turns a task OFF: say it up front, it is easy to
    -- read the other way round.
    local skipped = {}
    for key, value in pairs(Config.get("Skip") or {}) do
        if value == true then skipped[#skipped + 1] = key end
    end
    table.sort(skipped)
    if #skipped > 0 then
        note("your config turns OFF: " .. table.concat(skipped, ", ") .. " (Skip = true means skip)")
    end
    Loop.start("Kaitun", Engine.EVERY, Engine.tick)
end

-- Back to defaults for every key the Kaitun set.
function Engine.stop()
    Loop.stop("Kaitun")
    for key in pairs(applied) do pcall(Settings.set, key, Settings.DEFAULTS[key]) end
    applied = {}
end

function Engine.status()
    local resting = {}
    for name, entry in pairs(rest) do
        local left = entry.untilAt - now()
        if left > 0 then resting[#resting + 1] = string.format("%s %ds", name, math.floor(left)) end
    end
    table.sort(resting)
    return {
        task = current and current.name or nil,
        idle = idleName,
        hop = hopNote,
        log = log,
        resting = resting,
        plan = planCache.list,
    }
end

-- Why each task of this sea is or is not running, for the screen:
-- { "Electric: done", "Saber: next", ... } (the "other sea" ones left out).
-- Computed by the engine loop (Engine.tick); the screen only reads the
-- result, so nothing slow ever runs in the screen's loop.
function Engine.plan()
    if now() - planCache.at < 5 then return planCache.list end
    local list = {}
    local sea, level = Player.sea() or 1, Player.level() or 1
    for _, task in ipairs(Tasks.ordered()) do
        local ok, why = pcall(Engine.blocked, task, sea, level)
        if not ok then why = "error" end
        if why ~= "other sea" then
            -- "done" says who said so, to catch a false "owned".
            if why == "skipped" then
                local key = Config.skipped(task.name) and task.name or task.group
                why = "skipped by your config (Skip." .. tostring(key) .. " = true)"
            end
            if why == "done" and task.doneBy then
                local okBy, by = pcall(task.doneBy)
                if okBy and by then why = "done, " .. tostring(by) end
            end
            -- "not ready" says why, when the task can tell.
            if why == "not ready" and task.why then
                local okWhy, detail = pcall(task.why)
                if okWhy and detail then why = "not ready (" .. tostring(detail) .. ")" end
            end
            list[#list + 1] = task.name .. ": " .. (task == current and "running" or why or "ready")
        end
    end
    planCache = { at = now(), list = list }
    return list
end

-- Test hook.
function Engine.reset()
    current, startedAt, idleSince, lastStatus, statusSince = nil, nil, nil, nil, nil
    currentWorking = false
    planCache = { at = -math.huge, list = {} }
    rest, doneCache, applied, log = {}, {}, {}, {}
    lastTravel, lastBuy = -math.huge, -math.huge
    idleName = "Idle"
    taskHop, taskHopAfter, hopReason, hopSince, hopNote = nil, nil, nil, nil, nil
end

return Engine
