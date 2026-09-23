--=============================================================================
-- PLAYER TWEAKS — walk speed, jump power, noclip
--=============================================================================
--  Re-applied every tenth of a second because the game resets them (on
--  respawn, on some abilities). Noclip is left to Movement while a farm is
--  flying the character.
--
--  Buso (armament) Haki is always kept on: it is off after every respawn,
--  and many mobs and every boss take far less damage without it.
--=============================================================================

local Loop = require("Core.Loop")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
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

PlayerTweaks.BUSO_COOLDOWN = 3
local lastBuso = -math.huge

-- The reference's test: the aura adds a "_BusoLayer1..." part, or HasBuso.
local function busoOn(character)
    if character:FindFirstChild("HasBuso") then return true end
    for _, child in ipairs(character:GetChildren()) do
        if tostring(child.Name):find("_BusoLayer1", 1, true) then return true end
    end
    return false
end

-- Turns Buso on if it is off. Safe to call often: it waits BUSO_COOLDOWN
-- after a request while the aura appears.
function PlayerTweaks.ensureBuso()
    local character = Player.character()
    if not character or not Player.alive() or busoOn(character) then return false end
    local now = os.clock()
    if now - lastBuso < PlayerTweaks.BUSO_COOLDOWN then return false end
    lastBuso = now
    Services.invoke("Buso")
    return true
end

function PlayerTweaks.start()
    Loop.start("PlayerTweaks", 0.1, PlayerTweaks.tick)
    Loop.start("AutoBuso", 1, PlayerTweaks.ensureBuso)
end

-- Test hook.
function PlayerTweaks.reset()
    lastBuso = -math.huge
end

return PlayerTweaks
