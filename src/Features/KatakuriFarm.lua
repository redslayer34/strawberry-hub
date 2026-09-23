--=============================================================================
-- KATAKURI FARM — Sea 3, Cake Land mobs, then Cake Prince / Dough King
--=============================================================================
--  Killing the Cake Land mobs makes Cake Prince spawn. When he (or Dough
--  King) is alive he takes priority, unless IgnoreKatakuri is on.
--=============================================================================

local Data = require("Game.Data")
local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local MobFarm = require("Features.MobFarm")
local Settings = require("Core.Settings")

return MobFarm({
    name = "Katakuri Farm",
    key = "AutoKatakuri",
    sea = 3,
    mobs = function() return Data.CAKE_MOBS end,
    before = function(mode)
        if Settings.get("IgnoreKatakuri") then return false end
        local boss = Enemies.nearest(Data.CAKE_BOSSES)
        if not boss then return false end
        mode.status = Fight.status(boss, Fight.engage(mode, boss), " (boss)")
        return true
    end,
})
