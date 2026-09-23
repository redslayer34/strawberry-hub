--=============================================================================
-- PVP — follow a player, aim skills and guns at them, walk on water
--=============================================================================
--  The target is the player chosen in the list, or the nearest enemy (a
--  Marine does not target Marines, as in the reference).
--
--    Follow       a Farm mode: flies onto the target
--    Skill aim    AimHook sends every skill at the target
--    Gun aim      CombatUtil.GetTargetPosition answers the target's position
--                 (wrapped at start, restored on Unload)
--    Water walk   an invisible platform just under the sea surface
--=============================================================================

local AimHook = require("Game.AimHook")
local Common = require("Features.Stack.Common")
local Loop = require("Core.Loop")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Pvp = {}

Pvp.METHODS = { "Nearest enemy", "Selected player" }
Pvp.SEA_LEVEL = -60      -- the reference's sea height
Pvp.WATER_RANGE = 60     -- studs from sea level where the platform is active

local aiming = false
local gunModule, gunOriginal
local platform

-- Names of the other players, for the list.
function Pvp.playerNames()
    local names, me = {}, Services.player()
    for _, player in ipairs(Services.get("Players"):GetPlayers()) do
        if player ~= me then names[#names + 1] = player.Name end
    end
    table.sort(names)
    return names
end

local function rootOf(character)
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if root and humanoid and humanoid.Health > 0 then return root end
    return nil
end

local function enemy(player, me)
    if player == me then return false end
    local marines = Services.get("Teams"):FindFirstChild("Marines")
    if marines and me.Team == marines then return player.Team ~= marines end
    return true
end

-- The target's character, or nil.
function Pvp.target()
    local me = Services.player()
    if not me then return nil end
    if Settings.get("PvpMethod") == "Selected player" then
        local chosen = Services.get("Players"):FindFirstChild(Settings.get("PvpPlayer") or "")
        local character = chosen and chosen.Character
        return rootOf(character) and character or nil
    end
    local best, bestDistance
    for _, player in ipairs(Services.get("Players"):GetPlayers()) do
        local root = enemy(player, me) and rootOf(player.Character)
        if root then
            local distance = Player.distanceTo(root.Position)
            if not bestDistance or distance < bestDistance then best, bestDistance = player.Character, distance end
        end
    end
    return best
end

Pvp.follow = Mode({
    name = "Follow Player",
    key = "PvpFollow",
    want = function() return Pvp.target() ~= nil end,
    idleStatus = "No target",
    tick = function()
        local character = Pvp.target()
        if not character then return "No target" end
        Common.goTo(character.HumanoidRootPart.CFrame)
        return "Following " .. character.Name
    end,
})

---------------------------------------------------------------------------
-- Aim
---------------------------------------------------------------------------

function Pvp.aimStep()
    if not Settings.get("PvpAimbot") then
        if aiming then
            aiming = false
            AimHook.target = nil
        end
        return
    end
    local character = Pvp.target()
    if not character then return end
    aiming = true
    AimHook.install()
    AimHook.target = character.HumanoidRootPart.CFrame
end

-- Guns ask CombatUtil where to shoot; the wrapper answers the target.
function Pvp.installGunAim()
    if gunModule then return true end
    local module = Services.module("Modules.CombatUtil")
    if type(module) ~= "table" or type(module.GetTargetPosition) ~= "function" then return false end
    gunModule, gunOriginal = module, module.GetTargetPosition
    module.GetTargetPosition = function(...)
        if Settings.get("PvpGunAimbot") then
            local character = Pvp.target()
            if character then return character.HumanoidRootPart.Position end
        end
        return gunOriginal(...)
    end
    return true
end

---------------------------------------------------------------------------
-- Walk on water
---------------------------------------------------------------------------

function Pvp.waterStep()
    if not Settings.get("PvpWaterWalk") then
        if platform then
            pcall(function() platform:Destroy() end)
            platform = nil
        end
        return
    end
    if not platform or not platform.Parent then
        platform = Instance.new("Part")
        platform.Name = "StrawberryWaterWalk"
        platform.Size = Vector3.new(2048, 1, 2048)
        platform.Transparency = 1
        platform.Anchored = true
        platform.Parent = workspace
    end
    local here = Player.position()
    local humanoid = Player.humanoid()
    local onWater = here ~= nil and math.abs(here.Y - Pvp.SEA_LEVEL) <= Pvp.WATER_RANGE
        and not (humanoid and humanoid.Sit) and not Movement.moving()
    platform.CanCollide = onWater
    if here then platform.Position = Vector3.new(here.X, -5, here.Z) end
end

function Pvp.platform()
    return platform
end

function Pvp.start()
    pcall(Pvp.installGunAim)
    Loop.start("PvpAim", 0.05, Pvp.aimStep)
    Loop.start("WaterWalk", 0.1, Pvp.waterStep)
end

function Pvp.destroy()
    Loop.stop("PvpAim")
    Loop.stop("WaterWalk")
    if aiming then AimHook.target = nil end
    aiming = false
    if gunModule then gunModule.GetTargetPosition = gunOriginal end
    gunModule, gunOriginal = nil, nil
    if platform then pcall(function() platform:Destroy() end) end
    platform = nil
end

return Pvp
