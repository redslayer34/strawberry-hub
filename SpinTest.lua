-- Temporary: one fruit spin through the v30 gacha remote, answers on screen.
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players").LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "StrawberrySpinTest"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
local label = Instance.new("TextLabel")
label.Size = UDim2.new(0, 480, 0, 220)
label.Position = UDim2.new(0.5, -240, 0, 60)
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
local function describe(value, depth)
    if type(value) ~= "table" then return tostring(value) end
    if (depth or 0) > 1 then return "{..}" end
    local parts = {}
    for key, inner in pairs(value) do parts[#parts + 1] = tostring(key) .. "=" .. describe(inner, (depth or 0) + 1) end
    return "{" .. table.concat(parts, " ") .. "}"
end

local box = "ZiolesGacha"
pcall(function()
    local item = require(rs.Controllers.BannerClient).TryGetBannerItemIfActiveAsync()
    if type(item) == "table" and item.BoxName then box = item.BoxName end
end)
local remote = rs.Modules.Net:FindFirstChild("RF/GachaNetworkRF")
say("Remote: " .. tostring(remote and remote:GetFullName()) .. ", box " .. box)
if not remote then return end

local beli = player.Data.Beli.Value
say("Beli before: " .. tostring(beli))
local ok, result = pcall(function() return remote:InvokeServer({ Context = "Purchase", BoxName = box }) end)
say("Purchase: " .. tostring(ok) .. ", " .. describe(result))
task.wait(2)
say("Beli after:  " .. tostring(player.Data.Beli.Value) .. " (" .. tostring(player.Data.Beli.Value - beli) .. ")")
say("(closes in 60 s)")
task.delay(60, function() gui:Destroy() end)
