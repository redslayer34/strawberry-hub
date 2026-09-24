--=============================================================================
-- SAFE SPOT — the reference's "Tween Safe if have Items"
--=============================================================================
--  A Fist of Darkness or a God's Chalice is lost on death. While one is
--  held, the character waits at a safe spot (the Café in Sea 2, the Mansion
--  in Sea 3), unless a feature that is on is about to use it: Darkbeard,
--  the Soul Guitar and the Cyborg race use the Fist, rip_indra's summon and
--  Yoru use the Chalice.
--=============================================================================

local Common = require("Features.Stack.Common")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Settings = require("Core.Settings")

local SafeSpot = {}

SafeSpot.SPOTS = {
    [2] = Vector3.new(-385.250916, 73.0458984, 297.388397),
    [3] = Vector3.new(-12463, 374, -7523),
}
SafeSpot.FIST_USERS = { "StackSummonDarkbeard", "StackDarkbeard", "ItemSoulGuitar", "RaceCyborgFist" }
SafeSpot.CHALICE_USERS = { "StackSummonRipIndra", "ItemYoru" }

local function anyOn(keys)
    for _, key in ipairs(keys) do
        if Settings.get(key) then return true end
    end
    return false
end

-- The item to protect, or nil.
function SafeSpot.item()
    if Common.has("Fist of Darkness") and not anyOn(SafeSpot.FIST_USERS) then return "Fist of Darkness" end
    if Common.has("God's Chalice") and not anyOn(SafeSpot.CHALICE_USERS) then return "God's Chalice" end
    return nil
end

SafeSpot.mode = Mode({
    name = "Safe Spot",
    key = "SafeWithItems",
    want = function() return SafeSpot.item() ~= nil end,
    idleStatus = "No Fist or Chalice to protect",
    tick = function()
        local spot = SafeSpot.SPOTS[Player.sea()]
        if not spot then
            Movement.stop()
            return "No safe spot in this sea"
        end
        Common.goTo(spot)
        return "Keeping the " .. tostring(SafeSpot.item()) .. " safe"
    end,
})

return SafeSpot
