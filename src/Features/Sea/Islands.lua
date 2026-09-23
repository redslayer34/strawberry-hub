--=============================================================================
-- SEA ISLANDS — Mirage, Kitsune Island, Leviathan (Sea 3)
--=============================================================================
--  Mirage and the Frozen Dimension spawn while someone sails far out: the
--  finders drive your boat straight out to sea (at the reference's height,
--  above the waves) until the island shows up, then let the next farm run.
--  Every spawn (Mirage, Frozen Dimension, Prehistoric Island) is reported
--  once to the webhook when its toggle is on.
--
--  Kitsune: sail to Zone 6 on a full moon night until the island appears,
--  touch the shrine, collect the Azure Embers during the event and pray at
--  the statue once you hold enough.
--
--  Leviathan: buy the spy's info, find the Frozen Dimension (Beast Hunter
--  boat), open the gate at the Frozen Watcher, then fight the tail, the head
--  and the segments, and harpoon the Frozen Heart. Other accounts can ride
--  the finder's cannons (Multi Find).
--=============================================================================

local Boat = require("Game.Boat")
local Common = require("Features.Stack.Common")
local Events = require("Features.Sea.Events")
local Loop = require("Core.Loop")
local Mastery = require("Game.Mastery")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local Webhook = require("Features.Webhook")
local World = require("Game.World")

local Islands = {}

Islands.SAIL_HEIGHT = 160        -- the finders' boat height
Islands.SAFE_HEIGHT = 500        -- while a sea event is near
Islands.KITSUNE_SPOT = Boat.ZONES["Zone 6"] + Vector3.new(0, 0, 1000)
Islands.HEART_DISTANCE = 300
Islands.SEGMENTS = { 2, 3, 4 }

local seen = {}

local function map(name)
    local root = workspace:FindFirstChild("Map")
    return root and root:FindFirstChild(name)
end

local function location(name)
    local locations = Services.find(workspace, "_WorldOrigin.Locations")
    return locations and locations:FindFirstChild(name)
end

function Islands.raidTimer()
    local player = Services.player()
    local timer = player and Services.find(player, "PlayerGui.Main.TopHUDList.RaidTimer")
    return timer ~= nil and timer.Visible == true
end

-- Reports `what` once each time it appears (the webhook toggle `key`
-- decides whether a message is sent).
local function report(key, what, present)
    if not present then
        seen[what] = nil
        return false
    end
    if seen[what] then return false end
    seen[what] = true
    return Webhook.notify(key, what, "Spawned in this server")
end

-- One step of sailing out to sea to make islands spawn.
function Islands.sailOut(boatName)
    local boat, status = Boat.get(boatName)
    if not boat then return status end
    local height = Events.find(Events.ALL) and Islands.SAFE_HEIGHT or Islands.SAIL_HEIGHT
    Boat.sail(boat, Boat.FAR, height)
    return "Sailing out to sea"
end

---------------------------------------------------------------------------
-- Mirage
---------------------------------------------------------------------------

function Islands.mirage()
    return map("MysticIsland")
end

function Islands.findMirageStep()
    if Islands.mirage() then return nil end
    return "Mirage: " .. Islands.sailOut()
end

Islands.findMirage = Mode({
    name = "Find Mirage",
    key = "SeaFindMirage",
    sea = 3,
    want = function() return Islands.mirage() == nil end,
    idleStatus = "Mirage Island is here",
    tick = function() return Islands.sailOut() end,
    stop = Boat.stop,
})

---------------------------------------------------------------------------
-- Kitsune
---------------------------------------------------------------------------

function Islands.kitsuneReady()
    local prompt = Services.find(workspace, "Map.KitsuneIsland.ShrineDialogPart.ProximityPrompt")
    return prompt ~= nil and prompt.Enabled ~= false
end

-- A full moon tonight, or tomorrow night.
function Islands.moonSoon()
    local moon = World.moon()
    local hoursToNight = math.floor(18 - (Services.get("Lighting").ClockTime or 12))
    return (moon == "Full Moon" and hoursToNight >= 0 and hoursToNight <= 5) or moon == "Next Night"
end

Islands.kitsuneTeleport = Mode({
    name = "Kitsune Island",
    key = "SeaKitsuneTeleport",
    sea = 3,
    want = function() return location("Kitsune Island") ~= nil end,
    idleStatus = "No Kitsune Island",
    tick = function()
        Common.goTo(location("Kitsune Island").CFrame)
        return "Going to Kitsune Island"
    end,
})

Islands.kitsuneSpawn = Mode({
    name = "Spawn Kitsune",
    key = "SeaKitsuneSpawn",
    sea = 3,
    want = function() return not Islands.kitsuneReady() end,
    idleStatus = "Kitsune Island is here",
    tick = function()
        if Settings.get("SeaKitsuneHop") and not Islands.moonSoon() then
            Movement.stop()
            Common.hop("no full moon for Kitsune", true)
            return "Hopping for a full moon"
        end
        local boat, status = Boat.get()
        if not boat then return status end
        if Boat.sail(boat, Islands.KITSUNE_SPOT) > Events.AT_ZONE then return "Sailing to Zone 6" end
        return "Waiting for Kitsune Island (full moon night)"
    end,
    stop = Boat.stop,
})

Islands.kitsuneSummon = Mode({
    name = "Kitsune Shrine",
    key = "SeaKitsuneSummon",
    sea = 3,
    want = function() return Islands.kitsuneReady() and not Islands.raidTimer() end,
    idleStatus = "No shrine to touch",
    tick = function()
        local shrine = Services.find(workspace, "Map.KitsuneIsland.ShrineInactive")
        local pivot = Common.pivot(shrine)
        if not pivot then
            Movement.stop()
            return "Shrine not loaded"
        end
        Common.goTo(pivot)
        if Common.near(pivot, 10) and Common.every("KitsuneShrine", 5) then
            local remote = Common.net("RE/TouchKitsuneStatue")
            if remote then pcall(function() remote:FireServer() end) end
        end
        return "Touching the shrine"
    end,
})

local function soulEmber()
    for _, child in ipairs(workspace:GetChildren()) do
        local part = child.Name == "EmberTemplate" and child:FindFirstChild("Part")
        if part then return part end
    end
    return nil
end

Islands.kitsuneEmbers = Mode({
    name = "Azure Embers",
    key = "SeaKitsuneEmbers",
    sea = 3,
    want = Islands.raidTimer,
    idleStatus = "Waiting for the Kitsune event",
    tick = function()
        local ember = soulEmber()
        if ember then
            Common.goTo(ember.CFrame)
            return "Collecting an Azure Ember"
        end
        local island = location("Kitsune Island")
        if island then
            Common.goTo(island.CFrame)
            return "Waiting for embers"
        end
        Movement.stop()
        return "No Kitsune Island"
    end,
})

function Islands.tradeEmbers()
    if not Islands.raidTimer() then return false end
    if Common.itemCount("Azure Ember") < (tonumber(Settings.get("SeaAzureEmbers")) or 10) then return false end
    local remote = Common.net("RF/KitsuneStatuePray")
    if not remote then return false end
    pcall(function() remote:InvokeServer() end)
    Common.forget()
    return true
end

---------------------------------------------------------------------------
-- Leviathan
---------------------------------------------------------------------------

function Islands.leviathanStatus()
    local answer = Common.invoke("InfoLeviathan", "1")
    if answer == -1 then return "I DONT KNOW" end
    if answer == 5 then return "You can find leviathan now" end
    return "Buy Find leviathan"
end

function Islands.buySpy()
    if Islands.leviathanStatus() ~= "Buy Find leviathan" then return false end
    Services.invoke("InfoLeviathan", "1")
    Services.invoke("InfoLeviathan", "2")
    Common.forget()
    return true
end

function Islands.frozenDimension()
    return location("Frozen Dimension")
end

local function frozenWatcher()
    return World.npcPosition("Frozen Watcher")
end

Islands.findLeviathan = Mode({
    name = "Find Leviathan",
    key = "SeaFindLeviathan",
    sea = 3,
    want = function() return Islands.frozenDimension() == nil end,
    idleStatus = "The Frozen Dimension is here",
    tick = function()
        return Islands.sailOut(Settings.get("SeaBuyBeastHunter") and "Beast Hunter" or nil)
    end,
    stop = Boat.stop,
})

-- A free cannon seat on `owner`'s boat.
function Islands.freeCannon(owner)
    local boat = Boat.mine(owner)
    for _, child in ipairs(boat and boat:GetChildren() or {}) do
        local seat = child.Name == "Cannon" and child:FindFirstChild("Seat")
        if seat and not seat:FindFirstChild("SeatWeld") then return seat end
    end
    return nil
end

Islands.multiLeviathan = Mode({
    name = "Multi Find Leviathan",
    key = "SeaMultiLeviathan",
    sea = 3,
    want = function() return Islands.frozenDimension() == nil end,
    idleStatus = "The Frozen Dimension is here",
    tick = function()
        local humanoid = Player.humanoid()
        if humanoid and humanoid.Sit then
            Movement.stop()
            return "Riding " .. tostring(Settings.get("SeaLeviathanOwner")) .. "'s boat"
        end
        local seat = Islands.freeCannon(Settings.get("SeaLeviathanOwner"))
        if not seat then
            Movement.stop()
            return "No free cannon on the selected boat"
        end
        Movement.to(seat.CFrame)
        return "Taking a cannon seat"
    end,
})

local function toWatcher(open)
    local watcher = frozenWatcher()
    if not watcher then
        Common.goTo(Islands.frozenDimension().CFrame)
        return "Going to the Frozen Dimension"
    end
    Common.goTo(watcher)
    if open and Common.near(watcher, 8) and Common.every("LeviathanGate", 2.5) then
        Services.invoke("OpenLeviathanGate")
        return "Opening the Leviathan gate"
    end
    return "Going to the Frozen Watcher"
end

Islands.frozenTeleport = Mode({
    name = "Frozen Dimension",
    key = "SeaFrozenTeleport",
    sea = 3,
    want = function() return Islands.frozenDimension() ~= nil end,
    idleStatus = "No Frozen Dimension",
    tick = function() return toWatcher(false) end,
})

-- The part of the Leviathan to hit: an exposed tail, the head when not
-- armored, then segments 2 to 4 (the reference's order).
function Islands.leviathanTarget()
    local beasts = workspace:FindFirstChild("SeaBeasts")
    if not beasts then return nil end
    local function healthy(part)
        local health = part:FindFirstChild("Health")
        return health ~= nil and (tonumber(health.Value) or 0) > 0
    end
    local children = beasts:GetChildren()
    for _, part in ipairs(children) do
        if part.Name == "Leviathan Tail" and part:GetAttribute("HealthEnabled") and healthy(part) then return part end
    end
    for _, part in ipairs(children) do
        if part.Name == "Leviathan" and not part:GetAttribute("Armored") and healthy(part) then return part end
    end
    for _, id in ipairs(Islands.SEGMENTS) do
        for _, part in ipairs(children) do
            if part.Name == "Leviathan Segment" and part:GetAttribute("SegmentId") == id and healthy(part) then
                return part
            end
        end
    end
    return nil
end

Islands.leviathanStart = Mode({
    name = "Start Leviathan",
    key = "SeaLeviathanStart",
    sea = 3,
    want = function() return Islands.frozenDimension() ~= nil and Islands.leviathanTarget() == nil end,
    idleStatus = "No Frozen Dimension",
    tick = function() return toWatcher(true) end,
})

Islands.leviathanAttack = Mode({
    name = "Attack Leviathan",
    key = "SeaLeviathanAttack",
    sea = 3,
    want = function() return Islands.leviathanTarget() ~= nil end,
    idleStatus = "No Leviathan",
    tick = function()
        local part = Islands.leviathanTarget()
        local root = part:FindFirstChild("HumanoidRootPart") or part:FindFirstChild("Hitbox11")
        local hitbox = part:FindFirstChild("Hitbox11") or root
        if not root then return "Leviathan part not loaded" end
        local height = part.Name == "Leviathan" and 140 or 142
        Common.goTo(CFrame.new(root.Position.X, height, root.Position.Z))
        if Player.distanceTo(hitbox.Position) < Events.SKILL_RANGE then
            Mastery.fireAt(hitbox.CFrame, Events.weapons())
        end
        return "Fighting the " .. part.Name
    end,
})

local function frozenHeart()
    local heart = map("FrozenHeart")
    local inside = heart and heart:FindFirstChild("Inside")
    if not inside or inside:GetAttribute("Harpooned") then return nil end
    return heart, inside
end

local function faceTowards(position, target)
    local flat = Vector3.new(target.X, position.Y, target.Z)
    if CFrame.lookAt then return CFrame.lookAt(position, flat) end
    return CFrame.new(position)
end

Islands.leviathanHeart = Mode({
    name = "Frozen Heart",
    key = "SeaLeviathanHeart",
    sea = 3,
    want = function() return frozenHeart() ~= nil end,
    idleStatus = "No Frozen Heart to harpoon",
    tick = function()
        local heart, inside = frozenHeart()
        local owner = Settings.get("SeaHeartOwner")
        local boat = Boat.mine((owner ~= "" and owner) or nil)
        if not boat then
            Movement.stop()
            return "No Beast Hunter boat to harpoon from"
        end
        local seat = Boat.seat(boat)
        local cube = heart:FindFirstChild("Cube") or inside
        local spot = Vector3.new(cube.Position.X, seat.Position.Y, cube.Position.Z + Islands.HEART_DISTANCE)
        local humanoid = Player.humanoid()
        local sitting = humanoid and humanoid.SeatPart
        if (seat.Position - spot).Magnitude > 5 then
            if sitting == seat then
                Boat.to(faceTowards(spot, inside.Position))
                return "Bringing the boat to the heart"
            end
            Boat.stop()
            if Boat.mine() ~= boat then
                Movement.stop()
                return "Waiting for the boat owner"
            end
            Movement.to(seat.CFrame)
            return "Getting on the boat"
        end
        Boat.stop()
        local harpoon = boat:FindFirstChild("Harpoon")
        if not harpoon then return "This boat has no harpoon" end
        if sitting and sitting.Parent == harpoon then
            Movement.stop()
            if Common.every("FireHarpoon", 2) then
                local ok, now = pcall(function() return workspace:GetServerTimeNow() end)
                Services.invoke("FireHarpoon", 0.7853981633974483, 4.4342573293783646e-4, harpoon,
                    ok and now or os.time())
            end
            return "Harpooning the Frozen Heart"
        end
        local harpoonSeat = harpoon:FindFirstChild("Seat")
        if harpoonSeat then Movement.to(harpoonSeat.CFrame) end
        return "Taking the harpoon"
    end,
    stop = Boat.stop,
})

---------------------------------------------------------------------------
-- Loop (does not move the character)
---------------------------------------------------------------------------

function Islands.step()
    report("WebhookMirage", "Mirage Island", Islands.mirage() ~= nil)
    report("WebhookLeviathan", "Frozen Dimension", Islands.frozenDimension() ~= nil)
    report("WebhookPrehistoric", "Prehistoric Island", map("PrehistoricIsland") ~= nil)
    if Settings.get("SeaBuySpy") and Common.every("BuySpy", 5) then Islands.buySpy() end
    if Settings.get("SeaKitsuneTrade") and Common.every("KitsunePray", 5) then Islands.tradeEmbers() end
end

function Islands.start()
    Loop.start("Sea", 1, Islands.step)
end

function Islands.reset()
    seen = {}
end

return Islands
