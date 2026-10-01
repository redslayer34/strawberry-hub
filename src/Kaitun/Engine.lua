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
--    idle        Teddy's fn22: level farm until the max level, then
--                Katakuri in Sea 3
--
--  Watchdog, so one job can never hold the Kaitun forever:
--    its mode says "nothing to do" for IDLE_LIMIT s   -> rests IDLE_PAUSE s
--    the same status for STUCK_LIMIT s, or maxTime    -> rests STUCK_PAUSE s
--=============================================================================

local Config = require("Kaitun.Config")
local Data = require("Game.Data")
local Farm = require("Features.Farm")
local Loop = require("Core.Loop")
local Melee = require("Features.Items.Melee")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local Tasks = require("Kaitun.Tasks")

local Engine = {}

Engine.EVERY = 1
Engine.MAX_LEVEL = 2800
Engine.IDLE_LIMIT = 30
Engine.IDLE_PAUSE = 300
Engine.STUCK_LIMIT = 300
Engine.STUCK_PAUSE = 600
Engine.DEFAULT_MAX_TIME = 1800
Engine.DONE_CACHE = 15
Engine.TRAVEL_EVERY = 60
Engine.LOG_SIZE = 10
Engine.SEA_LEVEL = { [2] = 700, [3] = 1500 }

local current, startedAt
local idleSince, lastStatus, statusSince
local rest = {}        -- [task name] = { untilAt, why }
local doneCache = {}   -- [task name] = { done, at }
local applied = {}     -- keys the Kaitun has set
local log = {}
local lastTravel = -math.huge
local idleName = "Idle"

local function now() return os.clock() end

local function note(text)
    table.insert(log, 1, string.format("[%s] %s", os.date and os.date("%H:%M") or "--:--", text))
    while #log > Engine.LOG_SIZE do table.remove(log) end
end

---------------------------------------------------------------------------
-- Layers
---------------------------------------------------------------------------

-- Helpers and the stack events of the current sea.
function Engine.background(sea, level)
    local keys = {
        AutoStats = true,
        StatTargets = Config.get("Stats"),
        FruitStore = Config.get("StoreFruits") == true,
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
    local url = Config.get("WebhookUrl")
    if type(url) == "string" and url ~= "" then
        keys.WebhookUrl = url
        keys.WebhookProfile = true
        keys.WebhookStoreFruit = true
    end
    if sea == 1 then
        keys.StackNewWorld = level >= Engine.SEA_LEVEL[2]
    elseif sea == 2 then
        keys.StackThirdWorld = level >= Engine.SEA_LEVEL[3]
        keys.StackFactory = true
        keys.StackDarkbeard = true
        keys.StackSummonDarkbeard = true
    elseif sea == 3 then
        keys.StackEliteHunter = true
        keys.StackPirateRaid = true
        keys.StackRipIndra = true
        keys.StackSummonRipIndra = true
        keys.StackHakiPads = true
        keys.StackSoulReaper = true
        keys.StackSummonSoulReaper = true
        keys.StackDoughKing = true
        keys.StackSummonDoughKing = true
    end
    return keys
end

-- Teddy's fn22: levels first, then in Sea 3 bones while Dragon Talon is
-- locked (its Fire Essence comes from the bone gacha), then Katakuri. The
-- idle mode stays
-- on under the task (it is last in Farm.MODES), so a task with nothing to
-- do falls back to it at once.
function Engine.idle(sea, level)
    local keys = { Weapon = Engine.weapon() }
    if level < Engine.MAX_LEVEL or sea ~= 3 then
        keys.AutoFarmLevel = true
        return keys, "Level farm"
    end
    if not Config.skipped("Godhuman") and not Melee.unlocked("Dragon Talon") then
        keys.AutoBone = true
        return keys, "Bones (Fire Essence)"
    end
    keys.AutoKatakuri = true
    return keys, "Katakuri"
end

-- The weapon for the farms (the melee manager takes over in batch 2).
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
    if resting and now() < resting.untilAt then return "resting" end
    if Engine.isDone(task) then return "done" end
    if task.ready then
        local ok, ready = pcall(task.ready)
        if not (ok and ready) then return "not ready" end
    end
    return nil
end

function Engine.pick(sea, level, list)
    for _, task in ipairs(Tasks.ordered(list)) do
        if not Engine.blocked(task, sea, level) then return task end
    end
    return nil
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

function Engine.desired(sea, level, list)
    local wanted = Engine.background(sea, level)
    local idleKeys, name = Engine.idle(sea, level)
    for key, value in pairs(idleKeys) do wanted[key] = value end
    local task = Engine.pick(sea, level, list)
    if task then
        for key, value in pairs(Tasks.keysOf(task)) do wanted[key] = value end
    end
    -- Keys that only one layer sets go back to off when that layer stops.
    for _, key in ipairs({ "StackNewWorld", "StackThirdWorld", "StackFactory", "StackDarkbeard",
        "StackSummonDarkbeard", "StackEliteHunter", "StackPirateRaid", "StackRipIndra",
        "StackSummonRipIndra", "StackHakiPads", "StackSoulReaper", "StackSummonSoulReaper",
        "StackDoughKing", "StackSummonDoughKing", "AutoFarmLevel", "AutoKatakuri", "AutoBone" }) do
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
    rest[task.name] = { untilAt = now() + seconds, why = why }
    note(task.name .. " rests " .. math.floor(seconds / 60) .. " min: " .. why)
end

local function watch(task)
    local t = now()
    if task ~= current then
        if current then note("done with " .. current.name) end
        current, startedAt, idleSince, lastStatus, statusSince = task, t, nil, nil, t
        if task then note("task: " .. task.name) end
    end
    if not task then return end

    local mode = task.mode
    if mode then
        local ok, enabled = pcall(mode.enabled)
        if not (ok and enabled) then
            idleSince = idleSince or t
            if t - idleSince >= Engine.IDLE_LIMIT then
                Engine.rest(task, Engine.IDLE_PAUSE, "nothing to do (" .. tostring(mode.status) .. ")")
                current = nil
            end
            return
        end
        idleSince = nil
    end

    if t - startedAt >= (task.maxTime or Engine.DEFAULT_MAX_TIME) then
        Engine.rest(task, Engine.STUCK_PAUSE, "took too long")
        current = nil
        return
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
        end
    else
        statusSince = t
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
    if sea >= target or (task and inSea(task, sea)) then return end
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
    watch(task)
    travel(sea, level, task)
end

function Engine.start()
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
        log = log,
        resting = resting,
    }
end

-- Test hook.
function Engine.reset()
    current, startedAt, idleSince, lastStatus, statusSince = nil, nil, nil, nil, nil
    rest, doneCache, applied, log = {}, {}, {}, {}
    lastTravel = -math.huge
    idleName = "Idle"
end

return Engine
