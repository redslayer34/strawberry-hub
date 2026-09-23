--=============================================================================
-- STATS — spends stat points on the chosen stats
--=============================================================================
--  Available points are split evenly over the selected stats that are still
--  under the cap, then sent with CommF_ AddPoint.
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
    for _, step in ipairs(Stats.plan(points, levels(), Settings.get("StatTargets") or {})) do
        Services.invoke("AddPoint", step.stat, step.points)
    end
end

function Stats.start()
    Loop.start("AutoStats", 1, Stats.tick)
end

return Stats
