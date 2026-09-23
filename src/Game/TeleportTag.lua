--=============================================================================
-- TELEPORT TAG — the "Teleporting" tag the reference keeps while it moves
--=============================================================================
--  The reference (Banana Cat Hub) tags the local player "Teleporting"
--  (CollectionService) every time it moves the character or asks the game
--  for a teleport, and removes the tag HOLD seconds after the last move.
--  The game's own teleports carry the same tag.
--=============================================================================

local Services = require("Core.Services")

local TeleportTag = {}

TeleportTag.NAME = "Teleporting"
TeleportTag.HOLD = 1.5

local expires, scheduled = 0, false

local function tags()
    return Services.get("CollectionService")
end

local function remove()
    local player = Services.player()
    if player then pcall(function() tags():RemoveTag(player, TeleportTag.NAME) end) end
end

local function check()
    local left = expires - os.clock()
    if left > 0 then
        task.delay(left, check)
        return
    end
    scheduled = false
    remove()
end

-- Tags the player (again): the tag stays until HOLD seconds after the
-- last call.
function TeleportTag.mark()
    local player = Services.player()
    if not player then return end
    expires = os.clock() + TeleportTag.HOLD
    local ok, has = pcall(function() return tags():HasTag(player, TeleportTag.NAME) end)
    if not (ok and has) then
        pcall(function() tags():AddTag(player, TeleportTag.NAME) end)
    end
    if not scheduled then
        scheduled = true
        task.delay(TeleportTag.HOLD, check)
    end
end

-- Unload: the tag goes at once.
function TeleportTag.clear()
    expires = 0
    remove()
end

-- Test hook.
function TeleportTag.reset()
    expires, scheduled = 0, false
end

return TeleportTag
