--=============================================================================
-- BOAT — buys your boat, sits in it and drives it
--=============================================================================
--  A boat is driven like the character is flown (Game/Movement): a goal is
--  set with Boat.to and a Heartbeat step moves the VehicleSeat toward it.
--  The rest of the boat is welded to the seat and follows. The server pulls
--  a boat back when it goes too fast; that pull-back is detected and the
--  speed cap drops, then climbs back toward the SeaBoatSpeed setting (the
--  reference's manageTween does the same).
--
--  The character must stay seated for the server to accept the boat's
--  position, so the driver stops by itself as soon as you leave the seat,
--  and sea modes stop Movement while seated (Movement would pull the
--  character off the seat).
--=============================================================================

local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Boat = {}

Boat.NAMES = { "Guardian", "Beast Hunter", "Lantern", "Seleigh", "Brigade", "GrandBrigade" }
Boat.DEALERS = {
    [2] = Vector3.new(-13.488054275512695, 10.311711311340332, 2927.692),
    [3] = Vector3.new(-16204.0810546875, 9.0863618850708, 479.2259521484375),
}
Boat.ZONES = {
    ["Zone 1"] = Vector3.new(-21767.4765625, 0, 5815.41259765625),
    ["Zone 2"] = Vector3.new(-26017.931640625, 0, 5657.8837890625),
    ["Zone 3"] = Vector3.new(-29545.703125, 0, 6377.98974609375),
    ["Zone 4"] = Vector3.new(-33609.7578125, 0, 7422.890625),
    ["Zone 5"] = Vector3.new(-38480.42578125, 0, 10350.943359375),
    ["Zone 6"] = Vector3.new(-32975.9921875, 0, 25963.7109375),
}
Boat.ZONE_NAMES = { "Zone 1", "Zone 2", "Zone 3", "Zone 4", "Zone 5", "Zone 6" }
Boat.SEA2_SPOT = Vector3.new(654.3875732421875, 0, 6321.95947265625)
-- Where the reference sails to make islands spawn: straight out to sea.
Boat.FAR = Vector3.new(-118834.515625, 0, 99999920)
Boat.TOO_FAR = 4000       -- studs: a boat this far away is bought again
Boat.REACHED = 5          -- studs: the seat is set on the goal
Boat.MIN_CAP = 40         -- studs/s floor after pull-backs

local goal, connection
local cap, ceiling, nextRaise, lastPlaced = math.huge, math.huge, 0, nil
local lastNoclip = -math.huge

---------------------------------------------------------------------------
-- Finding and boarding
---------------------------------------------------------------------------

-- The boat owned by `owner` (default: you) that is still afloat.
function Boat.mine(owner)
    local player = Services.player()
    owner = owner or (player and player.Name)
    local boats = workspace:FindFirstChild("Boats")
    for _, boat in ipairs(boats and boats:GetChildren() or {}) do
        local tag = boat:FindFirstChild("Owner")
        local health = boat:FindFirstChild("Humanoid")
        if tag and tostring(tag.Value) == owner and boat:FindFirstChild("VehicleSeat")
            and (not health or (tonumber(health.Value) or 0) > 0) then
            return boat
        end
    end
    return nil
end

function Boat.seat(boat)
    return boat and boat:FindFirstChild("VehicleSeat")
end

function Boat.seated(boat)
    local humanoid = Player.humanoid()
    local seat = Boat.seat(boat)
    return seat ~= nil and humanoid ~= nil and humanoid.SeatPart == seat
end

-- The name BuyBoat expects.
function Boat.buyName(name)
    if name == "Brigade" or name == "GrandBrigade" then return "Pirate" .. name end
    return name
end

Boat.TIKI_SPAWNS = { Tiki = true, Tiki2 = true }
Boat.RESET_FAR = 1000
local lastReset = -math.huge

-- The reference's "Reset Character Buy Boat": far from the Sea 3 dealer
-- with the spawn point at Tiki Outpost, a reset is the fastest way there.
function Boat.resetForDealer(dealer)
    if not Settings.get("SeaResetForBoat") or Player.sea() ~= 3 then return false end
    if Player.distanceTo(dealer) <= Boat.RESET_FAR then return false end
    local player = Services.player()
    if not player or player:GetAttribute("CurrentLocation") == "Tiki Outpost" then return false end
    if not Boat.TIKI_SPAWNS[Player.data("LastSpawnPoint") or ""] then return false end
    if os.clock() - lastReset < 10 then return true end
    lastReset = os.clock()
    local humanoid = Player.humanoid()
    if humanoid then humanoid.Health = 0 end
    return true
end

-- Your boat once you sit in it; otherwise nil and what is being done
-- (flying to the dealer, buying, boarding). `name` is the boat to buy.
function Boat.get(name)
    local Common = require("Features.Stack.Common")
    local Movement = require("Game.Movement")
    local boat = Boat.mine()
    local seat = Boat.seat(boat)
    if not boat or Player.distanceTo(seat.Position) >= Boat.TOO_FAR then
        Boat.stop()
        local dealer = Boat.DEALERS[Player.sea()]
        if not dealer then
            Movement.stop()
            return nil, "No boat dealer in this sea"
        end
        if Boat.resetForDealer(dealer) then return nil, "Respawning at Tiki Outpost for the boat" end
        Common.goTo(dealer)
        if not Common.near(dealer, 8) then return nil, "Going to the boat dealer" end
        if Common.every("BuyBoat", 4) then
            Services.invoke("BuyBoat", Boat.buyName(name or Settings.get("SeaBoat")))
        end
        return nil, "Buying a boat"
    end
    if not Boat.seated(boat) then
        Boat.stop()
        Movement.to(seat.CFrame)
        return nil, "Getting on the boat"
    end
    Movement.stop()
    return boat
end

---------------------------------------------------------------------------
-- Driving
---------------------------------------------------------------------------

local function noclip(boat)
    for _, part in ipairs(boat:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
    end
end

-- Drives toward `where` (CFrame or Vector3), every frame until changed.
function Boat.to(where)
    if typeof(where) ~= "CFrame" then where = CFrame.new(where) end
    goal = where
end

-- Drives toward `position` on the water, keeping the seat's height (or `y`).
function Boat.sail(boat, position, y)
    local seat = Boat.seat(boat)
    if not seat then return math.huge end
    local target = Vector3.new(position.X, y or seat.Position.Y, position.Z)
    Boat.to(target)
    local flat = Vector3.new(seat.Position.X - target.X, 0, seat.Position.Z - target.Z)
    return flat.Magnitude
end

function Boat.goal()
    return goal
end

function Boat.stop()
    goal, lastPlaced = nil, nil
end

function Boat.speed()
    return math.min(Settings.get("SeaBoatSpeed"), cap, ceiling)
end

function Boat.step(dt)
    if not goal then return end
    local boat = Boat.mine()
    local seat = Boat.seat(boat)
    if not seat or not Boat.seated(boat) then
        Boat.stop()
        return
    end

    local now = os.clock()
    if now - lastNoclip >= 1 then
        lastNoclip = now
        noclip(boat)
    end

    local wanted = Settings.get("SeaBoatSpeed")
    local speed = math.min(wanted, cap)
    local stepLength = speed * dt
    local here = seat.Position

    if lastPlaced and (here - lastPlaced).Magnitude > math.max(20, stepLength * 3) then
        ceiling = speed * 0.9
        cap = math.max(speed * 0.7, Boat.MIN_CAP)
        nextRaise = now + 1
        speed = cap
        stepLength = speed * dt
    end

    local target = goal.Position
    local remaining = (target - here).Magnitude
    if remaining > stepLength and cap < math.min(wanted, ceiling) and now >= nextRaise then
        cap = math.min(cap * 1.08, ceiling, wanted)
        nextRaise = now + 1
    end

    local placed
    if remaining <= math.max(stepLength, Boat.REACHED) then
        placed = goal
    else
        placed = CFrame.new(here + (target - here).Unit * stepLength)
    end
    seat.CFrame = placed
    seat.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    seat.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    lastPlaced = placed.Position
end

function Boat.start()
    if connection then return end
    connection = Services.get("RunService").Heartbeat:Connect(Boat.step)
end

function Boat.destroy()
    if connection then
        connection:Disconnect()
        connection = nil
    end
    Boat.stop()
end

---------------------------------------------------------------------------
-- Repair
---------------------------------------------------------------------------

-- "Ship 1,200/3,000" -> 1200, 3000.
function Boat.health()
    local player = Services.player()
    local bar = player and Services.find(player, "PlayerGui.Main.BottomHUDList.ShipHealthBar")
    local label = bar and bar.Visible and bar:FindFirstChild("TextLabel")
    if not label then return nil end
    local text = tostring(label.Text):gsub(",", "")
    local current, max = text:match("(%d+)%s*/%s*(%d+)")
    return tonumber(current), tonumber(max)
end

-- Repairs the boat with the Shipwright hammer when it is damaged. Returns
-- the status while repairing, nil when there is nothing to repair.
function Boat.repair(boat)
    local current, max = Boat.health()
    if not current or not max or current >= max then return nil end
    local Common = require("Features.Stack.Common")
    local Movement = require("Game.Movement")
    local primary = boat.PrimaryPart or Boat.seat(boat)
    Boat.stop()
    local humanoid = Player.humanoid()
    if humanoid and humanoid.Sit then humanoid.Sit = false end
    local spot = primary.CFrame * CFrame.new(0, 15, 0)
    if Player.distanceTo(primary.Position) >= 20 then
        Movement.to(spot)
        return "Going to repair the boat"
    end
    Movement.to(spot)
    local character = Player.character()
    local hammer = character and character:FindFirstChild("_RepairHammer")
    if not hammer then
        local remote = Services.find(Services.replicated(), "Remotes.SubclassNetwork.UseSubclass")
        if remote and Common.every("RequestHammer", 3) then
            pcall(function() remote:InvokeServer({ Action = "RequestHammer" }) end)
        end
        return "Taking the repair hammer"
    end
    local up = hammer:FindFirstChild("M1UP")
    if up then
        up:Destroy()
    elseif not hammer:GetAttribute("Repairing") then
        local down = hammer:FindFirstChild("M1Down")
        if down and Common.every("Repair", 0.5) then pcall(function() down:FireServer("Default") end) end
    end
    return string.format("Repairing the boat (%d/%d)", current, max)
end

-- Test hook.
function Boat.reset()
    lastReset = -math.huge
    goal, lastPlaced = nil, nil
    cap, ceiling, nextRaise = math.huge, math.huge, 0
    lastNoclip = -math.huge
end

return Boat
