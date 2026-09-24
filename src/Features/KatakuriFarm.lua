--=============================================================================
-- KATAKURI FARM — Sea 3, Cake Land mobs, then Cake Prince / Dough King
--=============================================================================
--  Killing the Cake Land mobs makes Cake Prince spawn. When he (or Dough
--  King) is alive he takes priority, unless IgnoreKatakuri is on. With
--  HopKatakuri, a server without him is left for another one.
--=============================================================================

local Common = require("Features.Stack.Common")
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
    quest = { name = "CakeQuest2", id = 2, level = 2275 },
    before = function(mode)
        if Settings.get("IgnoreKatakuri") then return false end
        local boss = Enemies.nearest(Data.CAKE_BOSSES)
        if not boss then
            if Settings.get("HopKatakuri") then Common.hop("no Cake Prince") end
            return false
        end
        mode.status = Fight.status(boss, Fight.engage(mode, boss), " (boss)")
        return true
    end,
})
