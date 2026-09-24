--=============================================================================
-- FARM HELPERS — the reference's "Setting Farm" extras
--=============================================================================
--    Auto Click       hits what is within 80 studs when no farm is fighting
--    Auto Observation turns Ken on (E) whenever it is off
--    Auto V3          the race's V3 ability, again and again
--    Dodge skills     a mob casting (BodyGyro, BodyPosition, KiBlastFireShort
--                     under the fought mob) sends the character 200 studs up
--                     until the cast ends
--    Low HP           under LowHpPercent % health the character stays
--                     LowHpHeight studs above its goal until back over 80 %
--    Sea dodges       the Terrorshark's charge (+200) and the sea beasts'
--                     beams (+600 while the animation plays)
--    Boat speed       the boat's MaxSpeed raised to the chosen value
--  The heights are applied by Movement (Movement.liftProvider), on the goal,
--  as the reference does.
--=============================================================================

local Boat = require("Game.Boat")
local Combat = require("Game.Combat")
local Enemies = require("Game.Enemies")
local Loop = require("Core.Loop")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Helpers = {}

Helpers.CLICK_RANGE = 80
Helpers.KEN_EVERY = 3
Helpers.V3_EVERY = 3
Helpers.DODGE_LIFT = 200
Helpers.BEAM_LIFT = 600
Helpers.DODGE_MAX = 14            -- seconds a dodge lasts at most
Helpers.BEAM_MAX = 10
Helpers.RECOVERED = 0.8           -- health ratio that ends the low-HP escape
Helpers.MOB_CASTS = { BodyGyro = true, BodyPosition = true, KiBlastFireShort = true }
Helpers.SHARK_CASTS = { SharkSplash = true, ChargeUp = true }
Helpers.BEAMS = { ["rbxassetid://8708221792"] = 1.9, ["rbxassetid://8708222556"] = 0.7 }

local connections = {}
local dodges = {}         -- [kind] = { part, since, grace, ended }
local beam                -- { track, since }
local watchedBeast, beastConnection
local lowHp = false
local last = {}

local function every(key, seconds)
    local now = os.clock()
    if last[key] and now - last[key] < seconds then return false end
    last[key] = now
    return true
end

local function fightTarget()
    local ok, target = pcall(function() return require("Features.Farm").target() end)
    return ok and target or nil
end

local function pressKey(key)
    pcall(function()
        local input = Services.get("VirtualInputManager")
        input:SendKeyEvent(true, key, false, game)
        input:SendKeyEvent(false, key, false, game)
    end)
end

---------------------------------------------------------------------------
-- Dodges
---------------------------------------------------------------------------

local function startDodge(kind, part, shortGrace, shortUnder)
    dodges[kind] = { part = part, since = os.clock(), shortGrace = shortGrace, shortUnder = shortUnder }
end

-- A dodge lasts while its part exists (at most DODGE_MAX); a short one
-- keeps a little grace after it, as the reference waits a moment.
local function dodgeActive(kind)
    local dodge = dodges[kind]
    if not dodge then return false end
    local now = os.clock()
    if now - dodge.since >= Helpers.DODGE_MAX then
        dodges[kind] = nil
        return false
    end
    if dodge.part and dodge.part.Parent then return true end
    if not dodge.ended then
        dodge.ended = now
        dodge.grace = (now - dodge.since < dodge.shortUnder) and dodge.shortGrace or 0
    end
    if now < dodge.ended + dodge.grace then return true end
    dodges[kind] = nil
    return false
end

function Helpers.onEnemyDescendant(node)
    if not Settings.get("DodgeSkills") or not Helpers.MOB_CASTS[node.Name] then return end
    local target = fightTarget()
    local owner = node.Parent and node.Parent.Parent
    if target and owner and owner.Name == target.Name then startDodge("mob", node, 0.5, 2) end
end

function Helpers.onOriginChild(node)
    if not Settings.get("SeaDodgeTerrorshark") or not Helpers.SHARK_CASTS[node.Name] then return end
    local target = fightTarget()
    local root = target and target.Name == "Terrorshark" and target:FindFirstChild("HumanoidRootPart")
    if root and node.Position and (root.Position - node.Position).Magnitude < 20 then
        startDodge("shark", node, 2.5, 1)
    end
end

-- The sea beast being fought (Features/Sea/Events sets it): its beam
-- animations start a high dodge after the wind-up.
local function watchBeast(beast)
    if beast == watchedBeast then return end
    if beastConnection then pcall(function() beastConnection:Disconnect() end) end
    beastConnection, watchedBeast = nil, beast
    local animator = beast and beast:FindFirstChild("Humanoid")
    if not animator then return end
    local ok, connection = pcall(function()
        return animator.AnimationPlayed:Connect(function(track)
            local id = track and track.Animation and tostring(track.Animation.AnimationId)
            local windUp = id and Helpers.BEAMS[id]
            if not windUp or not Settings.get("SeaDodgeSeaBeast") then return end
            task.delay(windUp, function() beam = { track = track, since = os.clock() } end)
        end)
    end)
    if ok then beastConnection = connection end
end

local function beamActive()
    if not beam then return false end
    local playing = beam.track and beam.track.IsPlaying
    if playing and os.clock() - beam.since < Helpers.BEAM_MAX then return true end
    beam = nil
    return false
end

-- The height Movement adds above its goal.
function Helpers.lift()
    if dodgeActive("mob") or dodgeActive("shark") then return Helpers.DODGE_LIFT end
    if beamActive() then return Helpers.BEAM_LIFT end
    if lowHp and Settings.get("LowHpEscape") then return tonumber(Settings.get("LowHpHeight")) or 0 end
    return 0
end

---------------------------------------------------------------------------
-- Loop
---------------------------------------------------------------------------

local function connect()
    if not connections.enemies then
        local enemies = workspace:FindFirstChild("Enemies")
        if enemies then connections.enemies = enemies.DescendantAdded:Connect(Helpers.onEnemyDescendant) end
    end
    if not connections.origin then
        local origin = workspace:FindFirstChild("_WorldOrigin")
        if origin then connections.origin = origin.ChildAdded:Connect(Helpers.onOriginChild) end
    end
end

function Helpers.updateHealth()
    local humanoid = Player.humanoid()
    if not humanoid or not humanoid.MaxHealth or humanoid.MaxHealth <= 0 then return end
    local ratio = humanoid.Health / humanoid.MaxHealth
    if ratio < (tonumber(Settings.get("LowHpPercent")) or 40) / 100 then
        lowHp = true
    elseif ratio > Helpers.RECOVERED then
        lowHp = false
    end
end

function Helpers.autoClick()
    if not Settings.get("AutoClick") or fightTarget() then return false end
    local tool = Player.equippedTool()
    if tool and tool.ToolTip == "Blox Fruit" then
        local mob = Enemies.nearestWithin(Helpers.CLICK_RANGE)
        return mob ~= nil and Combat.fruitClick(mob.HumanoidRootPart.Position)
    end
    return Combat.attack(Helpers.CLICK_RANGE)
end

function Helpers.step()
    connect()
    Helpers.updateHealth()
    if Settings.get("AutoKen") and every("Ken", Helpers.KEN_EVERY) then
        local blur = Services.get("Lighting"):FindFirstChild("Blur")
        if blur and not blur.Enabled then pressKey("E") end
    end
    if Settings.get("AutoV3") and every("V3", Helpers.V3_EVERY) then
        local remote = Services.find(Services.replicated(), "Remotes.CommE")
        if remote then pcall(function() remote:FireServer("ActivateAbility") end) end
    end
    if Settings.get("SeaBoatMaxSpeed") then
        local seat = Boat.seat(Boat.mine())
        local wanted = tonumber(Settings.get("SeaBoatMaxValue")) or 200
        if seat and (tonumber(seat.MaxSpeed) or 0) + 1 < wanted then seat.MaxSpeed = wanted end
    end
    local ok, Events = pcall(require, "Features.Sea.Events")
    watchBeast(ok and Events.beast and Events.beast.Parent and Events.beast or nil)
end

function Helpers.start()
    Movement.liftProvider = Helpers.lift
    Loop.start("FarmHelpers", 0.2, Helpers.step)
    Loop.start("AutoClick", function() return math.max(Settings.get("AttackDelay"), 0.1) end, Helpers.autoClick)
end

function Helpers.destroy()
    for key, connection in pairs(connections) do
        pcall(function() connection:Disconnect() end)
        connections[key] = nil
    end
    watchBeast(nil)
    if Movement.liftProvider == Helpers.lift then Movement.liftProvider = nil end
end

-- Test hook.
function Helpers.reset()
    Helpers.destroy()
    dodges, beam, lowHp, last = {}, nil, false, {}
end

return Helpers
