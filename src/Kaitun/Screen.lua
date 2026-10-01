--=============================================================================
-- KAITUN SCREEN — a small red status panel
--=============================================================================
--  No window to drive: the Kaitun only shows what it is doing. Plain
--  Instances (no library to download), draggable by the title, hidden and
--  shown with RightControl.
--=============================================================================

local Engine = require("Kaitun.Engine")
local Farm = require("Features.Farm")
local Loop = require("Core.Loop")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Tasks = require("Kaitun.Tasks")

local Screen = {}

Screen.EVERY = 1
Screen.TOGGLE_KEY = "RightControl"

local RED = Color3.fromRGB(220, 38, 64)
local DARK = Color3.fromRGB(24, 16, 20)
local TEXT = Color3.fromRGB(245, 235, 238)
local MUTED = Color3.fromRGB(190, 150, 160)

local gui, labels, connections = nil, {}, {}
local startedAt = os.clock()

local function label(parent, name, y, size, color, bold)
    local text = Instance.new("TextLabel")
    text.Name = name
    text.BackgroundTransparency = 1
    text.Position = UDim2.new(0, 12, 0, y)
    text.Size = UDim2.new(1, -24, 0, size + 4)
    text.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    text.TextSize = size
    text.TextColor3 = color or TEXT
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.TextWrapped = true
    text.Text = ""
    text.Parent = parent
    labels[name] = text
    return text
end

local ROWS = { "Task", "Status", "Level", "Money", "Melee", "Items", "Resting", "Last" }

function Screen.build()
    Screen.destroy()
    labels = {}
    gui = Instance.new("ScreenGui")
    gui.Name = "StrawberryKaitun"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end

    local frame = Instance.new("Frame")
    frame.Name = "Panel"
    frame.Size = UDim2.fromOffset(330, 52 + #ROWS * 22)
    frame.Position = UDim2.new(0, 16, 0, 80)
    frame.BackgroundColor3 = DARK
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = RED
    stroke.Thickness = 1.5
    stroke.Parent = frame

    local bar = Instance.new("Frame")
    bar.Name = "Title"
    bar.Size = UDim2.new(1, 0, 0, 34)
    bar.BackgroundColor3 = RED
    bar.BorderSizePixel = 0
    bar.Parent = frame
    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 10)
    barCorner.Parent = bar
    label(bar, "Header", 8, 16, TEXT, true).Text = "🍓 Strawberry Kaitun"

    for index, name in ipairs(ROWS) do
        label(frame, name, 40 + (index - 1) * 22, 13, index <= 2 and TEXT or MUTED, index == 1)
    end

    -- Drag by the title bar.
    local dragging, dragStart, startPosition
    connections[#connections + 1] = bar.InputBegan:Connect(function(event)
        local kind = event.UserInputType
        if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
            dragging, dragStart, startPosition = true, event.Position, frame.Position
        end
    end)
    connections[#connections + 1] = bar.InputEnded:Connect(function(event)
        local kind = event.UserInputType
        if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then dragging = false end
    end)
    local input = Services.get("UserInputService")
    connections[#connections + 1] = input.InputChanged:Connect(function(event)
        if not dragging then return end
        local kind = event.UserInputType
        if kind ~= Enum.UserInputType.MouseMovement and kind ~= Enum.UserInputType.Touch then return end
        local delta = event.Position - dragStart
        frame.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
    end)
    connections[#connections + 1] = input.InputBegan:Connect(function(event, processed)
        if processed then return end
        if event.KeyCode == Enum.KeyCode[Screen.TOGGLE_KEY] then frame.Visible = not frame.Visible end
    end)

    gui.Parent = Services.guiParent()
    Screen.update()
    return gui
end

local function short(number)
    number = tonumber(number) or 0
    if number >= 1e6 then return string.format("%.1fM", number / 1e6) end
    if number >= 1e3 then return string.format("%.1fk", number / 1e3) end
    return tostring(math.floor(number))
end

local function uptime()
    local seconds = math.floor(os.clock() - startedAt)
    return string.format("%dh%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

-- The rows' text, separate from the Instances so tests can read it.
function Screen.lines()
    local status = Engine.status()
    local melee = Player.findTool("Melee")
    local level = melee and melee:FindFirstChild("Level")
    local items = {}
    for _, entry in ipairs(Tasks.CHECKLIST) do
        local ok, has = pcall(Tasks.owned, entry.item)
        items[#items + 1] = ((ok and has) and "✔ " or "✘ ") .. entry.label
    end
    return {
        Task = "Task: " .. (status.task or ("idle -- " .. tostring(status.idle))),
        Status = "Now: " .. tostring(Farm.status()),
        Level = string.format("Level %s  ·  Sea %s  ·  up %s", tostring(Player.level()), tostring(Player.sea()), uptime()),
        Money = string.format("Beli %s  ·  Fragments %s", short(Player.data("Beli")), short(Player.data("Fragments"))),
        Melee = "Melee: " .. (melee and (melee.Name .. (level and (" " .. tostring(level.Value)) or "")) or "none"),
        Items = table.concat(items, "  "),
        Resting = "Resting: " .. (#status.resting > 0 and table.concat(status.resting, ", ") or "none"),
        Last = status.log[1] or "",
    }
end

function Screen.update()
    if not gui then return end
    local ok, lines = pcall(Screen.lines)
    if not ok then return end
    for name, text in pairs(lines) do
        if labels[name] then labels[name].Text = text end
    end
end

function Screen.start()
    Screen.build()
    Loop.start("KaitunScreen", Screen.EVERY, Screen.update)
end

function Screen.gui()
    return gui
end

function Screen.destroy()
    Loop.stop("KaitunScreen")
    for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    connections = {}
    if gui then pcall(function() gui:Destroy() end) end
    gui = nil
end

return Screen
