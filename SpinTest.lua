-- Temporary: the Cousin's fruit spin, every answer shown on screen.
-- v2: from afar the game answers nil (v30); this one flies to the Cousin,
-- opens his dialogue (his prompt), then asks again.
local rs = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local player = game:GetService("Players").LocalPlayer
local commF = rs:WaitForChild("Remotes"):WaitForChild("CommF_")

local gui = Instance.new("ScreenGui")
gui.Name = "StrawberrySpinTest"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
local label = Instance.new("TextLabel")
label.Size = UDim2.new(0, 520, 0, 330)
label.Position = UDim2.new(0.5, -260, 0, 40)
label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
label.BackgroundTransparency = 0.2
label.TextColor3 = Color3.new(1, 1, 1)
label.TextSize = 14
label.Font = Enum.Font.Code
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.TextWrapped = true
label.Parent = gui

local lines = {}
local function say(text)
    lines[#lines + 1] = text
    while #lines > 20 do table.remove(lines, 1) end
    label.Text = table.concat(lines, "\n")
    print("[SpinTest] " .. text)
end
local function show(...)
    local out = {}
    for i = 1, select("#", ...) do out[i] = tostring((select(i, ...))) end
    return table.concat(out, ", ")
end
local function root() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end

local box = "DLCBoxData"
pcall(function()
    local item = require(rs.Controllers.BannerClient).TryGetBannerItemIfActiveAsync()
    if type(item) == "table" and item.BoxName then box = item.BoxName end
end)

local function ask(tag)
    say(tag .. " Check:     " .. show(pcall(commF.InvokeServer, commF, "Cousin", "Check", box)))
    say(tag .. " CheckTime: " .. show(pcall(commF.InvokeServer, commF, "Cousin", "CheckTime", box)))
end

say("Box " .. box .. ", Beli " .. tostring(player.Data.Beli.Value))
ask("[far]")

-- The Cousin: an NPC whose name says Cousin or Gacha.
local cousin, cousinPos
for _, folder in ipairs({ workspace:FindFirstChild("NPCs"), rs:FindFirstChild("NPCs") }) do
    for _, npc in ipairs(folder and folder:GetChildren() or {}) do
        local name = npc.Name:lower()
        if (name:find("cousin") or name:find("gacha")) and npc:FindFirstChild("HumanoidRootPart") then
            local pos = npc.HumanoidRootPart.Position
            local here = root()
            if not cousinPos or (here and (here.Position - pos).Magnitude < (here.Position - cousinPos).Magnitude) then
                cousin, cousinPos = npc.Name, pos
            end
        end
    end
end
if not cousin then
    local names = {}
    for _, folder in ipairs({ workspace:FindFirstChild("NPCs"), rs:FindFirstChild("NPCs") }) do
        for _, npc in ipairs(folder and folder:GetChildren() or {}) do
            if npc.Name:lower():find("fruit") then names[#names + 1] = npc.Name end
        end
    end
    say("No Cousin / Gacha NPC. Fruit NPCs: " .. table.concat(names, " | "))
    return
end
say(string.format("NPC '%s' at %d, %d, %d", cousin, cousinPos.X, cousinPos.Y, cousinPos.Z))

-- Flight there (300 studs/s, no collisions, no falling).
local hrp = root()
local noclip = RunService.Stepped:Connect(function()
    for _, part in ipairs(player.Character and player.Character:GetDescendants() or {}) do
        if part:IsA("BasePart") then part.CanCollide = false end
    end
end)
local hold = Instance.new("BodyVelocity")
hold.MaxForce = Vector3.new(9e9, 9e9, 9e9)
hold.Velocity = Vector3.new()
hold.Parent = hrp
local goal = CFrame.new(cousinPos + Vector3.new(0, 1.5, 4))
say(string.format("Flying %d studs...", (hrp.Position - goal.Position).Magnitude))
local tween = TweenService:Create(hrp, TweenInfo.new((hrp.Position - goal.Position).Magnitude / 300,
    Enum.EasingStyle.Linear), { CFrame = goal })
tween:Play()
tween.Completed:Wait()
task.wait(2)
noclip:Disconnect()

ask("[near]")

-- His prompt, held like a player's Interact.
local best, bestDistance
for _, folder in ipairs({ workspace:FindFirstChild("NPCs"), workspace:FindFirstChild("Map") }) do
    for _, node in ipairs(folder and folder:GetDescendants() or {}) do
        if node:IsA("ProximityPrompt") then
            local parent = node.Parent
            local at = parent and (parent:IsA("Attachment") and parent.WorldPosition
                or parent:IsA("BasePart") and parent.Position
                or parent:IsA("Model") and parent:GetPivot().Position)
            local distance = at and (at - cousinPos).Magnitude
            if distance and distance < 20 and (not bestDistance or distance < bestDistance) then
                best, bestDistance = node, distance
            end
        end
    end
end
if best then
    say(string.format("Prompt '%s' / '%s' (%s), holding", best.ActionText, best.ObjectText, best:GetFullName()))
    local ok = pcall(function()
        best:InputHoldBegin()
        task.wait((tonumber(best.HoldDuration) or 0) + 0.35)
        best:InputHoldEnd()
    end)
    if not ok and fireproximityprompt then pcall(fireproximityprompt, best) end
    task.wait(1.5)
else
    say("No prompt within 20 studs of the Cousin")
end

ask("[dialog]")
say("[dialog] Roll:      " .. show(pcall(commF.InvokeServer, commF, "Cousin", box)))
hold:Destroy()
say("(closes in 90 s)")
task.delay(90, function() gui:Destroy() end)
