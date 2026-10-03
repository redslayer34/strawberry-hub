-- Temporary: records what happens while you go through the portals by hand.
--   remote calls (FireServer / InvokeServer, with the answer), teleports
--   (where from, where to, what was near), touched trigger parts, prompts.
-- The full log goes to StrawberryHub/portal_log.txt; "Copy" puts it on the
-- clipboard. Run it once, then walk through every portal; the panel on
-- the right flies you near each portal of the sea.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local player = Players.LocalPlayer

local env = (getgenv and getgenv()) or _G
if env.StrawberryPortalLog then pcall(env.StrawberryPortalLog) end

local log, connections, alive = {}, {}, true
local FILE = "StrawberryHub/portal_log.txt"
local started = os.clock()

-- Screen -------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "StrawberryPortalLog"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
local box = Instance.new("TextLabel")
box.Size = UDim2.new(0, 560, 0, 250)
box.Position = UDim2.new(0, 10, 1, -300)
box.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
box.BackgroundTransparency = 0.25
box.TextColor3 = Color3.new(1, 1, 1)
box.TextSize = 12
box.Font = Enum.Font.Code
box.TextXAlignment = Enum.TextXAlignment.Left
box.TextYAlignment = Enum.TextYAlignment.Bottom
box.TextWrapped = true
box.Parent = gui
local function button(text, x, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 90, 0, 28)
    b.Position = UDim2.new(0, 10 + x, 1, -335)
    b.BackgroundColor3 = Color3.fromRGB(200, 40, 70)
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Text = text
    b.Parent = gui
    b.MouseButton1Click:Connect(callback)
    return b
end

local function save()
    pcall(function()
        if not writefile then return end
        if makefolder and isfolder and not isfolder("StrawberryHub") then makefolder("StrawberryHub") end
        writefile(FILE, table.concat(log, "\n"))
    end)
end

local dirty = false
local function add(text)
    local line = string.format("[%6.1f] %s", os.clock() - started, text)
    log[#log + 1] = line
    print("[PortalLog] " .. line)
    local from = math.max(1, #log - 15)
    box.Text = table.concat(log, "\n", from)
    dirty = true
end
task.spawn(function()
    while alive do
        task.wait(3)
        if dirty then dirty = false save() end
    end
end)

-- Describing values ----------------------------------------------------------
local function round(n) return math.floor(n * 10 + 0.5) / 10 end
local function v3(v) return string.format("(%s, %s, %s)", round(v.X), round(v.Y), round(v.Z)) end
local function describe(value, depth)
    depth = depth or 0
    local t = typeof(value)
    if t == "Vector3" then return v3(value) end
    if t == "CFrame" then return "CF" .. v3(value.Position) end
    if t == "Instance" then
        local ok, name = pcall(function() return value:GetFullName() end)
        return ok and name or tostring(value)
    end
    if t == "string" then return string.format("%q", value) end
    if t == "table" then
        if depth > 2 then return "{..}" end
        local parts, count = {}, 0
        for key, inner in pairs(value) do
            count = count + 1
            if count > 12 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = tostring(key) .. "=" .. describe(inner, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(value)
end
local function describeAll(args, n)
    local out = {}
    for i = 1, n do out[i] = describe(args[i]) end
    return table.concat(out, ", ")
end

local function root() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end

-- Remote calls ----------------------------------------------------------------
-- Combat, camera and other per-frame chatter left out; the same call
-- repeated within 2 s is written once.
local NOISE = { "RegisterAttack", "RegisterHit", "Mouse", "Camera", "Ping", "Heartbeat", "Stamina", "Replicat",
    "Input", "Look", "Aim", "Sprint", "Move", "Velocity", "Animation", "Sound", "Effect", "FX" }
local function noisy(name)
    for _, word in ipairs(NOISE) do
        if name:find(word, 1, true) then return true end
    end
    return false
end
local lastSeen = {}

local oldNamecall
if hookmetamethod and getnamecallmethod then
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if alive and (method == "FireServer" or method == "InvokeServer") and not (checkcaller and checkcaller())
            and typeof(self) == "Instance" and not noisy(self.Name) then
            local args = table.pack(...)
            local text = method .. " " .. describe(self) .. "(" .. describeAll(args, args.n) .. ")"
            local now = os.clock()
            if not lastSeen[text] or now - lastSeen[text] > 2 then
                lastSeen[text] = now
                if method == "InvokeServer" then
                    local results = table.pack(oldNamecall(self, ...))
                    task.spawn(add, text .. " -> " .. describeAll(results, results.n))
                    return table.unpack(results, 1, results.n)
                end
                task.spawn(add, text)
            end
        end
        return oldNamecall(self, ...)
    end)
    add("Remote hook on")
else
    add("No hookmetamethod: remote calls not recorded")
end

-- What is near a spot: trigger parts and prompts within 30 studs.
local function nearby(position)
    local found = {}
    local params = OverlapParams.new()
    local ok, parts = pcall(function()
        return workspace:GetPartBoundsInRadius(position, 30, params)
    end)
    for _, part in ipairs(ok and parts or {}) do
        if part:FindFirstChildOfClass("TouchTransmitter") or part:FindFirstChildWhichIsA("ProximityPrompt", true)
            or part.Name:lower():find("tele") or part.Name:lower():find("portal")
            or part.Name:lower():find("door") or part.Name:lower():find("entrance") then
            found[#found + 1] = describe(part) .. " @" .. v3(part.Position)
            if #found >= 8 then break end
        end
    end
    return #found > 0 and table.concat(found, " | ") or "nothing marked"
end

-- Teleports: the character moved more than 150 studs in one frame.
local lastPos = root() and root().Position
connections[#connections + 1] = RunService.Heartbeat:Connect(function()
    local hrp = root()
    if not hrp then return end
    local pos = hrp.Position
    if lastPos and (pos - lastPos).Magnitude > 150 then
        local from = lastPos
        add("TELEPORT " .. v3(from) .. " -> " .. v3(pos) .. string.format("  (%d studs)", (pos - from).Magnitude))
        add("  near start: " .. nearby(from))
        task.delay(1, function()
            local here = root()
            if here then add("  1 s later at " .. v3(here.Position) .. ", near: " .. nearby(here.Position)) end
        end)
        task.delay(4, function()
            local here = root()
            if here then add("  4 s later at " .. v3(here.Position)) end
        end)
    end
    lastPos = pos
end)

-- Touched trigger parts (once per part every 5 s).
local touchedAt = {}
local function watchCharacter(character)
    local hrp = character:WaitForChild("HumanoidRootPart", 10)
    if not hrp then return end
    lastPos = hrp.Position
    add("Character at " .. v3(hrp.Position))
    connections[#connections + 1] = hrp.Touched:Connect(function(part)
        if not part:FindFirstChildOfClass("TouchTransmitter") then return end
        local now = os.clock()
        if touchedAt[part] and now - touchedAt[part] < 5 then return end
        touchedAt[part] = now
        add("TOUCH " .. describe(part) .. " @" .. v3(part.Position))
    end)
end
if player.Character then task.spawn(watchCharacter, player.Character) end
connections[#connections + 1] = player.CharacterAdded:Connect(function(character)
    add("Character respawned")
    task.spawn(watchCharacter, character)
end)

-- Prompts.
connections[#connections + 1] = ProximityPromptService.PromptTriggered:Connect(function(prompt)
    local parent = prompt.Parent
    local at = parent and (parent:IsA("BasePart") and parent.Position
        or parent:IsA("Attachment") and parent.WorldPosition)
    add(string.format("PROMPT %s '%s' / '%s'%s", describe(prompt), prompt.ActionText, prompt.ObjectText,
        at and (" @" .. v3(at)) or ""))
end)

-- Place, sea and map name changes.
add("Place " .. tostring(game.PlaceId) .. ", MAP " .. tostring(workspace:GetAttribute("MAP")))
connections[#connections + 1] = workspace:GetAttributeChangedSignal("MAP"):Connect(function()
    add("MAP -> " .. tostring(workspace:GetAttribute("MAP")))
end)

-- Buttons --------------------------------------------------------------------
local function stop()
    if not alive then return end
    alive = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    save()
    pcall(function() gui:Destroy() end)
end
env.StrawberryPortalLog = stop
button("Copy", 0, function()
    save()
    if setclipboard then
        setclipboard(table.concat(log, "\n"))
        add("Copied " .. #log .. " lines to the clipboard")
    else
        add("No setclipboard: the log is in workspace/" .. FILE)
    end
end)
button("Mark", 100, function()
    local hrp = root()
    add("---- MARK at " .. (hrp and v3(hrp.Position) or "?") .. " ----")
end)
button("Stop", 200, function() stop() end)

-- Portal travel ---------------------------------------------------------------
-- A small list of the known portal spots of this sea, plus "Scan": every
-- trigger part of the map whose name looks like a portal. A button flies
-- there (300 studs/s, no collisions); "Stop flight" ends a flight.
local SEAS = { [2753915549] = 1, [85211729168715] = 1, [4442272183] = 2, [79091703265657] = 2,
    [7449423635] = 3, [100117331123089] = 3 }
local sea = SEAS[game.PlaceId] or 0
local V = Vector3.new
local SPOTS = {
    [1] = {
        { "Underwater City door", V(4050, 6, -1815) },
        { "Underwater City exit door", V(61170, 1, 1952) },
        { "Underwater City (inside)", V(61163.9, 11.8, 1819.8) },
        { "Underwater exit landing", V(3876.3, 35.1, -1939.3) },
        { "Sky (lower, Banana's point)", V(-4607.8, 872.5, -1667.6) },
        { "Upper Sky (Teddy's old point)", V(-6023, 5469, 2203) },
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
        { "Cake Loaf mirror (inside)", V(-1990.7, 4533.0, -14973.7) },
    },
}

local flight
local function stopFlight()
    if not flight then return end
    pcall(function() flight.tween:Cancel() end)
    pcall(function() flight.noclip:Disconnect() end)
    pcall(function() flight.hold:Destroy() end)
    flight = nil
end
local function flyTo(name, position)
    stopFlight()
    local hrp = root()
    if not hrp then return end
    local goal = CFrame.new(position + V(0, 4, 0))
    local distance = (hrp.Position - goal.Position).Magnitude
    add(string.format("FLY to %s %s (%d studs)", name, v3(position), distance))
    local hold = Instance.new("BodyVelocity")
    hold.MaxForce = V(9e9, 9e9, 9e9)
    hold.Velocity = V()
    hold.Parent = hrp
    local noclip = RunService.Stepped:Connect(function()
        for _, part in ipairs(player.Character and player.Character:GetDescendants() or {}) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end)
    local tween = game:GetService("TweenService"):Create(hrp,
        TweenInfo.new(distance / 300, Enum.EasingStyle.Linear), { CFrame = goal })
    flight = { tween = tween, noclip = noclip, hold = hold }
    tween.Completed:Connect(function(state)
        if state == Enum.PlaybackState.Completed then
            add("Arrived near " .. name .. "; near: " .. nearby(position))
            -- Free again: walk into the portal yourself.
            stopFlight()
        end
    end)
    tween:Play()
end

local panel = Instance.new("ScrollingFrame")
panel.Size = UDim2.new(0, 240, 0, 300)
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
local scanned = {}
local function scan()
    for _, b in ipairs(scanned) do b:Destroy() end
    scanned = {}
    local seen = {}
    for _, part in ipairs(workspace:GetDescendants()) do
        if part:IsA("BasePart") and part:FindFirstChildOfClass("TouchTransmitter") then
            local name = part.Name:lower()
            if name:find("tele") or name:find("portal") or name:find("door") or name:find("entrance")
                or name:find("gate") then
                local key = math.floor(part.Position.X / 20) .. "," .. math.floor(part.Position.Z / 20)
                if not seen[key] and #scanned < 40 then
                    seen[key] = true
                    local label = (part.Parent and part.Parent.Name or "?") .. "." .. part.Name
                    local position = part.Position
                    scanned[#scanned + 1] = row("[scan] " .. label, Color3.fromRGB(60, 90, 160), function()
                        flyTo(label, position)
                    end)
                end
            end
        end
    end
    pcall(function()
        for _, part in ipairs(game:GetService("CollectionService"):GetTagged("BoatCastleTeleporter")) do
            if part:IsA("BasePart") and #scanned < 40 then
                local label = "tag " .. part:GetFullName()
                local position = part.Position
                scanned[#scanned + 1] = row("[scan] " .. label, Color3.fromRGB(60, 90, 160), function()
                    flyTo(label, position)
                end)
            end
        end
    end)
    add("Scan: " .. #scanned .. " portal-like trigger parts listed")
end

row("Sea " .. sea .. " - Stop flight", Color3.fromRGB(120, 30, 30), function()
    stopFlight()
    add("Flight stopped")
end)
row("Scan the map for portals", Color3.fromRGB(40, 120, 60), scan)
for _, spot in ipairs(SPOTS[sea] or {}) do
    row(spot[1], Color3.fromRGB(70, 70, 70), function() flyTo(spot[1], spot[2]) end)
end
local oldStop = stop
stop = function()
    stopFlight()
    oldStop()
end
env.StrawberryPortalLog = stop
add("Recording. Walk through the portals; press Mark before each one, Copy at the end.")
