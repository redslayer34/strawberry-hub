--=============================================================================
-- SECTION — a discreet heading and a stack of components
--=============================================================================
--  A section is only a visual grouping: it does not own its components in the
--  engine sense, but it keeps a list of them so they can all be destroyed at
--  once. Without that list, destroying a section would leave theme painters
--  and connections alive while their instances are gone.
--=============================================================================

local Button = require("UI.Components.Button")
local Dropdown = require("UI.Components.Dropdown")
local Label = require("UI.Components.Label")
local Slider = require("UI.Components.Slider")
local Theme = require("UI.Theme")
local Toggle = require("UI.Components.Toggle")
local Utility = require("UI.Utility")

local Section = {}
Section.__index = Section

function Section.new(parent, opts, order, context)
    local self = setmetatable({}, Section)
    local maid = Utility.maid()

    self.maid = maid
    self.context = context
    self.components = {}
    self.count = 0

    local holder = Utility.new("Frame", {
        Name = "Section",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = order or 1,
        Parent = parent,
    })
    maid:give(holder)
    Utility.list(holder, 5)

    local header = Utility.new("TextLabel", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = opts.Name or "",
        TextSize = 13,
        TextColor3 = Theme.color("Text"),
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 0,
        Parent = holder,
    })

    local painterId = Theme.register(function(theme)
        header.TextColor3 = theme.Text
    end)
    maid:give(function() Theme.unregister(painterId) end)

    self.holder, self.header = holder, header
    return self
end

-- Insertion order is display order. A counter rather than #components: removing
-- a component must not shift the ones after it.
function Section:nextOrder()
    self.count = self.count + 1
    return self.count
end

function Section:track(component)
    table.insert(self.components, component)
    self.maid:give(component)
    return component
end

function Section:CreateButton(opts)
    return self:track(Button.new(self.holder, opts, self:nextOrder()))
end

function Section:CreateToggle(opts)
    return self:track(Toggle.new(self.holder, opts, self:nextOrder()))
end

function Section:CreateSlider(opts)
    return self:track(Slider.new(self.holder, opts, self:nextOrder()))
end

-- The context carries the overlay layer: a dropdown menu has to be able to
-- escape the tab's ScrollingFrame.
function Section:CreateDropdown(opts)
    return self:track(Dropdown.new(self.holder, opts, self:nextOrder(), self.context))
end

function Section:CreateLabel(opts)
    return self:track(Label.new(self.holder, opts, self:nextOrder()))
end

function Section:CreateDivider()
    return self:track(Label.Divider.new(self.holder, {}, self:nextOrder()))
end

function Section:SetName(name) self.header.Text = tostring(name or "") end

function Section:Destroy()
    self.components = {}
    self.maid:Destroy()
end

return Section
