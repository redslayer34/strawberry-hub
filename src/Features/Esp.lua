--=============================================================================
-- ESP — labels over fruits, berries, islands and players
--=============================================================================
--  The reference draws with the executor's Drawing library, which several
--  mobile executors lack. Here each label is a BillboardGui adorned to the
--  object (always on top), kept in one ScreenGui under the executor's hidden
--  GUI container, and refreshed twice a second: new objects get a label,
--  labels of objects gone or of categories turned off are removed.
--=============================================================================

local Loop = require("Core.Loop")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Esp = {}

Esp.REFRESH = 0.5

-- Fruit models on the ground only carry their mesh: its id says which fruit.
Esp.FRUIT_MESHES = {
    ["rbxassetid://15100283484"] = "Light Fruit",
    ["rbxassetid://15116730102"] = "Love Fruit",
    ["rbxassetid://15100273645"] = "Dough Fruit",
    ["rbxassetid://15116967784"] = "Spider Fruit",
    ["rbxassetid://15112263502"] = "Shadow Fruit",
    ["rbxassetid://15104782377"] = "Blade Fruit",
    ["rbxassetid://15060012861"] = "Rocket Fruit",
    ["rbxassetid://15106768588"] = "Leopard Fruit",
    ["rbxassetid://15112469964"] = "Falcon Fruit",
    ["rbxassetid://15708895165"] = "T-Rex Fruit",
    ["rbxassetid://19001642259"] = "Dragon (East) Fruit",
    ["rbxassetid://86024571204851"] = "Gas Fruit",
    ["rbxassetid://15100246632"] = "Phoenix Fruit",
    ["rbxassetid://14661873358"] = "Sound Fruit",
    ["rbxassetid://15111584216"] = "Flame Fruit",
    ["rbxassetid://15105281957"] = "Spring Fruit",
    ["rbxassetid://15116740364"] = "Bomb Fruit",
    ["rbxassetid://15104817760"] = "Rubber Fruit",
    ["rbxassetid://15057683975"] = "Spin Fruit",
    ["rbxassetid://15105350415"] = "Magma Fruit",
    ["rbxassetid://15482881956"] = "Kitsune Fruit",
    ["rbxassetid://15100485671"] = "Barrier Fruit",
    ["rbxassetid://18955022385"] = "Dragon (West) Fruit",
    ["rbxassetid://101378450824208"] = "Yeti Fruit",
    ["rbxassetid://15116721173"] = "Pain Fruit",
    ["https://assetdelivery.roblox.com/v1/asset/?id=10395893751"] = "Venom Fruit",
    ["rbxassetid://11908375285"] = "Spirit Fruit",
    ["rbxassetid://15100433167"] = "Ice Fruit",
    ["rbxassetid://15100299740"] = "Gravity Fruit",
    ["rbxassetid://15107005807"] = "Spike Fruit",
    ["rbxassetid://15116696973"] = "Smoke Fruit",
    ["rbxassetid://15112600534"] = "Diamond Fruit",
    ["rbxassetid://15112333093"] = "Ghost Fruit",
    ["rbxassetid://15057718441"] = "Quake Fruit",
    ["rbxassetid://15111517529"] = "Sand Fruit",
    ["rbxassetid://15100313696"] = "Buddha Fruit",
    ["rbxassetid://15116747420"] = "Rumble Fruit",
    ["rbxassetid://15100384816"] = "Blizzard Fruit",
    ["rbxassetid://15111553409"] = "Dark Fruit",
    ["rbxassetid://14661837634"] = "Mammoth Fruit",
    ["rbxassetid://15100184583"] = "Control Fruit",
}

Esp.FRUIT_COLOURS = {
    ["Leopard Fruit"] = Color3.fromRGB(255, 170, 0),
    ["Dragon (East) Fruit"] = Color3.fromRGB(255, 0, 0),
    ["Dragon (West) Fruit"] = Color3.fromRGB(255, 80, 80),
    ["Kitsune Fruit"] = Color3.fromRGB(200, 100, 255),
    ["Spirit Fruit"] = Color3.fromRGB(120, 200, 255),
    ["Venom Fruit"] = Color3.fromRGB(180, 60, 200),
    ["Dough Fruit"] = Color3.fromRGB(255, 220, 180),
    ["Light Fruit"] = Color3.fromRGB(255, 255, 150),
}

local WHITE = Color3.fromRGB(255, 255, 255)
local BERRY = Color3.fromRGB(255, 110, 180)
local ISLAND = Color3.fromRGB(150, 220, 255)
local ENEMY = Color3.fromRGB(255, 90, 90)
local ALLY = Color3.fromRGB(110, 255, 140)

local screen
local labels = {}   -- [object] = { gui = BillboardGui, text = TextLabel }

---------------------------------------------------------------------------
-- What to label
---------------------------------------------------------------------------

function Esp.fruitName(model)
    if model:IsA("Tool") then return model.Name end
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("MeshPart") then
            local name = Esp.FRUIT_MESHES[tostring(part.MeshId)]
            if name then return name end
        end
    end
    return "Fruit"
end

local function adornee(node)
    if node:IsA("BasePart") then return node end
    return node:FindFirstChildWhichIsA("BasePart", true)
end

local function distanceText(part)
    return " [" .. math.floor(Player.distanceTo(part.Position)) .. "m]"
end

local function fruits(out)
    for _, child in ipairs(workspace:GetChildren()) do
        local handle = (child:IsA("Tool") or child:IsA("Model")) and child.Name:find("Fruit", 1, true)
            and child:FindFirstChild("Handle")
        if handle then
            local name = Esp.fruitName(child)
            out[child] = { part = handle, text = name .. distanceText(handle), colour = Esp.FRUIT_COLOURS[name] or WHITE }
        end
    end
end

local function berries(out)
    local ok, bushes = pcall(function() return Services.get("CollectionService"):GetTagged("BerryBush") end)
    for _, bush in ipairs(ok and bushes or {}) do
        local okAttributes, attributes = pcall(function() return bush:GetAttributes() end)
        if okAttributes and type(attributes) == "table" and next(attributes) then
            local part = adornee(bush) or (bush.Parent and adornee(bush.Parent))
            if part then
                local berry = next(attributes)
                out[bush] = { part = part, text = tostring(berry) .. distanceText(part), colour = BERRY }
            end
        end
    end
end

local function islands(out)
    local locations = Services.find(workspace, "_WorldOrigin.Locations")
    for _, location in ipairs(locations and locations:GetChildren() or {}) do
        local part = adornee(location)
        if part then
            out[location] = { part = part, text = location.Name .. distanceText(part), colour = ISLAND }
        end
    end
end

local function players(out)
    local me = Services.player()
    for _, player in ipairs(Services.get("Players"):GetPlayers()) do
        local character = player ~= me and player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local health = humanoid and humanoid.MaxHealth and humanoid.MaxHealth > 0
                and math.floor(humanoid.Health / humanoid.MaxHealth * 100) or 0
            local data = player:FindFirstChild("Data")
            local level = data and data:FindFirstChild("Level")
            local text = string.format("%s [Lv %s] %d%%", player.Name, level and tostring(level.Value) or "?", health)
            local ally = me and me.Team ~= nil and player.Team == me.Team
            out[character] = { part = root, text = text .. distanceText(root), colour = ally and ALLY or ENEMY }
        end
    end
end

Esp.CATEGORIES = {
    { key = "EspFruit", collect = fruits },
    { key = "EspBerry", collect = berries },
    { key = "EspIsland", collect = islands },
    { key = "EspPlayer", collect = players },
}

-- Everything that should carry a label right now.
function Esp.targets()
    local out = {}
    for _, category in ipairs(Esp.CATEGORIES) do
        if Settings.get(category.key) then pcall(category.collect, out) end
    end
    return out
end

---------------------------------------------------------------------------
-- Labels
---------------------------------------------------------------------------

local function container()
    if screen and screen.Parent then return screen end
    screen = Instance.new("ScreenGui")
    screen.Name = "StrawberryESP"
    screen.ResetOnSpawn = false
    if syn and syn.protect_gui then pcall(syn.protect_gui, screen) end
    screen.Parent = Services.guiParent()
    return screen
end

local function newLabel(part)
    local gui = Instance.new("BillboardGui")
    gui.Name = "Label"
    gui.AlwaysOnTop = true
    gui.Size = UDim2.fromOffset(220, 36)
    gui.StudsOffset = Vector3.new(0, 3, 0)
    gui.Adornee = part
    local text = Instance.new("TextLabel")
    text.BackgroundTransparency = 1
    text.Size = UDim2.new(1, 0, 1, 0)
    text.TextStrokeTransparency = 0
    text.TextSize = 14
    text.Font = Enum.Font.GothamBold
    text.Parent = gui
    gui.Parent = container()
    return { gui = gui, text = text }
end

function Esp.refresh()
    local wanted = Esp.targets()
    for object, label in pairs(labels) do
        if not wanted[object] then
            pcall(function() label.gui:Destroy() end)
            labels[object] = nil
        end
    end
    for object, target in pairs(wanted) do
        local label = labels[object]
        if not label or label.gui.Adornee ~= target.part then
            if label then pcall(function() label.gui:Destroy() end) end
            label = newLabel(target.part)
            labels[object] = label
        end
        label.text.Text = target.text
        label.text.TextColor3 = target.colour
    end
end

function Esp.count()
    local n = 0
    for _ in pairs(labels) do n = n + 1 end
    return n
end

function Esp.start()
    Loop.start("ESP", Esp.REFRESH, Esp.refresh)
end

function Esp.destroy()
    Loop.stop("ESP")
    for object, label in pairs(labels) do
        pcall(function() label.gui:Destroy() end)
        labels[object] = nil
    end
    if screen then pcall(function() screen:Destroy() end) end
    screen = nil
end

return Esp
