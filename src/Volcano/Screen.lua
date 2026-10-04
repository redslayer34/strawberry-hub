--=============================================================================
-- VOLCANO SCREEN — what the Volcano script is doing, over the game
--=============================================================================
--  The Kaitun panel's look, smaller and lighter so the island stays in
--  view: name, running time, the current step, then boxes for the island,
--  the magnet and the loot. Clicks go through to the game and RightControl
--  hides or shows it. Plain Instances: nothing to download.
--=============================================================================

local Engine = require("Volcano.Engine")
local Loop = require("Core.Loop")
local Services = require("Core.Services")

local Screen = {}

Screen.EVERY = 1
Screen.TOGGLE_KEY = "RightControl"
Screen.TINT = 0.78             -- background transparency of the full-screen tint

local RED = Color3.fromRGB(230, 46, 76)
local PINK = Color3.fromRGB(255, 128, 150)
local SOFT = Color3.fromRGB(255, 205, 214)
local TEXT = Color3.fromRGB(250, 240, 242)
local MUTED = Color3.fromRGB(205, 170, 178)
local BOX = Color3.fromRGB(28, 14, 20)
local TINT = Color3.fromRGB(16, 6, 10)

local gui, labels, connections, dots = nil, {}, {}, {}
local startedAt, tick = os.clock(), 0

local function clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = radius or UDim.new(0, 10)
    c.Parent = parent
end

local function stroke(parent, color)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = 1
    s.Transparency = 0.45
    s.Parent = parent
end

-- A centred line of text `width` wide at `y`.
local function text(parent, name, y, height, size, color, font, width)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.AnchorPoint = Vector2.new(0.5, 0)
    label.Position = UDim2.new(0.5, 0, 0, y)
    label.Size = UDim2.new(0, width or 620, 0, height)
    label.BackgroundTransparency = 1
    label.Font = font or Enum.Font.Arcade
    label.TextSize = size
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.6
    label.TextWrapped = true
    label.Text = ""
    label.Parent = parent
    labels[name] = label
    return label
end

-- A dark rounded box with a line of text, part of a row.
local function box(parent, name, x, y, width)
    local frame = Instance.new("Frame")
    frame.Name = name .. "Box"
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.Position = UDim2.new(0.5, x, 0, y)
    frame.Size = UDim2.new(0, width, 0, 32)
    frame.BackgroundColor3 = BOX
    frame.BackgroundTransparency = 0.25
    frame.BorderSizePixel = 0
    frame.Parent = parent
    corner(frame, UDim.new(0, 8))
    stroke(frame, RED)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Size = UDim2.new(1, -12, 1, 0)
    label.Position = UDim2.new(0, 6, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Arcade
    label.TextSize = 14
    label.TextColor3 = SOFT
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Text = ""
    label.Parent = frame
    labels[name] = label
    return frame
end

function Screen.build()
    Screen.destroy()
    labels, dots = {}, {}
    startedAt = os.clock()

    gui = Instance.new("ScreenGui")
    gui.Name = "StrawberryVolcano"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 10
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end

    -- The tint over the whole screen. Not Active: clicks reach the game.
    local tint = Instance.new("Frame")
    tint.Name = "Tint"
    tint.Size = UDim2.new(1, 0, 1, 0)
    tint.BackgroundColor3 = TINT
    tint.BackgroundTransparency = Screen.TINT
    tint.BorderSizePixel = 0
    tint.Active = false
    tint.Parent = gui

    local center = Instance.new("Frame")
    center.Name = "Center"
    center.AnchorPoint = Vector2.new(0.5, 0.5)
    center.Position = UDim2.new(0.5, 0, 0.5, 0)
    center.Size = UDim2.new(0, 640, 0, 300)
    center.BackgroundTransparency = 1
    center.Parent = tint
    -- Smaller screens (phones): the block shrinks to fit.
    local scale = Instance.new("UIScale")
    scale.Parent = center
    pcall(function()
        local size = workspace.CurrentCamera.ViewportSize
        scale.Scale = math.clamp(math.min(size.X / 680, size.Y / 320), 0.55, 1.2)
    end)

    text(center, "Title", 0, 40, 32, PINK).Text = "🌋 Strawberry Volcano"

    local bar = Instance.new("Frame")
    bar.Name = "Underline"
    bar.AnchorPoint = Vector2.new(0.5, 0)
    bar.Position = UDim2.new(0.5, 0, 0, 42)
    bar.Size = UDim2.new(0, 240, 0, 3)
    bar.BackgroundColor3 = RED
    bar.BorderSizePixel = 0
    bar.Parent = center
    corner(bar, UDim.new(1, 0))

    text(center, "Running", 54, 22, 18, SOFT)
    text(center, "Time", 76, 16, 13, MUTED)

    for index = 1, 3 do
        local dot = Instance.new("Frame")
        dot.Name = "Dot" .. index
        dot.AnchorPoint = Vector2.new(0.5, 0)
        dot.Position = UDim2.new(0.5, (index - 2) * 16, 0, 96)
        dot.Size = UDim2.new(0, 8, 0, 8)
        dot.BackgroundColor3 = RED
        dot.BorderSizePixel = 0
        dot.Parent = center
        corner(dot, UDim.new(1, 0))
        dots[index] = dot
    end

    text(center, "Step", 112, 36, 15, TEXT, Enum.Font.GothamBold)

    box(center, "Island", -160, 156, 300)
    box(center, "Counts", 160, 156, 300)
    box(center, "Magnet", 0, 196, 620)
    box(center, "Eggs", -160, 236, 300)
    box(center, "Bones", 160, 236, 300)

    text(center, "Last", 278, 16, 12, MUTED, Enum.Font.Gotham)

    local input = Services.get("UserInputService")
    connections[#connections + 1] = input.InputBegan:Connect(function(event, processed)
        if processed then return end
        if event.KeyCode == Enum.KeyCode[Screen.TOGGLE_KEY] then tint.Visible = not tint.Visible end
    end)

    gui.Parent = Services.guiParent()
    return gui
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

-- Each line on its own: one that fails shows "?" and the error goes in the
-- last line, instead of every line staying empty.
local screenError
local function safe(fn)
    local ok, value = pcall(fn)
    if ok then return tostring(value) end
    screenError = screenError or tostring(value)
    return "?"
end

-- The text of every line, separate from the Instances so tests can read it.
function Screen.lines()
    screenError = nil
    local ok, status = pcall(Engine.status)
    if not ok or type(status) ~= "table" then
        screenError = tostring(status)
        status = { log = {} }
    end
    local lines = {
        Running = "Volcano Running" .. string.rep(".", tick % 3 + 1),
        Time = "Time: " .. clock(os.clock() - startedAt),
        Step = safe(function() return status.step or "Starting" end),
        Island = safe(function() return "Island: " .. tostring(status.island or "?") end),
        Counts = safe(function()
            return string.format("Islands %d  ·  Events %d", status.islands or 0, status.events or 0)
        end),
        Magnet = safe(function() return "Volcanic Magnet: " .. tostring(status.magnet or "?") end),
        Eggs = safe(function()
            return string.format("Dragon Eggs: %d  (+%d)", status.eggs or 0, status.eggsGained or 0)
        end),
        Bones = safe(function() return "Dino Bones: " .. tostring(status.bones or 0) end),
        Last = safe(function() return status.log[1] or "" end),
    }
    if screenError then lines.Last = "screen error: " .. screenError end
    return lines
end

function Screen.update()
    if not gui then return end
    tick = tick + 1
    for index, dot in ipairs(dots) do
        dot.BackgroundTransparency = (index == tick % 3 + 1) and 0 or 0.6
    end
    local ok, lines = pcall(Screen.lines)
    if ok then
        for name, value in pairs(lines) do
            if labels[name] then labels[name].Text = value end
        end
    end
end

function Screen.start()
    Screen.build()
    Loop.start("VolcanoScreen", Screen.EVERY, Screen.update)
end

function Screen.gui()
    return gui
end

function Screen.destroy()
    Loop.stop("VolcanoScreen")
    for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    connections = {}
    if gui then pcall(function() gui:Destroy() end) end
    gui = nil
end

return Screen
