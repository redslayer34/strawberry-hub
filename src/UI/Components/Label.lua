--=============================================================================
-- LABEL & DIVIDER
--=============================================================================
--  Two passive elements, grouped because they share the same absence of
--  interaction: no click, no hover, no callback.
--
--  The Label exists to show state that changes (progress, status) — hence
--  SetText, and wrapping for long text.
--=============================================================================

local Theme = require("UI.Theme")
local Utility = require("UI.Utility")

local Label = {}
Label.__index = Label

function Label.new(parent, opts, order)
    local self = setmetatable({}, Label)
    local maid = Utility.maid()
    self.maid = maid

    local container = Utility.new("Frame", {
        Name = "Label",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.color("Element"),
        BorderSizePixel = 0,
        LayoutOrder = order or 1,
        Parent = parent,
    })
    maid:give(container)

    Utility.corner(5, container)
    local stroke = Utility.stroke(Theme.color("Border"), 1, container)
    Utility.padding(container, 8, 8, 11, 11)

    local text = Utility.new("TextLabel", {
        Name = "Text",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = opts.Name or opts.Text or "",
        TextSize = 12,
        TextColor3 = Theme.color("Text"),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Parent = container,
    })

    self.container, self.label = container, text

    local painterId = Theme.register(function(theme)
        container.BackgroundColor3 = theme.Element
        stroke.Color = theme.Border
        text.TextColor3 = theme.Text
    end)
    maid:give(function() Theme.unregister(painterId) end)

    return self
end

function Label:SetText(value)
    self.label.Text = tostring(value or "")
    return self
end

function Label:GetText() return self.label.Text end

function Label:Destroy() self.maid:Destroy() end

---------------------------------------------------------------------------

local Divider = {}
Divider.__index = Divider

function Divider.new(parent, opts, order)
    local self = setmetatable({}, Divider)
    local maid = Utility.maid()
    self.maid = maid

    -- The transparent holder provides the breathing room; only the one-pixel
    -- line is visible. A separator flush against its neighbours separates
    -- nothing.
    local holder = Utility.new("Frame", {
        Name = "Divider",
        Size = UDim2.new(1, 0, 0, 9),
        BackgroundTransparency = 1,
        LayoutOrder = order or 1,
        Parent = parent,
    })
    maid:give(holder)

    local line = Utility.new("Frame", {
        Name = "Line",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.color("Border"),
        BorderSizePixel = 0,
        Parent = holder,
    })

    local painterId = Theme.register(function(theme)
        line.BackgroundColor3 = theme.Border
    end)
    maid:give(function() Theme.unregister(painterId) end)

    self.container = holder
    return self
end

function Divider:Destroy() self.maid:Destroy() end

Label.Divider = Divider
return Label
