-- Temporary: try the portals the way the hub now does it.
-- One button per portal of your sea: fly to the portal (6 studs), ask
-- requestEntrance(far side), then go where the server answers.
local rs = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local player = game:GetService("Players").LocalPlayer
local V = Vector3.new

local env = (getgenv and getgenv()) or _G
if env.StrawberryPortalTest then pcall(env.StrawberryPortalTest) end

local SEAS = { [2753915549] = 1, [85211729168715] = 1, [4442272183] = 2, [79091703265657] = 2,
    [7449423635] = 3, [100117331123089] = 3 }
local sea = SEAS[game.PlaceId] or 0

-- { name, portal (map path, fallback), far side (map path or fallback | string) }
local PORTALS = {
    [1] = {
        { "Underwater City in", { "TeleportSpawn/Entrance", V(4050, 6, -1815) },
            { "TeleportSpawn/EntrancePoint", V(61163.85, 11.76, 1819.78) } },
        { "Underwater City out", { "TeleportSpawn/Exit", V(61170, 1, 1952) },
            { "TeleportSpawn/ExitPoint", V(3864.69, 6.74, -1926.21) } },
        { "Upper Sky in", { "Sky/Entrance" }, { "SkyArea2/EntrancePoint", V(-6023.58, 5469.72, 2203.31) } },
        { "Upper Sky out", { "SkyArea2/Exit" }, { "Sky/ExitPoint", V(-4166.61, 1093.70, -347.16) } },
    },
    [2] = {
        { "Ghost Ship in", { "GhostShip/Teleport", V(-6499, 91, -127) }, { "GhostShipInterior/TeleportSpawn", V(923, 126, 32852) } },
        { "Ghost Ship out", { "GhostShipInterior/Teleport", V(920, 155, 32838) }, { "GhostShip/TeleportSpawn", V(-6509, 89, -133) } },
    },
    [3] = {
        { "Castle -> Mansion", { "Boat Castle/MapTeleportA/Hitbox", V(-5060.4, 318.5, -3193.2) },
            { "Turtle/MapTeleportB/Hitbox", V(-12463.6, 378.3, -7566.1) } },
        { "Mansion -> Castle", { "Turtle/MapTeleportB/Hitbox", V(-12463.6, 378.3, -7566.1) },
            { "Boat Castle/MapTeleportA/Hitbox", V(-5060.4, 318.5, -3193.2) } },
        { "Castle -> Hydra", { "Boat Castle/MapTeleportB/Hitbox", V(-5027.0, 318.5, -3206.7) },
            { "Waterfall/MapTeleportA/Hitbox", V(5651.0, 1017.3, -350.4) } },
        { "Hydra -> Castle", { "Waterfall/MapTeleportA/Hitbox", V(5651.0, 1017.3, -350.4) },
            { "Boat Castle/MapTeleportB/Hitbox", V(-5027.0, 318.5, -3206.7) } },
    },
}

local function find(path)
    for _, top in ipairs({ workspace:FindFirstChild("Map"), rs:FindFirstChild("MapStash") }) do
        local node = top
        for name in string.gmatch(path, "[^/]+") do node = node and node:FindFirstChild(name) end
        if node and node:IsA("BasePart") then return node end
    end
end
local function point(spec)
    local part = find(spec[1])
    return part and part.Position or spec[2]
end
local function root() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end
local function xyz(p) return typeof(p) == "Vector3" and string.format("(%d, %d, %d)", p.X, p.Y, p.Z) or tostring(p) end

-- Screen
local gui = Instance.new("ScreenGui")
gui.Name = "StrawberryPortalTest"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 230, 0, 0)
frame.AutomaticSize = Enum.AutomaticSize.Y
frame.Position = UDim2.new(1, -240, 0, 60)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
frame.BackgroundTransparency = 0.2
frame.Parent = gui
Instance.new("UIListLayout", frame).Padding = UDim.new(0, 3)
local function label(text)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 48)
    l.BackgroundColor3 = Color3.fromRGB(200, 40, 70)
    l.TextColor3 = Color3.new(1, 1, 1)
    l.TextSize = 12
    l.TextWrapped = true
    l.Text = text
    l.Parent = frame
    return l
end
local status = label("Sea " .. sea .. ": pick a portal")
local function button(text, color, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 28)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.new(1, 1, 1)
    b.TextSize = 13
    b.Text = text
    b.Parent = frame
    b.MouseButton1Click:Connect(callback)
end

-- Flight
local busy = false
local function flyTo(goal)
    local hrp = root()
    if not hrp then return false end
    local hold = Instance.new("BodyVelocity")
    hold.MaxForce = V(9e9, 9e9, 9e9)
    hold.Velocity = V()
    hold.Parent = hrp
    local noclip = RunService.Stepped:Connect(function()
        for _, p in ipairs(player.Character and player.Character:GetDescendants() or {}) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end)
    local tween = TweenService:Create(hrp, TweenInfo.new((hrp.Position - goal).Magnitude / 300, Enum.EasingStyle.Linear),
        { CFrame = CFrame.new(goal) })
    tween:Play()
    tween.Completed:Wait()
    noclip:Disconnect()
    hold:Destroy()
    return true
end

local function use(portal)
    if busy then return end
    local source, far = point(portal[2]), point(portal[3])
    if not source then
        status.Text = portal[1] .. ": portal not loaded, go closer"
        return
    end
    busy = true
    local hrp = root()
    local side = hrp and V(hrp.Position.X - source.X, 0, hrp.Position.Z - source.Z)
    side = side and side.Magnitude > 1 and side.Unit or V(0, 0, 1)
    status.Text = "Flying to " .. portal[1]
    if flyTo(source + side * 6 + V(0, 3, 0)) then
        local ok, answer = pcall(function() return rs.Remotes.CommF_:InvokeServer("requestEntrance", far) end)
        hrp = root()
        if ok and typeof(answer) == "Vector3" and hrp then hrp.CFrame = CFrame.new(answer) end
        task.wait(2)
        hrp = root()
        local moved = hrp and typeof(answer) == "Vector3" and (hrp.Position - answer).Magnitude < 300
        status.Text = string.format("%s: answer %s -> %s (now at %s)", portal[1], ok and xyz(answer) or "error",
            moved and "WORKS" or "did not work", hrp and xyz(hrp.Position) or "?")
    end
    busy = false
end

for _, portal in ipairs(PORTALS[sea] or {}) do
    button(portal[1], Color3.fromRGB(150, 90, 20), function() task.spawn(use, portal) end)
end
button("Close", Color3.fromRGB(60, 60, 60), function() env.StrawberryPortalTest() end)
env.StrawberryPortalTest = function() pcall(function() gui:Destroy() end) end
