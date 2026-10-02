--=============================================================================
-- STATS — spends stat points on the chosen stats
--=============================================================================
--  Two ways, sent with CommF_ AddPoint:
--
--    Teddy   the Teddy Kaitun's order, by level: everything into Melee
--            under 55; then Defense to 15 (100 from level 300) first, Melee
--            to the cap, Defense to the cap, and from level 400 Sword to 600
--            and Demon Fruit to 1950
--    Even    the points split evenly over the chosen stats under the cap
--=============================================================================

local Data = require("Game.Data")
local Loop = require("Core.Loop")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Stats = {}

-- Pure: points to add per stat. `levels` maps stat -> current level.
function Stats.plan(points, levels, targets)
    local open = {}
    for _, stat in ipairs(Data.STATS) do
        if targets[stat] and (levels[stat] or 0) < Data.STAT_MAX then open[#open + 1] = stat end
    end
    local plan = {}
    if points <= 0 or #open == 0 then return plan end

    local share = math.floor(points / #open)
    local extra = points - share * #open
    for index, stat in ipairs(open) do
        local amount = share + (index <= extra and 1 or 0)
        amount = math.min(amount, Data.STAT_MAX - (levels[stat] or 0))
        if amount > 0 then plan[#plan + 1] = { stat = stat, points = amount } end
    end
    return plan
end

-- Teddy's steps for `level`: { stat, target } in order.
function Stats.teddySteps(level)
    local max = Data.STAT_MAX
    if level < 55 then return { { "Melee", max } } end
    local defense = level < 300 and 15 or 100
    local steps = { { "Defense", defense }, { "Melee", max }, { "Defense", max } }
    if level >= 400 then
        steps[#steps + 1] = { "Sword", 600 }
        steps[#steps + 1] = { "Demon Fruit", 1950 }
    end
    return steps
end

-- Pure: Teddy's order, filling one step after the other with the points.
function Stats.teddyPlan(points, level, levels)
    local plan, left, given = {}, points, {}
    for _, step in ipairs(Stats.teddySteps(level or 1)) do
        if left <= 0 then break end
        local stat, target = step[1], math.min(step[2], Data.STAT_MAX)
        local now = (levels[stat] or 0) + (given[stat] or 0)
        local amount = math.min(left, target - now)
        if amount > 0 then
            plan[#plan + 1] = { stat = stat, points = amount }
            given[stat] = (given[stat] or 0) + amount
            left = left - amount
        end
    end
    return plan
end

local function levels()
    local player = Services.player()
    local stats = player and Services.find(player, "Data.Stats")
    local out = {}
    for _, stat in ipairs(Data.STATS) do
        local level = stats and Services.find(stats, stat .. ".Level")
        out[stat] = level and level.Value or 0
    end
    return out
end

function Stats.tick()
    if not Settings.get("AutoStats") then return end
    local points = Player.data("Points") or 0
    local plan
    if Settings.get("StatMode") == "Even" then
        plan = Stats.plan(points, levels(), Settings.get("StatTargets") or {})
    else
        plan = Stats.teddyPlan(points, Player.level() or 1, levels())
    end
    for _, step in ipairs(plan) do
        Services.invoke("AddPoint", step.stat, step.points)
    end
end

function Stats.start()
    Loop.start("AutoStats", 1, Stats.tick)
end

return Stats
