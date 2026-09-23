--=============================================================================
-- PLAYER TWEAKS — walk speed, jump power, noclip
--=============================================================================
--  Re-applied every tenth of a second because the game resets them (on
--  respawn, on some abilities). Noclip is left to Movement while a farm is
--  flying the character.
--=============================================================================

local Loop = require("Core.Loop")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Settings = require("Core.Settings")

local PlayerTweaks = {}

function PlayerTweaks.tick()
    local humanoid = Player.humanoid()
    if not humanoid then return end

    if Settings.get("WalkSpeedOn") then humanoid.WalkSpeed = Settings.get("WalkSpeed") end
    if Settings.get("JumpPowerOn") then
        humanoid.UseJumpPower = true
        humanoid.JumpPower = Settings.get("JumpPower")
    end

    if Settings.get("Noclip") and not Movement.moving() then
        local character = Player.character()
        for _, part in ipairs(character and character:GetDescendants() or {}) do
            if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
        end
    end
end

function PlayerTweaks.start()
    Loop.start("PlayerTweaks", 0.1, PlayerTweaks.tick)
end

return PlayerTweaks
