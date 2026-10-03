-- Temporary: a small panel that flies you NEAR each portal of the sea
-- (about 15 studs away, never into it), and orange USE buttons that go
-- through a portal the game's own way (requestEntrance, then the client
-- puts the character on the answer).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

local env = (getgenv and getgenv()) or _G
if env.StrawberryPortalFly then pcall(env.StrawberryPortalFly) end

local SPEED = 300       -- studs/s
local AWAY = 15         -- studs from the portal where the flight stops
local V = Vector3.new

local SEAS = { [2753915549] = 1, [85211729168715] = 1, [4442272183] = 2, [79091703265657] = 2,
    [7449423635] = 3, [100117331123089] = 3 }
local sea = SEAS[game.PlaceId] or 0
local SPOTS = {
    [1] = {
        { "Underwater City door", V(4050, 6, -1815) },
        { "Underwater City exit door", V(61170, 1, 1952) },
        { "Sky (lower)", V(-4607.8, 872.5, -1667.6) },
        { "Upper Sky (old point)", V(-6023, 5469, 2203) },
    },
    [2] = {
        { "Ghost Ship door", V(-6499, 91, -127) },
        { "Ghost Ship exit door", V(920, 155, 32838) },
    },
    [3] = {
        { "Castle -> Mansion door", V(-5060.4, 318.5, -3193.2) },
        { "Castle -> Hydra door", V(-5027.0, 318.5, -3206.7) },
        { "Castle -> Tiki door", V(-5097.1, 318.5, -3178.4) },
        { "Mansion door", V(-12463.6, 378.3, -7566.1) },
        { "Hydra door", V(5651.0, 1017.3, -350.4) },
        { "Tiki door", V(-16799.1, 84.3, 291.1) },
        { "Submarine worker", V(-16269.4, 24.0, 1371.7) },
        { "Submerged Island dock", V(11427.9, -2156.4, 9726.2) },
        { "Temple of Time exit", V(28609.4, 14896.5, 106.4) },
    },
}

local function root() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end

-- Screen -------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "StrawberryPortalFly"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")

local panel = Instance.new("ScrollingFrame")
panel.Size = UDim2.new(0, 240, 0, 320)
panel.Position = UDim2.new(1, -250, 0, 60)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
panel.BackgroundTransparency = 0.2
panel.ScrollBarThickness = 6
panel.CanvasSize = UDim2.new(0, 0, 0, 0)
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 3)
layout.Parent = panel

local status = Instance.new("TextLabel")
status.Size = UDim2.new(0, 240, 0, 22)
status.Position = UDim2.new(1, -250, 0, 36)
status.BackgroundColor3 = Color3.fromRGB(200, 40, 70)
status.TextColor3 = Color3.new(1, 1, 1)
status.TextSize = 12
status.TextWrapped = true
status.Text = "Sea " .. sea .. " portals"
status.Parent = gui

local function row(text, color, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -8, 0, 26)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.new(1, 1, 1)
    b.TextSize = 12
    b.TextWrapped = true
    b.Text = text
    b.Parent = panel
    b.MouseButton1Click:Connect(callback)
    return b
end

-- Flight -------------------------------------------------------------------
local flight
local function stopFlight()
    if not flight then return end
    pcall(function() flight.tween:Cancel() end)
    pcall(function() flight.noclip:Disconnect() end)
    pcall(function() flight.hold:Destroy() end)
    flight = nil
end

local function flyNear(name, portal)
    stopFlight()
    local hrp = root()
    if not hrp then return end
    -- Stop AWAY studs short, on the side we come from, a little above.
    local flat = V(hrp.Position.X - portal.X, 0, hrp.Position.Z - portal.Z)
    local side = flat.Magnitude > 1 and flat.Unit or V(0, 0, 1)
    local goal = CFrame.new(portal + side * AWAY + V(0, 5, 0), portal)
    local distance = (hrp.Position - goal.Position).Magnitude
    status.Text = string.format("Flying to %s (%d studs)", name, distance)
    local hold = Instance.new("BodyVelocity")
    hold.MaxForce = V(9e9, 9e9, 9e9)
    hold.Velocity = V()
    hold.Parent = hrp
    local noclip = RunService.Stepped:Connect(function()
        for _, part in ipairs(player.Character and player.Character:GetDescendants() or {}) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end)
    local tween = TweenService:Create(hrp, TweenInfo.new(distance / SPEED, Enum.EasingStyle.Linear), { CFrame = goal })
    flight = { tween = tween, noclip = noclip, hold = hold }
    tween.Completed:Connect(function(state)
        if state == Enum.PlaybackState.Completed then
            stopFlight()
            status.Text = "Near " .. name .. ": walk in"
        end
    end)
    tween:Play()
end

-- Portal-like trigger parts of the loaded map.
local scanned = {}
local function scan()
    for _, b in ipairs(scanned) do b:Destroy() end
    scanned = {}
    local seen = {}
    local function addPart(part, label)
        local key = math.floor(part.Position.X / 20) .. "," .. math.floor(part.Position.Z / 20)
        if seen[key] or #scanned >= 40 then return end
        seen[key] = true
        local position = part.Position
        scanned[#scanned + 1] = row("[scan] " .. label, Color3.fromRGB(60, 90, 160), function()
            flyNear(label, position)
        end)
    end
    for _, part in ipairs(workspace:GetDescendants()) do
        if part:IsA("BasePart") and part:FindFirstChildOfClass("TouchTransmitter") then
            local name = part.Name:lower()
            if name:find("tele") or name:find("portal") or name:find("door") or name:find("entrance")
                or name:find("gate") then
                addPart(part, (part.Parent and part.Parent.Name or "?") .. "." .. part.Name)
            end
        end
    end
    pcall(function()
        for _, part in ipairs(game:GetService("CollectionService"):GetTagged("BoatCastleTeleporter")) do
            if part:IsA("BasePart") then addPart(part, "tag " .. part.Name) end
        end
    end)
    status.Text = "Scan: " .. #scanned .. " portal-like parts"
end

-- The game's own portals (PlayerScripts.AnimateEntrance): touching a
-- portal asks requestEntrance(arg), and the CLIENT moves the character to
-- the Vector3 the server answers. arg is the far side's point (or a name
-- for the Hydra boss doors). Parts may sit in ReplicatedStorage.MapStash
-- when not streamed in.
local function find(path)
    for _, top in ipairs({ workspace:FindFirstChild("Map"),
        game:GetService("ReplicatedStorage"):FindFirstChild("MapStash") }) do
        local node = top
        for name in string.gmatch(path, "[^/]+") do
            node = node and node:FindFirstChild(name)
        end
        if node then return node end
    end
    return nil
end
local function pos(path) local part = find(path) return part and part.Position end
local function ahead(path)
    local part = find(path)
    return part and (part.CFrame * V(0, 0, -6))
end
local PORTALS = {
    [1] = {
        { "Underwater City in", "TeleportSpawn/Entrance", function() return pos("TeleportSpawn/EntrancePoint") end },
        { "Underwater City out", "TeleportSpawn/Exit", function() return pos("TeleportSpawn/ExitPoint") end },
        { "Sky in (clouds broken)", "Sky/Entrance", function() return pos("SkyArea2/EntrancePoint") end },
        { "Sky out", "SkyArea2/Exit", function() return pos("Sky/ExitPoint") end },
    },
    [2] = {
        { "Flamingo in", "Dressrosa/FlamingoEntrance", function() return ahead("Dressrosa/FlamingoExit") end },
        { "Flamingo out", "Dressrosa/FlamingoExit", function() return ahead("Dressrosa/FlamingoEntrance") end },
        { "Ghost Ship in (lvl 1000)", "GhostShip/Teleport", function() return pos("GhostShipInterior/TeleportSpawn") end },
        { "Ghost Ship out", "GhostShipInterior/Teleport", function() return pos("GhostShip/TeleportSpawn") end },
    },
    [3] = {
        { "Mansion -> Castle", "Turtle/MapTeleportB/Hitbox", function() return pos("Boat Castle/MapTeleportA/Hitbox") end },
        { "Castle -> Mansion", "Boat Castle/MapTeleportA/Hitbox", function() return pos("Turtle/MapTeleportB/Hitbox") end },
        { "Castle -> Hydra", "Boat Castle/MapTeleportB/Hitbox", function() return pos("Waterfall/MapTeleportA/Hitbox") end },
        { "Hydra -> Castle", "Waterfall/MapTeleportA/Hitbox", function() return pos("Boat Castle/MapTeleportB/Hitbox") end },
        { "Turtle boss door (1950)", "Turtle/Entrance/Door/BossDoor/Hitbox", function() return "WaterfallBossHitbox" end },
        { "Hydra boss door back", "Waterfall/BossRoom/Door/BossDoor/Hitbox", function() return "TurtleEntranceBoss" end },
    },
}

local function describe(value)
    if typeof(value) == "Vector3" then
        return string.format("(%d, %d, %d)", value.X, value.Y, value.Z)
    end
    return tostring(value)
end

-- The game's way: requestEntrance(arg), then the character is put on the
-- answer when it is a Vector3.
local function enter(name, arg)
    local hrp = root()
    local commF = game:GetService("ReplicatedStorage").Remotes.CommF_
    local ok, answer = pcall(function() return commF:InvokeServer("requestEntrance", arg) end)
    if ok and typeof(answer) == "Vector3" and hrp and hrp.Parent then
        hrp.CFrame = CFrame.new(answer)
    end
    status.Text = string.format("%s: requestEntrance(%s) -> %s", name, describe(arg), ok and describe(answer) or "error")
    print("[PortalFly] " .. status.Text)
end

-- Flies next to the portal, then enters it the game's way.
local function use(portal)
    local part = find(portal[2])
    local arg = portal[3]()
    if not part or arg == nil then
        status.Text = portal[1] .. ": not loaded (go closer first)"
        return
    end
    stopFlight()
    local hrp = root()
    if not hrp then return end
    -- Beside it (8 studs), not on it: only our call takes the portal.
    local flat = V(hrp.Position.X - part.Position.X, 0, hrp.Position.Z - part.Position.Z)
    local side = flat.Magnitude > 1 and flat.Unit or V(0, 0, 1)
    local goal = CFrame.new(part.Position + side * 8 + V(0, 3, 0))
    local distance = (hrp.Position - goal.Position).Magnitude
    status.Text = string.format("Going into %s (%d studs)", portal[1], distance)
    local hold = Instance.new("BodyVelocity")
    hold.MaxForce = V(9e9, 9e9, 9e9)
    hold.Velocity = V()
    hold.Parent = hrp
    local noclip = RunService.Stepped:Connect(function()
        for _, piece in ipairs(player.Character and player.Character:GetDescendants() or {}) do
            if piece:IsA("BasePart") then piece.CanCollide = false end
        end
    end)
    local tween = TweenService:Create(hrp, TweenInfo.new(distance / SPEED, Enum.EasingStyle.Linear), { CFrame = goal })
    flight = { tween = tween, noclip = noclip, hold = hold }
    tween.Completed:Connect(function(state)
        if state ~= Enum.PlaybackState.Completed then return end
        stopFlight()
        enter(portal[1], portal[3]() or arg)
    end)
    tween:Play()
end

row("Stop flight", Color3.fromRGB(120, 30, 30), function()
    stopFlight()
    status.Text = "Flight stopped"
end)
row("Scan the map for portals", Color3.fromRGB(40, 120, 60), scan)
for _, spot in ipairs(SPOTS[sea] or {}) do
    row(spot[1], Color3.fromRGB(70, 70, 70), function() flyNear(spot[1], spot[2]) end)
end
for _, portal in ipairs(PORTALS[sea] or {}) do
    row("USE " .. portal[1], Color3.fromRGB(150, 90, 20), function() use(portal) end)
end
row("Close", Color3.fromRGB(50, 50, 50), function() env.StrawberryPortalFly() end)

env.StrawberryPortalFly = function()
    stopFlight()
    pcall(function() gui:Destroy() end)
end
