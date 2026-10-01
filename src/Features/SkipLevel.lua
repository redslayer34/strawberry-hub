--=============================================================================
-- SKIP LEVEL — the Teddy Kaitun's "Jump Lv Farming" (Sea 1, under level 150)
--=============================================================================
--  No quest: mobs far above the player's level give far more experience
--  than the starter quests. Teddy's two steps:
--
--    level 1-30     Sky Bandits, on the lower Skylands
--    level 31-149   God's Guards (Lv. 450), on the upper Skylands
--
--  It sits just above the level farm in Farm.MODES: under 150 it takes its
--  place, at 150 it hands back to the normal quest route.
--=============================================================================

local Enemies = require("Game.Enemies")
local MobFarm = require("Features.MobFarm")
local Movement = require("Game.Movement")
local Player = require("Core.Player")

local SkipLevel = {}

SkipLevel.UNTIL = 150
SkipLevel.STEPS = {
    { upTo = 30, mob = "Sky Bandit", spot = Vector3.new(-5014.0341796875, 280.72146606445312, -972.079345703125) },
    { upTo = 149, mob = "God's Guard", spot = Vector3.new(-4227.2509765625, 1088, -567.60888671875) },
}
SkipLevel.FAR = 1000          -- studs from the spot: fly there first
SkipLevel.HEIGHT = 25         -- above the spot, as Teddy waits

-- The step for the current level, or nil (150 and up).
function SkipLevel.step(level)
    level = level or Player.level() or 1
    for _, step in ipairs(SkipLevel.STEPS) do
        if level <= step.upTo then return step end
    end
    return nil
end

local mode = MobFarm({
    name = "Skip Level",
    key = "AutoSkipLevel",
    sea = 1,
    idle = "Level 150 reached",
    mobs = function()
        local step = SkipLevel.step()
        return step and { step.mob } or nil
    end,
    -- Nothing loaded and far away: the mobs stream in around their island.
    before = function(farm)
        local step = SkipLevel.step()
        if not step or Enemies.nearest({ step.mob }) then return false end
        if Player.distanceTo(step.spot) <= SkipLevel.FAR then return false end
        farm.target = nil
        Movement.to(CFrame.new(step.spot + Vector3.new(0, SkipLevel.HEIGHT, 0)))
        farm.status = "Going to the " .. step.mob .. "s"
        return true
    end,
})

local enabled = mode.enabled
function mode.enabled()
    return enabled() and Player.sea() == 1 and (Player.level() or 0) < SkipLevel.UNTIL
end

SkipLevel.mode = mode

-- Used by the Kaitun's panel.
function SkipLevel.describe()
    local step = SkipLevel.step()
    return step and ("Skip level (" .. step.mob .. ")") or nil
end


return SkipLevel
