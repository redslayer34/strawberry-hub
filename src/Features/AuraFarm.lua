--=============================================================================
-- AURA FARM — kills whatever comes within range, without travelling
--=============================================================================

local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Settings = require("Core.Settings")

local AuraFarm = { name = "Aura Farm", status = "Idle", target = nil }

function AuraFarm.enabled()
    return Settings.get("AutoAura") == true
end

function AuraFarm.tick()
    AuraFarm.target = nil
    if not Player.alive() then
        AuraFarm.status = "Waiting for respawn"
        return
    end

    local radius = Settings.get("AuraRadius")
    local mob = Enemies.nearestWithin(radius)
    if not mob then
        AuraFarm.status = "No mob within " .. radius .. " studs"
        Movement.stop()
        return
    end
    AuraFarm.status = Fight.status(mob, Fight.engage(AuraFarm, mob))
end

function AuraFarm.stop()
    AuraFarm.target = nil
    AuraFarm.status = "Idle"
end

return AuraFarm
