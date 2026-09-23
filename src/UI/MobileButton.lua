--=============================================================================
-- MOBILE BUTTON — a small draggable button that shows / hides the window
--=============================================================================
--  Fluent toggles its window with a keyboard key only (LeftControl by
--  default), which a phone does not have. On touch devices this adds a
--  button that calls Window:Minimize(), Fluent's own toggle.
--=============================================================================

local Services = require("Core.Services")

local MobileButton = {}

local function guiParent()
    if gethui then
        local ok, parent = pcall(gethui)
        if ok and parent then return parent end
    end
    return Services.get("CoreGui")
end

-- Returns the ScreenGui, or nil when not on a touch device.
function MobileButton.create(window, force)
    local input = Services.get("UserInputService")
    if not force and not input.TouchEnabled then return nil end

    local gui = Instance.new("ScreenGui")
    gui.Name = "StrawberryHubToggle"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end

    local button = Instance.new("TextButton")
    button.Name = "Toggle"
    button.Size = UDim2.fromOffset(46, 46)
    button.Position = UDim2.new(0, 16, 0.4, 0)
    button.BackgroundColor3 = Color3.fromRGB(32, 32, 36)
    button.BackgroundTransparency = 0.1
    button.Text = "SH"
    button.TextColor3 = Color3.fromRGB(255, 92, 120)
    button.TextSize = 16
    button.Font = Enum.Font.GothamBold
    button.AutoButtonColor = true
    button.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = button

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 92, 120)
    stroke.Thickness = 1.5
    stroke.Parent = button

    -- Drag: a press that moves more than a few pixels is a drag, not a tap.
    local dragging, dragStart, startPosition, moved

    button.InputBegan:Connect(function(event)
        local kind = event.UserInputType
        if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
            dragging, moved = true, false
            dragStart = event.Position
            startPosition = button.Position
        end
    end)

    button.InputChanged:Connect(function(event)
        if not dragging then return end
        local kind = event.UserInputType
        if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseMovement then return end
        local delta = event.Position - dragStart
        if math.abs(delta.X) + math.abs(delta.Y) > 6 then moved = true end
        button.Position = UDim2.new(
            startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
    end)

    button.InputEnded:Connect(function(event)
        local kind = event.UserInputType
        if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    button.Activated:Connect(function()
        if moved then return end
        pcall(function() window:Minimize() end)
    end)

    gui.Parent = guiParent()
    return gui
end

return MobileButton
