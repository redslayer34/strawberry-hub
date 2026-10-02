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
local struck = setmetatable({}, { __mode = "k" })   -- clouds hit by us
local rememberBolt     -- defined with the quest state below
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
        if clouds[cloud] and struck[cloud] then rememberBolt() end
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
            if tagged(part) then return part, cloud end
        end
        if tagged(cloud) then return cloud, cloud end
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

-- The bolt phase, remembered per account in the workspace: the server's
-- state number after the cloud is not always 4 (the user's game went back
-- to "asking the Mad Scientist" with the bolt in hand), so once the cloud
-- phase (1 or 2) gave way to another state, or a struck cloud broke, the
-- bolt is taken as obtained until Electric is owned.
local boltSeen, lastState
local function boltFile()
    local player = Services.player()
    return "StrawberryHub/electric_bolt_" .. tostring(player and player.UserId or 0) .. ".txt"
end

rememberBolt = function()
    boltSeen = true
    pcall(function()
        if not writefile then return end
        if makefolder and isfolder and not isfolder("StrawberryHub") then makefolder("StrawberryHub") end
        writefile(boltFile(), "1")
    end)
end

local function boltRemembered()
    if boltSeen == nil then
        local ok, found = pcall(function() return isfile and isfile(boltFile()) end)
        boltSeen = ok and found == true
    end
    return boltSeen
end

-- Whether the player holds the Lightning Bolt (or the server says so).
function Electric.hasBolt()
    local state = Electric.state()
    if state == Electric.STATE_HAS_BOLT then return true end
    if Common.has("Lightning Bolt") or Common.itemCount("Lightning Bolt") > 0 then return true end
    if lastState and (lastState == 1 or lastState == 2) and state and state ~= 1 and state ~= 2 and state ~= 0 then
        rememberBolt()
    end
    lastState = state or lastState
    return boltRemembered()
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

Electric.ACCEPT_TRIES = 5      -- asks with no change of state...
Electric.GIVE_UP = 600         -- ...then the quest is left alone this long
local askTries, askState, givenUpUntil = 0, nil, nil

function Electric.givenUp()
    return givenUpUntil ~= nil and os.clock() < givenUpUntil
end

function Electric.step(mode)
    if not Common.travel(1) then return "Travelling to Sea 1" end
    local state = Electric.state()
    if Electric.hasBolt() then
        if (Player.data("Beli") or 0) < Electric.PRICE then
            Movement.stop()
            return "Holding the Lightning Bolt until $500,000"
        end
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
            -- The server's state after the cloud is not always 4: with the
            -- money, the bolt is offered (then the purchase) at every visit
            -- before asking for the quest. Without a bolt they just fail.
            local rich = (Player.data("Beli") or 0) >= Electric.PRICE
            local delivered, bought
            if rich then
                delivered = Services.invoke("DeliverLightningBolt")
                if delivered ~= 1 then bought = Services.invoke("BuyElectro") end
            end
            -- The same answer again and again: the quest does not start
            -- this way; leave it for a while instead of talking forever.
            if state == askState then askTries = askTries + 1 else askTries, askState = 1, state end
            if askTries > Electric.ACCEPT_TRIES then
                askTries, givenUpUntil = 0, os.clock() + Electric.GIVE_UP
            end
            local accepted = Services.invoke("AcceptElectroQuest")
            Electric.answers = string.format("deliver %s, buy %s, accept %s",
                tostring(delivered), tostring(bought), tostring(accepted))
            Common.forget()
            Melee.forget()
        end
        return "Asking the Mad Scientist about Electric (state " .. tostring(state)
            .. (Electric.answers and "; " .. Electric.answers or "") .. ")"
    end
    askTries = 0
    local part, cloud = Electric.target()
    if part then
        if cloud then struck[cloud] = true end
        return strike(mode, part)
    end
    Common.goTo(Electric.SKY_WAIT)
    return "Looking for a charged storm cloud"
end

Electric.mode = Mode({
    name = "Electric",
    key = "ItemElectric",
    -- The quest and the bolt cost nothing: only the delivery wants $500,000,
    -- so with the bolt in hand and less money the farms go on meanwhile.
    want = function()
        if Electric.owned() or Electric.givenUp() then return false end
        return not Electric.hasBolt() or (Player.data("Beli") or 0) >= Electric.PRICE
    end,
    idleStatus = "Owned, or holding the bolt until $500,000",
    tick = Electric.step,
})

-- Test hook.
function Electric.reset()
    Electric.destroy()
    lastHit = -math.huge
    boltSeen, lastState = nil, nil
    askTries, askState, givenUpUntil = 0, nil, nil
    Electric.answers = nil
end

return Electric
