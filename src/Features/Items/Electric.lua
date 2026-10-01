--=============================================================================
-- ITEMS: ELECTRIC — the Lightning Bolt quest (Sea 1)
--=============================================================================
--  The Mad Scientist no longer just sells Electric ("Electro"): he wants a
--  Lightning Bolt, dropped by a charged storm cloud over the Skylands, and
--  $500,000. It is one of the game's secret quests ("Electric Fighting
--  Teacher"); the steps are Vxeze Hub's, which handles the current version:
--
--    ElectroQuestState 4         the bolt is held: DeliverLightningBolt at
--                                the Mad Scientist (BuyElectro if it says
--                                anything but 1)
--    ElectroQuestState 1 or 2    quest on: strike a charged cloud with
--                                melee until it breaks and drops the bolt
--    anything else               AcceptElectroQuest at the Mad Scientist
--
--  The clouds are only announced by BonusMomentsRemoteEvent ("Charge",
--  "Split", "Break" for "Electric Fighting Teacher"), so Electric.start()
--  listens from the moment the script runs: a cloud charged earlier would
--  be missed otherwise. A cloud part is struck when it carries the
--  M1HitRegistry tag.
--
--  Electric is needed for Superhuman (300) and Electric Claw (400), so for
--  Godhuman.
--=============================================================================

local Common = require("Features.Stack.Common")
local Loop = require("Core.Loop")
local Melee = require("Features.Items.Melee")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local World = require("Game.World")

local Electric = {}

Electric.MOMENT = "Electric Fighting Teacher"
Electric.TAG = "M1HitRegistry"
Electric.SCIENTIST = Vector3.new(-4628.9, 12, -355.7)
Electric.SKY_WAIT = Vector3.new(-5025, 820, -640)
Electric.PRICE = 500000
Electric.HIT_RANGE = 12
Electric.HIT_EVERY = 0.4
Electric.STATE_HAS_BOLT = 4

local clouds = {}       -- [cloud] = { parts }
local connection
local lastHit = -math.huge

---------------------------------------------------------------------------
-- The clouds
---------------------------------------------------------------------------

-- One BonusMomentsRemoteEvent message (Vxeze's GetChargedClouds).
function Electric.onMoment(name, kind, cloud, extra)
    if name ~= Electric.MOMENT or typeof(cloud) ~= "Instance" then return end
    if kind == "Charge" then
        local parts = clouds[cloud] or {}
        clouds[cloud] = parts
        if typeof(extra) == "Instance" then
            for _, known in ipairs(parts) do
                if known == extra then return end
            end
            parts[#parts + 1] = extra
        end
    elseif kind == "Split" and type(extra) == "table" then
        local parts = clouds[cloud] or {}
        clouds[cloud] = parts
        for _, part in ipairs(extra) do parts[#parts + 1] = part end
    elseif kind == "Break" then
        clouds[cloud] = nil
    end
end

local function tagged(part)
    if not part or not part.Parent then return false end
    local ok, has = pcall(function()
        return Services.get("CollectionService"):HasTag(part, Electric.TAG)
    end)
    return ok and has == true
end

-- A cloud part that can be struck now, or nil. Clouds with none left are
-- forgotten.
function Electric.target()
    for cloud, parts in pairs(clouds) do
        for _, part in ipairs(parts) do
            if tagged(part) then return part end
        end
        if tagged(cloud) then return cloud end
        clouds[cloud] = nil
    end
    return nil
end

local function listen()
    if connection then return true end
    local remotes = Services.replicated():FindFirstChild("Remotes")
    local event = remotes and remotes:FindFirstChild("BonusMomentsRemoteEvent")
    if not event then return false end
    connection = event.OnClientEvent:Connect(function(...)
        pcall(Electric.onMoment, ...)
    end)
    return true
end

-- The remote may load after the script: retried until connected.
function Electric.start()
    if listen() then return end
    Loop.start("ElectricListen", 5, function()
        if listen() then Loop.stop("ElectricListen") end
    end)
end

function Electric.destroy()
    Loop.stop("ElectricListen")
    if connection then pcall(function() connection:Disconnect() end) end
    connection = nil
    clouds = {}
end

---------------------------------------------------------------------------
-- The quest
---------------------------------------------------------------------------

function Electric.owned()
    return Melee.owned("Electro")
end

function Electric.state()
    return tonumber(Common.invoke("ElectroQuestState"))
end

local function scientist()
    return World.npcPosition("Mad Scientist") or Electric.SCIENTIST
end

local function atScientist()
    local where = scientist()
    Common.goTo(CFrame.new(where + Vector3.new(0, 1.5, 4)))
    return Common.near(where, 10)
end

local function strike(mode, part)
    mode.target = nil
    local hrp = Player.hrp()
    if not hrp or (hrp.Position - part.Position).Magnitude > Electric.HIT_RANGE then
        Common.goTo(part.CFrame * CFrame.new(0, 0, 6))
        return "Flying to the charged storm cloud"
    end
    Common.goTo(hrp.CFrame)
    Player.equip("Melee")
    if os.clock() - lastHit >= Electric.HIT_EVERY then
        lastHit = os.clock()
        local attack = Services.netRemote("RegisterAttack", false)
        local hit = Services.netRemote("RegisterHit", true)
        if attack and hit then
            attack:FireServer(0.3)
            hit:FireServer(part)
        end
    end
    return "Striking the charged storm cloud"
end

function Electric.step(mode)
    if not Common.travel(1) then return "Travelling to Sea 1" end
    local state = Electric.state()
    if state == Electric.STATE_HAS_BOLT then
        if not atScientist() then return "Taking the Lightning Bolt to the Mad Scientist" end
        if Common.every("ElectricDeliver", 2) then
            if Services.invoke("DeliverLightningBolt") ~= 1 then Services.invoke("BuyElectro") end
            Common.forget()
            Melee.forget()
        end
        return "Giving the Lightning Bolt"
    end
    if state ~= 1 and state ~= 2 then
        if not atScientist() then return "Going to the Mad Scientist" end
        if Common.every("ElectricAccept", 3) then
            Services.invoke("AcceptElectroQuest")
            Common.forget()
        end
        return "Asking the Mad Scientist about Electric"
    end
    local part = Electric.target()
    if part then return strike(mode, part) end
    Common.goTo(Electric.SKY_WAIT)
    return "Looking for a charged storm cloud"
end

Electric.mode = Mode({
    name = "Electric",
    key = "ItemElectric",
    want = function()
        if Electric.owned() then return false end
        return (Player.data("Beli") or 0) >= Electric.PRICE or Electric.state() == Electric.STATE_HAS_BOLT
    end,
    idleStatus = "Owned, or $500,000 needed",
    tick = Electric.step,
})

-- Test hook.
function Electric.reset()
    Electric.destroy()
    lastHit = -math.huge
end

return Electric
