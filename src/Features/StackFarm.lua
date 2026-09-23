--=============================================================================
-- STACK FARM — events that interrupt the main farm
--=============================================================================
--  Every frame the tasks below are asked, in the reference's order, whether
--  they have something to do (a boss alive, an item to use, an event on).
--  The first one that does takes the character; when none does this mode is
--  disabled and the main farm (Level, Bones, Katakuri...) carries on.
--
--  Tasks may also ask for a server hop when what they wait for is not on
--  this server (Darkbeard, Dough King, an Elite Hunter, a fruit). Hops only
--  happen while no task is busy, and are paced by Stack/Common.
--
--  A task is a table with: name, enabled(), want(), tick(mode) -> status,
--  and optionally hop() -> reason or nil.
--=============================================================================

local Bosses = require("Features.Stack.Bosses")
local Chests = require("Features.Stack.Chests")
local Common = require("Features.Stack.Common")
local EliteHunter = require("Features.Stack.EliteHunter")
local Events = require("Features.Stack.Events")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Summons = require("Features.Stack.Summons")
local World = require("Features.Stack.World")

local StackFarm = { name = "Stack", status = "Idle", target = nil }

StackFarm.TASKS = {
    World.newWorld,
    Chests,
    World.thirdWorld,
    Bosses.darkbeard,
    Bosses.ripIndra,
    Summons,
    Bosses.soulReaper,
    Bosses.doughKing,
    EliteHunter,
    Events.factory,
    Events.raid,
    Events.fruit,
}

local chosen, running
StackFarm.hopNote = nil

local function pick()
    for _, task in ipairs(StackFarm.TASKS) do
        if task.enabled() then
            local ok, wanted = pcall(task.want)
            if ok and wanted then return task end
        end
    end
    return nil
end

-- No task busy: the hop reasons of the enabled tasks.
local function hops()
    local active, first = {}, nil
    for _, task in ipairs(StackFarm.TASKS) do
        if task.hop and task.enabled() then
            local ok, reason = pcall(task.hop)
            if ok and reason then
                active[reason] = true
                first = first or reason
            end
        end
    end
    Common.keepHopReasons(active)
    StackFarm.hopNote = first and ("hop soon: " .. first) or nil
    if first and Common.hop(first) then StackFarm.hopNote = "hopping: " .. first end
end

function StackFarm.enabled()
    if not Player.alive() then
        chosen = nil
        return false
    end
    chosen = pick()
    if not chosen then hops() end
    return chosen ~= nil
end

function StackFarm.tick()
    local task = chosen
    if not task then return end
    if task ~= running then
        running = task
        StackFarm.target = nil
    end
    local ok, status = pcall(task.tick, StackFarm)
    if not ok then
        StackFarm.target = nil
        Movement.stop()
        status = "error: " .. tostring(status)
    end
    StackFarm.status = task.name .. ": " .. tostring(status)
end

function StackFarm.stop()
    chosen, running = nil, nil
    StackFarm.target = nil
    StackFarm.status = "Idle"
end

-- For the Stack tab.
function StackFarm.current()
    return running and running.name or nil
end

-- Test hook.
function StackFarm.reset()
    StackFarm.stop()
    StackFarm.hopNote = nil
    Common.reset()
    Chests.reset()
    EliteHunter.reset()
    Summons.reset()
    Bosses.reset()
    Events.reset()
    World.reset()
end

return StackFarm
