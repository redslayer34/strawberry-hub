--=============================================================================
-- BONE FARM — Sea 3, Haunted Castle mobs (bones for the Death King)
--=============================================================================

local Data = require("Game.Data")
local MobFarm = require("Features.MobFarm")

return MobFarm({
    name = "Bone Farm",
    key = "AutoBone",
    sea = 3,
    mobs = function() return Data.BONE_MOBS end,
})
