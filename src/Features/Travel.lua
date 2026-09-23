--=============================================================================
-- TRAVEL — flies to a chosen place, pausing the farm on the way
--=============================================================================
--  Registered first in Farm.MODES and enabled only while a destination is
--  pending: a teleport takes the character from whatever farm is running,
--  and hands it back as soon as it has arrived. On arrival an optional
--  callback runs once (buying from the NPC stood next to, for instance).
--=============================================================================

local Movement = require("Game.Movement")
local Player = require("Core.Player")

local Travel = { name = "Travel", status = "Idle", target = nil }

Travel.ARRIVED = 8

local pending

-- `where` is a Vector3 or a function returning one (NPCs move and stream).
function Travel.go(label, where, onArrive)
    pending = { label = label, where = where, onArrive = onArrive }
end

function Travel.cancel()
    if pending then Movement.stop() end
    pending = nil
end

function Travel.pending()
    return pending
end

function Travel.enabled()
    return pending ~= nil
end

function Travel.tick()
    local trip = pending
    if not trip then return end
    if not Player.alive() then
        Travel.status = "Waiting for respawn"
        return
    end

    local position = trip.where
    if type(position) == "function" then position = position() end
    if not position then
        Travel.status = trip.label .. " is not loaded (move closer to it)"
        pending = nil
        Movement.stop()
        return
    end

    local distance = Player.distanceTo(position)
    Movement.to(CFrame.new(position) * CFrame.new(0, 4, 2))
    Travel.status = string.format("Travelling to %s (%d studs)", trip.label, math.floor(distance))

    if distance <= Travel.ARRIVED then
        pending = nil
        Travel.status = "Arrived at " .. trip.label
        Movement.stop()
        if trip.onArrive then
            local ok, err = pcall(trip.onArrive)
            if not ok then warn("[Strawberry Hub] " .. trip.label .. ": " .. tostring(err)) end
        end
    end
end

function Travel.stop()
    Travel.status = "Idle"
end

return Travel
