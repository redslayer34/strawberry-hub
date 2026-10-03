-- Temporary: records what happens while you go through the portals by hand.
--   remote calls (FireServer / InvokeServer, with the answer), teleports
--   (where from, where to, what was near), touched trigger parts, prompts.
-- The full log goes to StrawberryHub/portal_log.txt; "Copy" puts it on the
-- clipboard. Run it once, then walk through every portal.
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
button("Stop", 200, stop)
add("Recording. Walk through the portals; press Mark before each one, Copy at the end.")
