--=============================================================================
-- CONTEXT — the contact surface between the AutomationCore and the runtime
--=============================================================================
--  The AutomationCore knows nothing about the historical monolith. It knows
--  only this context: a handful of primitives injected at construction.
--
--  Two deliberate consequences:
--    * every module can be tested by handing it a simulated context;
--    * replacing the movement or combat engine touches no perception,
--      decision or recovery module.
--
--  This is also what makes QuestFarm and CDK genuinely separable: they depend
--  on the context, not on each other.
--=============================================================================

local Config = require("AutomationCore.Config")
local DynamicMapCache = require("AutomationCore.DynamicMapCache")
local Log = require("AutomationCore.Log")

local Context = {}
Context.__index = Context

-- internal : the StrawberryHub.Internal table exposed by the runtime.
function Context.new(internal)
    assert(type(internal) == "table", "context: runtime primitives missing")

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

        -- Shared state, written by perception, read by everything else.
        quest = nil,
        sea = nil,
        island = nil,
        region = nil,
        targets = {},

        stats = { ticks = 0, scans = 0, recoveries = 0, kills = 0 },
    }, Context)

    ---------------------------------------------------------------------------
    -- Player
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

        -- Raw value of a LocalPlayer.Data field (Level, Beli, Fragments...).
        data = function(field)
            local data = player and player:FindFirstChild("Data")
            local entry = data and data:FindFirstChild(field)
            return entry and entry.Value or nil
        end,
    }

    ---------------------------------------------------------------------------
    -- World — no hardcoded paths beyond these accessors
    ---------------------------------------------------------------------------
    self.world = {
        enemies = function() return workspace:FindFirstChild("Enemies") end,
        npcs = function() return workspace:FindFirstChild("NPCs") end,

        -- The game publishes island positions here itself. This is the dynamic
        -- source that replaces coordinate tables: when an island moves, this
        -- table moves with it.
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

    -- The core is driven by the runtime's AutoFarm flag: switching the farm
    -- off in the interface must stop the core, without the core knowing.
    self.flags = {
        farming = function() return internal.State.flags.AutoFarm == true end,
        get = function(name) return internal.State.flags[name] == true end,
    }

    return self
end

-- Player position, or nil. Heavily used shorthand.
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
