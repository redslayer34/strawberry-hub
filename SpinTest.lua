-- Temporary: one Cousin fruit spin, every answer shown on screen.
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players").LocalPlayer
local commF = rs:WaitForChild("Remotes"):WaitForChild("CommF_")

local gui = Instance.new("ScreenGui")
gui.Name = "StrawberrySpinTest"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
local label = Instance.new("TextLabel")
label.Size = UDim2.new(0, 420, 0, 260)
label.Position = UDim2.new(0.5, -210, 0, 60)
label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
label.BackgroundTransparency = 0.2
label.TextColor3 = Color3.new(1, 1, 1)
label.TextSize = 15
label.Font = Enum.Font.Code
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.TextWrapped = true
label.Parent = gui

local lines = {}
local function say(text)
    lines[#lines + 1] = text
    label.Text = table.concat(lines, "\n")
    print("[SpinTest] " .. text)
end
local function show(...)
    local out = {}
    for i = 1, select("#", ...) do out[i] = tostring((select(i, ...))) end
    return table.concat(out, ", ")
end

local box = "DLCBoxData"
local ok, banner = pcall(require, rs.Controllers.BannerClient)
if ok and type(banner) == "table" and banner.TryGetBannerItemIfActiveAsync then
    local got, item = pcall(banner.TryGetBannerItemIfActiveAsync)
    if got and type(item) == "table" and item.BoxName then box = item.BoxName end
    say("Banner: " .. tostring(got) .. " box " .. box)
else
    say("BannerClient: " .. tostring(banner))
end

say("Level " .. tostring(player.Data.Level.Value) .. ", Beli " .. tostring(player.Data.Beli.Value))
say("Check:     " .. show(pcall(commF.InvokeServer, commF, "Cousin", "Check", box)))
say("CheckTime: " .. show(pcall(commF.InvokeServer, commF, "Cousin", "CheckTime", box)))
say("Roll:      " .. show(pcall(commF.InvokeServer, commF, "Cousin", box)))
if box ~= "DLCBoxData" then
    say("Roll DLC:  " .. show(pcall(commF.InvokeServer, commF, "Cousin", "DLCBoxData")))
end
say("(closes in 60 s)")
task.delay(60, function() gui:Destroy() end)
