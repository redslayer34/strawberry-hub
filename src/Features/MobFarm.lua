--=============================================================================
-- MOB FARM — builds a farm mode that kills a list of mobs
--=============================================================================
--  Most modes are the same loop with a different mob list: fight the nearest
--  wanted mob, otherwise tour their spawn points. A spec only says what
--  differs:
--
--    name        shown in the status
--    key         the setting that enables the mode
--    sea         optional: the sea the mobs live in
--    mobs()      the mob names to farm (nil or empty: nothing to do)
--    before(m)   optional: runs first each tick; return true if it acted
--    idle        optional: status when the list is empty
--=============================================================================

local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Settings = require("Core.Settings")

return function(spec)
    local mode = { name = spec.name, status = "Idle", target = nil }
    local search = Fight.newSearch()

    function mode.enabled()
        return Settings.get(spec.key) == true
    end

    function mode.tick()
        if not Player.alive() then
            mode.target = nil
            mode.status = "Waiting for respawn"
            return
        end

        if spec.sea and Player.sea() ~= spec.sea then
            mode.target = nil
            mode.status = "Only in Sea " .. spec.sea
            Movement.stop()
            return
        end

        if spec.before and spec.before(mode) then return end

        local names = spec.mobs()
        if not names or #names == 0 then
            mode.target = nil
            mode.status = spec.idle or "Nothing selected"
            Movement.stop()
            return
        end

        local mob = Enemies.nearest(names)
        if mob then
            mode.status = Fight.status(mob, Fight.engage(mode, mob))
            return
        end

        if search:run(mode, names) then
            mode.status = "Looking for " .. table.concat(names, ", ")
        else
            mode.status = "Waiting for " .. table.concat(names, ", ") .. " (no spawn point loaded)"
        end
    end

    function mode.stop()
        mode.target = nil
        mode.status = "Idle"
        search:reset()
    end

    return mode
end
