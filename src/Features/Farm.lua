--=============================================================================
-- FARM — runs exactly one farm mode at a time
--=============================================================================
--  Every mode moves the character, so two running together would fight over
--  it. The first enabled mode in MODES (priority order) is the only one that
--  ticks; when none is enabled the character is handed back to the player.
--
--  A mode is a table with: name, status, target, enabled(), tick(), stop().
--=============================================================================

local Combat = require("Game.Combat")
local Loop = require("Core.Loop")
local Mastery = require("Game.Mastery")
local Movement = require("Game.Movement")
local Router = require("Game.Router")
local Settings = require("Core.Settings")

local Farm = {}

-- Priority order: the first enabled mode is the one that runs.
Farm.MODES = {
    require("Features.Travel"),
    require("Features.BossFarm"),
    require("Features.KatakuriFarm"),
    require("Features.BoneFarm"),
    require("Features.MaterialFarm"),
    require("Features.KillMobFarm"),
    require("Features.AuraFarm"),
    require("Features.LevelFarm"),
}

local current

function Farm.current()
    return current
end

function Farm.tick()
    local chosen
    for _, mode in ipairs(Farm.MODES) do
        if mode.enabled() then
            chosen = mode
            break
        end
    end

    if chosen ~= current then
        if current then current.stop() end
        current = chosen
        Mastery.reset()
        if not chosen then Movement.stop() end
    end

    if chosen then chosen.tick() end
end

function Farm.target()
    return current and current.target or nil
end

function Farm.status()
    if not current then return "Idle" end
    local text = current.name .. ": " .. tostring(current.status)
    local via = Router.note()
    if via then text = text .. " -- " .. via end
    return text
end

-- The farm decides where to be every frame; the attack loop hits whatever
-- the active mode is fighting, as fast as the AttackDelay setting allows.
function Farm.start()
    Loop.start("Farm", 0, Farm.tick)
    Loop.start("Attack", function() return Settings.get("AttackDelay") end, function()
        local target = Farm.target()
        if target then Combat.strike(target) end
    end)
end

function Farm.stop()
    Loop.stop("Farm")
    Loop.stop("Attack")
    if current then current.stop() end
    current = nil
    Mastery.reset()
    Movement.stop()
end

return Farm
