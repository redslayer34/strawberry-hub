--=============================================================================
-- COMBAT — hits sent the way the game's own client sends them
--=============================================================================
--  A melee or sword blow is two remotes, in this order:
--
--    Modules.Net RE/RegisterAttack :FireServer(0)
--        announces the swing (0 = no animation delay)
--    Modules.Net RegisterHit       :FireServer(firstPart, { {rig, part}, ... })
--        applies the damage: the first hit part, then every other target
--
--  Hit parts are chosen like the game does: limbs only (the allow-list
--  below), one per rig, and only rigs CombatUtil reports as vulnerable.
--  A Blox Fruit's M1 goes through the tool's own LeftClickRemote instead.
--=============================================================================

local Player = require("Core.Player")
local Services = require("Core.Services")

local Combat = {}

-- Reach of a normal hit (the reference uses 30 for mobs and 80 for aura).
Combat.RANGE = 30
-- No strike is attempted on a target further than this.
Combat.MAX_TARGET_DISTANCE = 70

-- Body parts the server accepts as a hit.
Combat.LIMBS = {
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    UpperTorso = true, LowerTorso = true, Head = true,
}

local function combatUtil()
    return Services.module("Modules.CombatUtil")
end

local function candidates(includePlayers)
    local list = {}
    local enemies = workspace:FindFirstChild("Enemies")
    if enemies then
        for _, model in ipairs(enemies:GetChildren()) do list[#list + 1] = model end
    end
    if includePlayers then
        local characters = workspace:FindFirstChild("Characters")
        if characters then
            for _, model in ipairs(characters:GetChildren()) do list[#list + 1] = model end
        end
    end
    return list
end

local function partsWithin(model, origin, radius)
    local parts = {}
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") and (child.Position - origin).Magnitude <= radius then
            parts[#parts + 1] = child
        end
    end
    return parts
end

-- One {rig, part} pair per damageable target within `range` of the player,
-- or nil when there is none. The pairs are already in the shape RegisterHit
-- expects.
function Combat.gatherHits(range, includePlayers)
    local util = combatUtil()
    local character = Player.character()
    local hrp = Player.hrp()
    if not util or not character or not hrp then return nil end

    local origin = hrp.Position
    local players = Services.get("Players")
    local hits, seen = {}, {}

    for _, model in ipairs(candidates(includePlayers)) do
        local root = model:FindFirstChild("HumanoidRootPart")
        if model ~= character and root then
            local reach = range
            if players:GetPlayerFromCharacter(model) then reach = range / 1.5 end
            local radius = reach + root.Size.X / 2

            -- Tall rigs (bosses) are also tested from their feet, or their
            -- root would sit out of range while their legs are not.
            local points = { root.Position }
            if root.Size.Y > 5 then
                points[2] = (root.CFrame * CFrame.new(0, -root.Size.Y * 1.5 + 3, 0)).Position
            end

            local close = false
            for _, point in ipairs(points) do
                if (point - origin).Magnitude < 10 + radius then
                    close = true
                    break
                end
            end

            if close then
                for _, part in ipairs(partsWithin(model, origin, radius)) do
                    if Combat.LIMBS[part.Name] then
                        local rig = util:GetRigOfHitPart(part)
                        if rig and rig ~= character and not seen[rig] and util:IsVulnerable(rig) then
                            seen[rig] = true
                            hits[#hits + 1] = { rig, part }
                        end
                    end
                end
            end
        end
    end

    if #hits == 0 then return nil end
    return hits
end

-- Melee / sword blow on everything in range. Returns true if a hit was sent.
function Combat.attack(range, includePlayers)
    if Player.stunned() then return false end

    local registerAttack = Services.netRemote("RegisterAttack", false)
    local registerHit = Services.netRemote("RegisterHit", true)
    if not registerAttack or not registerHit then return false end

    local hits = Combat.gatherHits(range or Combat.RANGE, includePlayers)
    if not hits then return false end

    local first = table.remove(hits, 1)
    registerAttack:FireServer(0)
    registerHit:FireServer(first[2], hits)
    return true
end

local combo = 0

-- Blox Fruit M1 toward `position`. Returns true when the equipped fruit
-- accepted it, false when there is no fruit (the caller then falls back to a
-- normal attack).
function Combat.fruitClick(position)
    local tool = Player.equippedTool()
    local hrp = Player.hrp()
    if not tool or not hrp or tool.ToolTip ~= "Blox Fruit" then return false end

    local leftClick = tool:FindFirstChild("LeftClickRemote")
    local remoteFunction = tool:FindFirstChild("RemoteFunction")
    local remoteEvent = tool:FindFirstChild("RemoteEvent")

    if not leftClick and remoteFunction then
        if remoteEvent then remoteEvent:FireServer(position) end
        task.spawn(function()
            pcall(remoteFunction.InvokeServer, remoteFunction, "TAP")
        end)
        return true
    end

    if leftClick and tool.Name == "Mammoth-Mammoth" then
        leftClick:FireServer(position)
        return true
    end

    if leftClick then
        combo = combo % 5 + 1
        leftClick:FireServer((position - hrp.Position).Unit, combo)
        return true
    end

    return false
end

-- One strike at `target` with whatever is equipped.
function Combat.strike(target)
    local root = target and target:FindFirstChild("HumanoidRootPart")
    local humanoid = target and target:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then return false end
    if Player.distanceTo(root.Position) >= Combat.MAX_TARGET_DISTANCE then return false end

    local tool = Player.equippedTool()
    if tool and tool.ToolTip == "Blox Fruit" and Combat.fruitClick(root.Position) then
        return true
    end
    return Combat.attack(Combat.RANGE)
end

return Combat
