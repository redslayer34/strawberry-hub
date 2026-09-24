--=============================================================================
-- TYRANT FARM — Sea 3, Tiki Outpost, up to the Tyrant of the Skies
--=============================================================================
--  The reference's "Farm Tyrant of the Skies": the island's mobs; once the
--  four eyes of the island are lit, the trees of the eagle arena are broken
--  with skills, which brings the Tyrant of the Skies; he is fought first
--  whenever he is alive.
--=============================================================================

local Common = require("Features.Stack.Common")
local Data = require("Game.Data")
local Enemies = require("Game.Enemies")
local Mastery = require("Game.Mastery")
local MobFarm = require("Features.MobFarm")
local Services = require("Core.Services")

local function island()
    return Services.find(workspace, "Map.TikiOutpost.IslandModel")
end

local TyrantFarm

-- All four eyes of the island are lit.
local function eyesLit(model)
    for index = 1, 4 do
        local eye = model:FindFirstChild("Eye" .. index, true)
        if not eye or eye.Transparency ~= 0 then return false end
    end
    return true
end

local function arenaTree(model)
    local arena = model:FindFirstChild("EagleBossArena", true)
    for _, child in ipairs(arena and arena:GetChildren() or {}) do
        if child.Name == "Tree" and not child:GetAttribute("AlreadyDestroyedClient") then return child end
    end
    return nil
end

TyrantFarm = MobFarm({
    name = "Tyrant Farm",
    key = "AutoTyrant",
    sea = 3,
    mobs = function() return Data.TYRANT_MOBS end,
    quest = { name = "TikiQuest3", id = 2, level = 2575 },
    before = function(mode)
        local boss, inWorld = Enemies.findBoss(Data.TYRANT)
        if boss then
            mode.status = Common.fight(mode, boss, inWorld)
            return true
        end
        local model = island()
        if not model or not eyesLit(model) then return false end
        local tree = arenaTree(model)
        local pivot = tree and Common.pivot(tree)
        if not pivot then return false end
        mode.target = nil
        Common.goTo(pivot)
        if Common.near(pivot, 10) then Mastery.fireAt(pivot) end
        mode.status = "Breaking the arena trees"
        return true
    end,
})

return TyrantFarm
