--=============================================================================
-- KAITUN SCREEN — full screen, see-through, text on top
--=============================================================================
--  No window to drive: the Kaitun only shows what it is doing. The whole
--  screen gets a light tint with the information centred on it (the layout
--  of the other Kaituns: logo, name, running time, three stat boxes). Fixed
--  in place, it lets clicks through to the game, and RightControl hides or
--  shows it. Plain Instances: nothing to download.
--
--  The total running time is kept per account in the executor's workspace,
--  so it carries on across server hops and restarts.
--=============================================================================

local Config = require("Kaitun.Config")
local Engine = require("Kaitun.Engine")
local Farm = require("Features.Farm")
local Fruits = require("Features.Fruits")
local Logo = require("UI.Logo")
local Loop = require("Core.Loop")
local Melee = require("Features.Items.Melee")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Tasks = require("Kaitun.Tasks")

local Screen = {}

Screen.EVERY = 1
Screen.SAVE_EVERY = 30
Screen.TOGGLE_KEY = "RightControl"
Screen.TINT = 0.55             -- background transparency of the full-screen tint
Screen.FOLDER = "StrawberryHub"

local RED = Color3.fromRGB(230, 46, 76)
local PINK = Color3.fromRGB(255, 128, 150)
local SOFT = Color3.fromRGB(255, 205, 214)
local TEXT = Color3.fromRGB(250, 240, 242)
local MUTED = Color3.fromRGB(205, 170, 178)
local BOX = Color3.fromRGB(28, 14, 20)
local TINT = Color3.fromRGB(16, 6, 10)

local gui, labels, connections, dots = nil, {}, {}, {}
local startedAt = os.clock()
local totalBefore, lastSave, tick = 0, os.clock(), 0

---------------------------------------------------------------------------
-- Total time (per account, in the workspace)
---------------------------------------------------------------------------

local function timeFile()
    local player = Services.player()
    return Screen.FOLDER .. "/kaitun_time_" .. tostring(player and player.UserId or 0) .. ".txt"
end

local function loadTotal()
    local ok, seconds = pcall(function()
        if not (isfile and readfile and isfile(timeFile())) then return 0 end
        return tonumber(readfile(timeFile())) or 0
    end)
    return ok and seconds or 0
end

local function saveTotal()
    pcall(function()
        if not writefile then return end
        if makefolder and isfolder and not isfolder(Screen.FOLDER) then makefolder(Screen.FOLDER) end
        writefile(timeFile(), tostring(math.floor(totalBefore + os.clock() - startedAt)))
    end)
end

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

local function stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.Parent = parent
end

-- A centred line of text `width` wide at `y`.
local function text(parent, name, y, height, size, color, font, width)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.AnchorPoint = Vector2.new(0.5, 0)
    label.Position = UDim2.new(0.5, 0, 0, y)
    label.Size = UDim2.new(0, width or 640, 0, height)
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
    frame.Size = UDim2.new(0, width, 0, 34)
    frame.BackgroundColor3 = BOX
    frame.BackgroundTransparency = 0.25
    frame.BorderSizePixel = 0
    frame.Parent = parent
    corner(frame, UDim.new(0, 8))
    stroke(frame, RED, 1, 0.45)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Size = UDim2.new(1, -12, 1, 0)
    label.Position = UDim2.new(0, 6, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Arcade
    label.TextSize = 15
    label.TextColor3 = SOFT
    label.TextScaled = false
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Text = ""
    label.Parent = frame
    labels[name] = label
    return frame
end

function Screen.build()
    Screen.destroy()
    labels, dots = {}, {}
    totalBefore, startedAt, lastSave = loadTotal(), os.clock(), os.clock()

    gui = Instance.new("ScreenGui")
    gui.Name = "StrawberryKaitun"
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
    center.Size = UDim2.new(0, 660, 0, 470)
    center.BackgroundTransparency = 1
    center.Parent = tint
    -- Smaller screens (phones): the block shrinks to fit.
    local scale = Instance.new("UIScale")
    scale.Parent = center
    pcall(function()
        local size = workspace.CurrentCamera.ViewportSize
        scale.Scale = math.clamp(math.min(size.X / 700, size.Y / 480), 0.55, 1.2)
    end)

    -- Logo: a white disc with the strawberry, red ring.
    local logo = Instance.new("Frame")
    logo.Name = "Logo"
    logo.AnchorPoint = Vector2.new(0.5, 0)
    logo.Position = UDim2.new(0.5, 0, 0, 0)
    logo.Size = UDim2.new(0, 104, 0, 104)
    logo.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    logo.BorderSizePixel = 0
    logo.Parent = center
    corner(logo, UDim.new(1, 0))
    stroke(logo, RED, 3)
    -- The pixel strawberry when the executor can show a local image, the
    -- emoji otherwise.
    local image = Logo.asset()
    if image then
        local berry = Instance.new("ImageLabel")
        berry.Name = "Berry"
        berry.AnchorPoint = Vector2.new(0.5, 0)
        berry.Position = UDim2.new(0.5, 0, 0.08, 0)
        berry.Size = UDim2.new(0.56, 0, 0.56, 0)
        berry.BackgroundTransparency = 1
        berry.Image = image
        berry.ScaleType = Enum.ScaleType.Fit
        pcall(function() berry.ResampleMode = Enum.ResamplerMode.Pixelated end)
        berry.Parent = logo
    else
        local berry = Instance.new("TextLabel")
        berry.Name = "Berry"
        berry.Size = UDim2.new(1, 0, 0.7, 0)
        berry.BackgroundTransparency = 1
        berry.Text = "🍓"
        berry.TextSize = 54
        berry.Font = Enum.Font.GothamBold
        berry.TextColor3 = RED
        berry.Parent = logo
    end
    local small = Instance.new("TextLabel")
    small.Name = "LogoName"
    small.Position = UDim2.new(0, 0, 0.66, 0)
    small.Size = UDim2.new(1, 0, 0.22, 0)
    small.BackgroundTransparency = 1
    small.Text = "Strawberry"
    small.TextSize = 13
    small.Font = Enum.Font.GothamBold
    small.TextColor3 = RED
    small.Parent = logo

    text(center, "Title", 116, 40, 34, PINK).Text = "🍓 Strawberry Kaitun"

    local bar = Instance.new("Frame")
    bar.Name = "Underline"
    bar.AnchorPoint = Vector2.new(0.5, 0)
    bar.Position = UDim2.new(0.5, 0, 0, 160)
    bar.Size = UDim2.new(0, 240, 0, 3)
    bar.BackgroundColor3 = RED
    bar.BorderSizePixel = 0
    bar.Parent = center
    corner(bar, UDim.new(1, 0))

    text(center, "Running", 174, 24, 20, SOFT)
    text(center, "Time", 198, 18, 14, MUTED)
    text(center, "Spin", 216, 14, 12, MUTED)

    for index = 1, 3 do
        local dot = Instance.new("Frame")
        dot.Name = "Dot" .. index
        dot.AnchorPoint = Vector2.new(0.5, 0)
        dot.Position = UDim2.new(0.5, (index - 2) * 16, 0, 234)
        dot.Size = UDim2.new(0, 8, 0, 8)
        dot.BackgroundColor3 = RED
        dot.BorderSizePixel = 0
        dot.Parent = center
        corner(dot, UDim.new(1, 0))
        dots[index] = dot
    end

    text(center, "Task", 250, 18, 15, TEXT, Enum.Font.GothamBold)
    text(center, "Status", 270, 34, 13, SOFT, Enum.Font.Gotham)

    box(center, "Level", -214, 312, 200)
    box(center, "Fragments", 0, 312, 200)
    box(center, "Beli", 214, 312, 200)
    box(center, "Melee", -107, 354, 414)
    box(center, "Sea", 214, 354, 200)

    text(center, "Items", 398, 18, 13, SOFT, Enum.Font.Gotham)
    text(center, "Resting", 416, 30, 12, MUTED, Enum.Font.Gotham)
    text(center, "Last", 450, 16, 12, MUTED, Enum.Font.Gotham)

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

local function short(number)
    number = tonumber(number) or 0
    if number >= 1e9 then return string.format("%.2fB", number / 1e9) end
    if number >= 1e6 then return string.format("%.2fM", number / 1e6) end
    if number >= 1e3 then return string.format("%.1fK", number / 1e3) end
    return tostring(math.floor(number))
end

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
    local status = select(2, pcall(Engine.status))
    if type(status) ~= "table" then status = { log = {}, resting = {} } end
    local session = os.clock() - startedAt
    local lines = {
        Running = "Kaitun Running" .. string.rep(".", tick % 3 + 1),
        Time = "Time: " .. clock(session) .. "  •  Total: " .. clock(totalBefore + session),
        Spin = safe(function()
            local left = Fruits.nextRollIn()
            if left == nil then return "Next fruit spin: unknown yet" end
            if left <= 0 then return "Next fruit spin: now" end
            return "Next fruit spin: " .. clock(left)
        end),
        Task = safe(function()
            local task = status.task or ("idle: " .. tostring(status.idle))
            return "Task: " .. task .. (status.hop and ("  (hop soon: " .. status.hop .. ")") or "")
        end),
        Status = safe(Farm.status),
        Level = "Level: " .. safe(Player.level),
        Fragments = "Fragments: " .. safe(function() return short(Player.data("Fragments")) end),
        Beli = "Beli: " .. safe(function() return short(Player.data("Beli")) end),
        Money = safe(function()
            return "Beli " .. short(Player.data("Beli")) .. "  ·  Fragments " .. short(Player.data("Fragments"))
        end),
        Melee = Config.skipped("Godhuman") and "Melee: chain OFF (Skip.Godhuman = true)"
            or ("Melee: " .. safe(Melee.describe)),
        Sea = "Sea: " .. safe(Player.sea),
        Items = safe(function()
            local items = {}
            for _, entry in ipairs(Tasks.CHECKLIST) do
                local ok, has = pcall(Tasks.owned, entry.item)
                items[#items + 1] = ((ok and has) and "[x] " or "[ ] ") .. entry.label
            end
            return table.concat(items, "   ")
        end),
        Resting = safe(function()
            -- Every task of this sea and why it runs or not (done, resting,
            -- not ready...), the rests with their time left.
            local parts = {}
            for _, entry in ipairs(status.plan or {}) do parts[#parts + 1] = entry end
            local text = table.concat(parts, "  ·  ")
            if #status.resting > 0 then text = text .. "   |   rest: " .. table.concat(status.resting, ", ") end
            return text
        end),
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
    if os.clock() - lastSave >= Screen.SAVE_EVERY then
        lastSave = os.clock()
        saveTotal()
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
    if gui then saveTotal() end
    for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    connections = {}
    if gui then pcall(function() gui:Destroy() end) end
    gui = nil
end

return Screen
