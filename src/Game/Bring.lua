--=============================================================================
-- BRING — pulls same-name mobs onto one spot so every hit lands on all of them
--=============================================================================
--  The client can only move a mob it simulates (network ownership). Two rules
--  from the reference keep that true:
--    - nothing is pulled while another player is within 300 studs (they may
--      own the mobs, and pulling would teleport them back and forth);
--    - a mob whose health has not moved 2.2 s after being pulled is not ours:
--      it is put back at its pivot and left alone for the rest of the fight.
--
--  The meeting point is the spawn part closest to the target, so the pack is
--  gathered where it already lives rather than dragged across the island.
--=============================================================================

local Enemies = require("Game.Enemies")
local Player = require("Core.Player")
local Services = require("Core.Services")

local Bring = {}

Bring.OTHER_PLAYER_RADIUS = 300
Bring.MAX_PLAYER_DISTANCE = 50   -- only pull while standing on the target
Bring.STUCK_AFTER = 2.2
Bring.INTERVAL = 0.15

-- Mobs we failed to own. Weak keys: a dead mob's model is collected.
local ignored = setmetatable({}, { __mode = "k" })
local watching = setmetatable({}, { __mode = "k" })

local lastTarget, anchor
local lastRun = -math.huge

local function otherPlayerNear(position, radius)
    local characters = workspace:FindFirstChild("Characters")
    local me = Services.player()
    if not characters or not me then return false end
    for _, model in ipairs(characters:GetChildren()) do
        if model.Name ~= me.Name then
            local root = model:FindFirstChild("HumanoidRootPart")
            if root and (root.Position - position).Magnitude <= radius then
                return true
            end
        end
    end
    return false
end
Bring.otherPlayerNear = otherPlayerNear

-- Which mobs to pull: the target first, then alive same-name mobs near the
-- anchor, up to `count`. Pure selection, no side effect.
function Bring.select(target, anchorPosition, count)
    local picked = { target }
    local radius = count > 2 and 350 or 200
    for _, mob in ipairs(Enemies.all(target.Name, ignored)) do
        if #picked >= count then break end
        local root = mob.HumanoidRootPart
        if mob ~= target
            and (root.Position - anchorPosition).Magnitude <= radius
            and not otherPlayerNear(root.Position, Bring.OTHER_PLAYER_RADIUS) then
            picked[#picked + 1] = mob
        end
    end
    return picked
end

local function noCollide(mob)
    for _, part in ipairs(mob:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            part.CanCollide = false
        end
    end
end

local function giveUp(mob)
    ignored[mob] = true
    pcall(function()
        mob.HumanoidRootPart.CFrame = mob.WorldPivot
    end)
end

local function watch(mob)
    if watching[mob] then return end
    watching[mob] = true
    local humanoid = mob:FindFirstChildOfClass("Humanoid")
    local before = humanoid and humanoid.Health
    task.delay(Bring.STUCK_AFTER, function()
        watching[mob] = nil
        if humanoid and humanoid.Parent and humanoid.Health > 0
            and humanoid.Health == before and not ignored[mob] then
            giveUp(mob)
        end
    end)
end

local function anchorFor(target)
    local root = target.HumanoidRootPart
    local spawnPart = Enemies.nearestSpawn(target.Name, root.Position)
    if spawnPart then return spawnPart.CFrame end
    return root.CFrame
end

-- Pulls up to `count` mobs of the target's kind onto the anchor. Safe to call
-- every frame: it throttles itself.
function Bring.run(target, count)
    if not Enemies.isAlive(target) or ignored[target] then return end

    local now = os.clock()
    if now - lastRun < Bring.INTERVAL then return end
    lastRun = now

    if target ~= lastTarget then
        lastTarget = target
        anchor = anchorFor(target)
    end

    local hrp = Player.hrp()
    if not hrp then return end
    if (hrp.Position - target.HumanoidRootPart.Position).Magnitude > Bring.MAX_PLAYER_DISTANCE then return end
    if otherPlayerNear(hrp.Position, Bring.OTHER_PLAYER_RADIUS) then return end

    -- A larger simulation radius lets the client own the mobs around it.
    if sethiddenproperty then
        pcall(sethiddenproperty, Services.player(), "SimulationRadius", 5000)
    end

    local group = Bring.select(target, anchor.Position, count or 2)
    if #group < 2 then return end

    for _, mob in ipairs(group) do
        noCollide(mob)
        mob.HumanoidRootPart.CFrame = anchor * CFrame.new(0, math.random(0, 2), math.random(0, 2))
        watch(mob)
    end
end

function Bring.isIgnored(mob)
    return ignored[mob] == true
end

-- Test hook.
function Bring.reset()
    ignored = setmetatable({}, { __mode = "k" })
    watching = setmetatable({}, { __mode = "k" })
    lastTarget, anchor, lastRun = nil, nil, -math.huge
end

return Bring
