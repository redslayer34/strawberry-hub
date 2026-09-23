--=============================================================================
-- TOUCH SLIDER — makes Fluent's sliders usable with a finger
--=============================================================================
--  Fluent only starts dragging when the touch lands on the slider's 14 px dot,
--  and a tap on the rail does nothing. This adds, on top of the rail, an
--  invisible 36 px tall touch area: touching anywhere sets the value there,
--  and moving the finger keeps dragging. The dot is also enlarged.
--
--  Values go through the slider's own SetValue, so rounding, callbacks and
--  SaveManager behave exactly as before. Fluent's layout is private, so it is
--  located by shape (the rail frame holding a UISizeConstraint and the dot):
--  if that shape ever changes, the slider simply stays stock.
--=============================================================================

local Services = require("Core.Services")

local TouchSlider = {}

TouchSlider.HEIGHT = 36
TouchSlider.DOT = 22

local connections = {}

local function isPress(input)
    local kind = input.UserInputType
    return kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1
end

local function isMove(input)
    local kind = input.UserInputType
    return kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseMovement
end

-- Fluent's slider: an inner Frame (the 4 px bar) holding a UISizeConstraint
-- and a rail Frame whose child is the dot ImageLabel.
local function findParts(root)
    for _, node in ipairs(root:GetDescendants()) do
        if node:IsA("UISizeConstraint") and node.Parent and node.Parent:IsA("Frame") then
            local inner = node.Parent
            for _, child in ipairs(inner:GetChildren()) do
                if child:IsA("Frame") then
                    local dot = child:FindFirstChildWhichIsA("ImageLabel")
                    if dot then return inner, child, dot end
                end
            end
        end
    end
    return nil
end

-- Enhances the slider just added to `parent` (a Fluent tab or section).
-- Returns true when the touch area was added.
function TouchSlider.enhance(parent, slider)
    local container = parent and parent.Container
    if not container or not slider or not slider.SetValue then return false end

    local inner, rail, dot
    local children = container:GetChildren()
    for index = #children, 1, -1 do
        local child = children[index]
        if not child:FindFirstChild("StrawberryTouch", true) then
            inner, rail, dot = findParts(child)
            if inner then break end
        end
    end
    if not inner then return false end

    dot.Size = UDim2.fromOffset(TouchSlider.DOT, TouchSlider.DOT)
    -- Fluent positions the dot at (scale, -7): this anchor keeps the bigger
    -- dot centred on the same point.
    dot.AnchorPoint = Vector2.new((TouchSlider.DOT / 2 - 7) / TouchSlider.DOT, 0.5)

    local area = Instance.new("TextButton")
    area.Name = "StrawberryTouch"
    area.Text = ""
    area.AutoButtonColor = false
    area.BackgroundTransparency = 1
    area.AnchorPoint = Vector2.new(0.5, 0.5)
    area.Position = UDim2.new(0.5, 0, 0.5, 0)
    area.Size = UDim2.new(1, 16, 0, TouchSlider.HEIGHT)
    area.ZIndex = 10
    area.Parent = inner

    local dragging = false

    local function setFrom(x)
        local width = rail.AbsoluteSize.X
        if not width or width <= 0 then return end
        local scale = math.clamp((x - rail.AbsolutePosition.X) / width, 0, 1)
        slider:SetValue(slider.Min + (slider.Max - slider.Min) * scale)
    end

    local input = Services.get("UserInputService")
    connections[#connections + 1] = area.InputBegan:Connect(function(event)
        if isPress(event) then
            dragging = true
            setFrom(event.Position.X)
        end
    end)
    connections[#connections + 1] = input.InputChanged:Connect(function(event)
        if dragging and isMove(event) then setFrom(event.Position.X) end
    end)
    connections[#connections + 1] = input.InputEnded:Connect(function(event)
        if isPress(event) then dragging = false end
    end)
    return true
end

function TouchSlider.destroy()
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    connections = {}
end

return TouchSlider
