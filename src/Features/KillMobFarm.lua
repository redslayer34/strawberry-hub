--=============================================================================
-- KILL MOB FARM — farms one mob chosen in the dropdown
--=============================================================================

local MobFarm = require("Features.MobFarm")
local Settings = require("Core.Settings")

return MobFarm({
    name = "Kill Mob",
    key = "AutoKillMob",
    idle = "Choose a mob",
    mobs = function()
        local mob = Settings.get("Mob")
        if mob == nil or mob == "" then return nil end
        return { mob }
    end,
})
