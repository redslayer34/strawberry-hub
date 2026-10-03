-- Temporary: a small panel that flies you NEAR each portal of the sea
-- (about 15 studs away, never into it). Walk in yourself.
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

row("Stop flight", Color3.fromRGB(120, 30, 30), function()
    stopFlight()
    status.Text = "Flight stopped"
end)
row("Scan the map for portals", Color3.fromRGB(40, 120, 60), scan)
for _, spot in ipairs(SPOTS[sea] or {}) do
    row(spot[1], Color3.fromRGB(70, 70, 70), function() flyNear(spot[1], spot[2]) end)
end
row("Close", Color3.fromRGB(50, 50, 50), function() env.StrawberryPortalFly() end)

env.StrawberryPortalFly = function()
    stopFlight()
    pcall(function() gui:Destroy() end)
end
