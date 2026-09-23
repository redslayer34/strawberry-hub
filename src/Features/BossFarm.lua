--=============================================================================
-- BOSS FARM — kills the chosen boss (or any boss) once it has spawned
--=============================================================================

local Data = require("Game.Data")
local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Settings = require("Core.Settings")

local BossFarm = { name = "Boss Farm", status = "Idle", target = nil }

function BossFarm.enabled()
    return Settings.get("AutoBoss") == true
end

local function wanted()
    if Settings.get("AllBosses") then return Data.BOSSES end
    local boss = Settings.get("Boss")
    if boss == nil or boss == "" then return nil end
    return { boss }
end

function BossFarm.tick()
    BossFarm.target = nil
    if not Player.alive() then
        BossFarm.status = "Waiting for respawn"
        return
    end

    local names = wanted()
    if not names then
        BossFarm.status = "Choose a boss"
        Movement.stop()
        return
    end

    local boss, inWorld = Enemies.findBoss(names)
    if not boss then
        BossFarm.status = "Not spawned: " .. (Settings.get("AllBosses") and "any boss" or names[1])
        Movement.stop()
        return
    end

    if not inWorld then
        -- Parked out of streaming range: flying there loads it.
        Movement.to(boss.HumanoidRootPart.CFrame * CFrame.new(0, Fight.SPAWN_HEIGHT, 0))
        BossFarm.status = "Going to " .. boss.Name
        return
    end

    BossFarm.status = Fight.status(boss, Fight.engage(BossFarm, boss))
end

function BossFarm.stop()
    BossFarm.target = nil
    BossFarm.status = "Idle"
end

return BossFarm
