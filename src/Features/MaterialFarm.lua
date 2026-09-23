--=============================================================================
-- MATERIAL FARM — kills the mobs that drop the chosen material
--=============================================================================
--  If the material's mobs live in another sea, the player is sent there with
--  the sea's CommF_ travel action (retried every few seconds until the
--  teleport happens).
--=============================================================================

local Data = require("Game.Data")
local MobFarm = require("Features.MobFarm")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local TRAVEL_RETRY = 15
local lastTravel = -math.huge

local function material()
    return Data.MATERIALS[Settings.get("Material")]
end

return MobFarm({
    name = "Material Farm",
    key = "AutoMaterial",
    idle = "Choose a material",
    mobs = function()
        local entry = material()
        return entry and entry.mobs
    end,
    before = function(mode)
        local entry = material()
        if not entry or Player.sea() == entry.sea then return false end
        mode.target = nil
        Movement.stop()
        mode.status = "Travelling to Sea " .. entry.sea .. " for " .. Settings.get("Material")
        local now = os.clock()
        if now - lastTravel >= TRAVEL_RETRY then
            lastTravel = now
            Services.invoke(Data.TRAVEL[entry.sea])
        end
        return true
    end,
})
