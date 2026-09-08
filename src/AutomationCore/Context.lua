--=============================================================================
-- CONTEXT — surface de contact entre l'AutomationCore et le runtime
--=============================================================================
--  L'AutomationCore ne connait pas le monolithe historique. Il ne connait que
--  ce contexte : une poignee de primitives injectees a la construction.
--
--  Deux consequences voulues :
--    * chaque module se teste en lui passant un contexte simule ;
--    * remplacer le moteur de deplacement ou de combat ne touche a aucun
--      module de perception, de decision ou de recuperation.
--
--  C'est aussi ce qui rend QuestFarm et CDK reellement separables : ils
--  dependent du contexte, pas l'un de l'autre.
--=============================================================================

local Config = require("AutomationCore.Config")
local DynamicMapCache = require("AutomationCore.DynamicMapCache")
local Log = require("AutomationCore.Log")

local Context = {}
Context.__index = Context

-- internal : la table StrawberryHub.Internal exposee par le runtime.
function Context.new(internal)
    assert(type(internal) == "table", "contexte : primitives runtime manquantes")

    local legacyConfig = internal.Config
    local Core = internal.Core
    local Move = internal.Move
    local Attack = internal.Attack
    local Remote = internal.Remote
    local player = internal.Player

    local self = setmetatable({
        cfg = Config,
        legacy = internal,
        legacyConfig = legacyConfig,
        map = DynamicMapCache.new(),
        log = Log,

        -- Etat partage, ecrit par la perception, lu par tout le reste.
        quest = nil,
        sea = nil,
        island = nil,
        region = nil,
        targets = {},

        stats = { ticks = 0, scans = 0, recoveries = 0, kills = 0 },
    }, Context)

    ---------------------------------------------------------------------------
    -- Joueur
    ---------------------------------------------------------------------------
    self.player = {
        instance = player,
        character = function() return Core.character() end,
        hrp = function() return Core.hrp() end,
        humanoid = function() return Core.humanoid() end,
        alive = function() return Core.alive() end,
        level = function() return Core.level() end,

        position = function()
            local hrp = Core.hrp()
            return hrp and hrp.Position or nil
        end,

        -- Valeur brute d'un champ de LocalPlayer.Data (Level, Beli, Fragments...).
        data = function(field)
            local data = player and player:FindFirstChild("Data")
            local entry = data and data:FindFirstChild(field)
            return entry and entry.Value or nil
        end,
    }

    ---------------------------------------------------------------------------
    -- Monde — aucun chemin code en dur au-dela de ces accesseurs
    ---------------------------------------------------------------------------
    self.world = {
        enemies = function() return workspace:FindFirstChild("Enemies") end,
        npcs = function() return workspace:FindFirstChild("NPCs") end,

        -- Le jeu publie lui-meme la position des iles ici. C'est la source
        -- dynamique qui remplace les tables de CFrame : quand une ile bouge,
        -- cette table bouge avec elle.
        locations = function()
            local origin = workspace:FindFirstChild("_WorldOrigin")
            return origin and origin:FindFirstChild("Locations")
        end,

        questFrame = function()
            local gui = player and player:FindFirstChild("PlayerGui")
            local main = gui and gui:FindFirstChild("Main")
            return main and main:FindFirstChild("Quest")
        end,

        placeId = function() return game.PlaceId end,
        jobId = function() return game.JobId end,
    }

    ---------------------------------------------------------------------------
    -- Actions
    ---------------------------------------------------------------------------
    self.move = {
        tweenTo = function(cf) return Move.tweenTo(cf) end,
        snapTo = function(cf) return Move.snapTo(cf) end,
        stop = function() return Move.stopTween() end,
        faceTarget = function(part, offset) return Move.faceTarget(part, offset) end,
    }

    self.attack = {
        strike = function(enemy) return Attack.strike(enemy) end,
        equip = function(selection) return Attack.equip(selection) end,
        release = function() return Attack.releaseHold() end,
        ready = function() return Attack.ready() end,
    }

    self.remote = {
        invoke = function(...) return Remote.invoke(...) end,
    }

    self.server = {
        hop = function(lowestOnly) return internal.Server.hop(lowestOnly) end,
        rejoin = function() return internal.Server.rejoin() end,
    }

    self.teleport = {
        toIsland = function(name) return internal.Teleport.toIsland(name) end,
        toSea = function(sea) return internal.Teleport.toSea(sea) end,
    }

    -- Le core est pilote par le flag AutoFarm du runtime : couper le farm
    -- dans l'UI doit arreter le core, sans qu'il ait a le savoir.
    self.flags = {
        farming = function() return internal.State.flags.AutoFarm == true end,
        get = function(name) return internal.State.flags[name] == true end,
    }

    return self
end

-- Position du joueur, ou nil. Raccourci tres utilise.
function Context:pos()
    return self.player.position()
end

function Context:distanceTo(target)
    local here = self:pos()
    if not here or not target then return math.huge end
    local there = typeof(target) == "Vector3" and target
        or (typeof(target) == "CFrame" and target.Position)
        or (target.Position)
    if not there then return math.huge end
    return (there - here).Magnitude
end

return Context
