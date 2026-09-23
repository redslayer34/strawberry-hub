--=============================================================================
-- MOVEMENT — flies the character to a goal, one Heartbeat step at a time
--=============================================================================
--  Features never move the character themselves: they set a goal with
--  Movement.to(cframe), every frame if the goal moves (a mob), and this module
--  steps toward it. Setting the goal again each frame is also what holds the
--  character in place above a mob once it has arrived.
--
--  Why stepping and not TweenService: a tween is committed to its path, so a
--  moving goal means cancelling and recreating it constantly. Stepping just
--  re-aims every frame.
--
--  The server pulls a character back when it moves too fast. That pull is
--  detected (the character is found far from where it was placed last frame)
--  and the speed cap drops for a few seconds, then climbs back toward the
--  TweenSpeed setting -- the same adaptive cap the reference uses.
--=============================================================================

local Player = require("Core.Player")
local Router = require("Game.Router")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Movement = {}

local SNAP = 2.5          -- studs: close enough to land exactly on the goal
local MAX_STEP = 18       -- studs per frame, whatever the speed
local MIN_CAP = 120       -- studs/s floor after repeated pull-backs
local PULL_BACK = 40      -- studs: a jump this large was the server, not us

local goal
local connection
local cap = math.huge
local nextRaise = 0
local lastPlaced
local lastCharacter

function Movement.to(cframe)
    goal = cframe
end

function Movement.goal()
    return goal
end

function Movement.moving()
    return goal ~= nil
end

-- Clears the goal and hands the character back to the player.
function Movement.stop()
    goal = nil
    lastPlaced = nil
    local hrp = Player.hrp()
    local float = hrp and hrp:FindFirstChild("FloatForce")
    if float then float:Destroy() end
end

-- Keeps the character from falling while it is placed by CFrame.
local function ensureFloat(hrp)
    if hrp:FindFirstChild("FloatForce") then return end
    local body = Instance.new("BodyVelocity")
    body.Name = "FloatForce"
    body.Velocity = Vector3.new(0, 0, 0)
    body.MaxForce = Vector3.new(100000, 100000, 100000)
    body.P = 10000
    body.Parent = hrp
end

local function noclip(character)
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            part.CanCollide = false
        end
    end
end

function Movement.step(dt)
    if not goal then return end

    local character = Player.character()
    local hrp = Player.hrp()
    local humanoid = Player.humanoid()
    if not character or not hrp or not humanoid or humanoid.Health <= 0 or hrp.Anchored then
        return
    end

    -- A new character spawns somewhere else: that jump is not a pull-back.
    if character ~= lastCharacter then
        lastCharacter = character
        lastPlaced = nil
    end

    ensureFloat(hrp)
    noclip(character)

    local now = os.clock()
    local here = hrp.Position
    local target = goal.Position

    if lastPlaced and (here - lastPlaced).Magnitude > PULL_BACK then
        cap = math.max(math.min(cap, Settings.get("TweenSpeed")) * 0.7, MIN_CAP)
        nextRaise = now + 3
    end

    local wanted = Settings.get("TweenSpeed")
    local speed = math.min(wanted, cap)

    -- Smart travel: the Router may be running a teleport (hold still, and
    -- forget where we placed the character: the jump is not a pull-back),
    -- or send us to an intermediate point such as the submarine dock.
    local destination = goal
    local handled, aim = Router.update(here, target, speed)
    if handled then
        lastPlaced = nil
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        return
    end
    if aim then
        target = aim
        destination = CFrame.new(aim)
    end

    local stepLength = math.min(speed * dt, MAX_STEP)
    local remaining = (target - here).Magnitude
    -- Short trips are set in one go, as the reference does.
    local snap = SNAP
    if Settings.get("SmartTravel") then snap = Router.SNAP end

    if remaining > stepLength and now >= nextRaise and cap < wanted then
        cap = math.min(cap * 1.08, wanted)
        nextRaise = now + 1.5
    end

    local placed
    if remaining <= math.max(stepLength, snap) then
        placed = destination
    else
        placed = CFrame.new(here + (target - here).Unit * stepLength)
    end

    hrp.CFrame = placed
    hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    lastPlaced = placed.Position
end

function Movement.start()
    if connection then return end
    connection = Services.get("RunService").Heartbeat:Connect(Movement.step)
end

function Movement.destroy()
    if connection then
        connection:Disconnect()
        connection = nil
    end
    Movement.stop()
end

-- Current flying speed: the setting, lowered while the server pulls back.
function Movement.speed()
    return math.min(Settings.get("TweenSpeed"), cap)
end

-- The portal recorder must not learn the hub's own flights.
require("Game.PortalRecorder").movingCheck = Movement.moving

-- Test hook.
function Movement.reset()
    goal, lastPlaced, lastCharacter = nil, nil, nil
    cap, nextRaise = math.huge, 0
end

return Movement
