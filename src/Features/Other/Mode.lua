--=============================================================================
-- OTHER MODE — builds a Farming Other mode
--=============================================================================
--  Every Farming Other feature is a Farm mode (it moves the character), so
--  it runs one at a time with the others and Stack events still interrupt
--  it. A spec only says what differs:
--
--    name        shown in the status
--    key         the setting that turns it on
--    sea         optional: the only sea it works in
--    want()      optional: false when there is nothing to do right now; the
--                next farm mode then runs (e.g. no berry on the server)
--    idle()      optional: called while on but not wanted (e.g. to hop)
--    idleStatus  optional: status while not wanted
--    tick(mode)  does one step, returns the status text
--    stop()      optional: cleanup when the mode stops being the active one
--=============================================================================

local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Settings = require("Core.Settings")

return function(spec)
    local mode = { name = spec.name, status = "Idle", target = nil }

    function mode.enabled()
        if Settings.get(spec.key) ~= true then return false end
        if spec.sea and Player.sea() ~= spec.sea then
            mode.status = "Only in Sea " .. spec.sea
            return false
        end
        if spec.want then
            local ok, wanted = pcall(spec.want)
            if not (ok and wanted) then
                if spec.idle then pcall(spec.idle, mode) end
                mode.status = spec.idleStatus or "Nothing to do"
                return false
            end
        end
        return true
    end

    function mode.tick()
        mode.target = nil
        if not Player.alive() then
            mode.status = "Waiting for respawn"
            return
        end
        local ok, status = pcall(spec.tick, mode)
        if not ok then
            mode.target = nil
            Movement.stop()
            status = "error: " .. tostring(status)
        end
        mode.status = tostring(status)
    end

    function mode.stop()
        mode.target = nil
        mode.status = "Idle"
        if spec.stop then pcall(spec.stop) end
    end

    return mode
end
