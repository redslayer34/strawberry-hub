--=============================================================================
-- TAB — sidebar button plus content page
--=============================================================================
--  Switching tabs only flips `Visible`. Pages are built once and kept: that is
--  what preserves component state (a slider's value, scroll position, a
--  dropdown's selection) across a round trip. Rebuilding on every click would
--  be simpler to write and would lose all of it.
--
--  The active tab is marked by a vertical red bar and a slightly lighter
--  background, as in the reference.
--=============================================================================

local Input = require("UI.Input")
local Section = require("UI.Section")
local Theme = require("UI.Theme")
local Utility = require("UI.Utility")

local Tab = {}
Tab.__index = Tab

function Tab.new(window, opts, order)
    local self = setmetatable({}, Tab)
    local maid = Utility.maid()

    self.maid = maid
    self.window = window
    self.name = opts.Name or "Tab"
    self.active = false
    self.sections = {}
    self.sectionCount = 0

    ---------------------------------------------------------------------
    -- Sidebar button
    ---------------------------------------------------------------------

    local button = Utility.new("TextButton", {
        Name = "TabButton",
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = Theme.color("Sidebar"),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = order or 1,
        Parent = window.tabList,
    })
    maid:give(button)
    Utility.corner(4, button)

    -- Active-tab bar: zero height at rest, growing on selection. The animation
    -- therefore runs from the centre and reads as a slide rather than a
    -- sudden appearance.
    local indicator = Utility.new("Frame", {
        Name = "Indicator",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 2, 0, 0),
        BackgroundColor3 = Theme.color("Accent"),
        BorderSizePixel = 0,
        Parent = button,
    })
    Utility.corner(1, indicator)

    local icon
    local textOffset = 10

    if opts.Icon then
        icon = Utility.new("ImageLabel", {
            Name = "Icon",
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 9, 0.5, 0),
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            Image = opts.Icon,
            ImageColor3 = Theme.color("MutedText"),
            Parent = button,
        })
        textOffset = 29
    end

    local label = Utility.new("TextLabel", {
        Name = "Label",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, textOffset, 0.5, 0),
        Size = UDim2.new(1, -(textOffset + 6), 1, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = self.name,
        TextSize = 12,
        TextColor3 = Theme.color("MutedText"),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = button,
    })

    ---------------------------------------------------------------------
    -- Page
    ---------------------------------------------------------------------

    local page = Utility.new("ScrollingFrame", {
        Name = "Page_" .. self.name,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.color("Border"),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Parent = window.content,
    })
    maid:give(page)
    Utility.padding(page, 10, 14, 12, 12)
    Utility.list(page, 12)

    self.button, self.page, self.indicator = button, page, indicator
    self.label, self.icon = label, icon

    ---------------------------------------------------------------------
    -- Appearance
    ---------------------------------------------------------------------

    local function paint(animate)
        local theme = Theme.get()
        local goalText = self.active and theme.Text or theme.MutedText
        local goalBg = self.active and theme.TabActive or theme.Sidebar
        local goalTransparency = self.active and 0 or 1
        local goalIndicator = self.active and UDim2.new(0, 2, 0, 14) or UDim2.new(0, 2, 0, 0)

        if animate then
            Utility.tween(label, { TextColor3 = goalText })
            Utility.tween(button, { BackgroundTransparency = goalTransparency })
            Utility.tween(indicator, { Size = goalIndicator })
            if icon then Utility.tween(icon, { ImageColor3 = goalText }) end
        else
            label.TextColor3 = goalText
            button.BackgroundTransparency = goalTransparency
            indicator.Size = goalIndicator
            if icon then icon.ImageColor3 = goalText end
        end
        button.BackgroundColor3 = goalBg
        indicator.BackgroundColor3 = theme.Accent
        page.ScrollBarImageColor3 = theme.Border
    end

    self.paint = paint

    local painterId = Theme.register(function() paint(false) end)
    maid:give(function() Theme.unregister(painterId) end)

    -- Hover only when the tab is not already active, otherwise hovering would
    -- wipe out the current tab's highlight.
    for _, connection in ipairs(Input.onHover(button,
        function()
            if not self.active then
                Utility.tween(button, { BackgroundTransparency = 0 })
                button.BackgroundColor3 = Theme.color("TabHover")
            end
        end,
        function()
            if not self.active then
                Utility.tween(button, { BackgroundTransparency = 1 })
            end
        end)) do
        maid:give(connection)
    end

    maid:give(Input.onActivate(button, function()
        window:SelectTab(self)
    end))

    return self
end

---------------------------------------------------------------------------

function Tab:CreateSection(opts)
    self.sectionCount = self.sectionCount + 1
    local section = Section.new(self.page, opts or {}, self.sectionCount, self.window.context)
    table.insert(self.sections, section)
    self.maid:give(section)
    return section
end

function Tab:Show()
    if self.active then return end
    self.active = true
    -- The page already exists: we only reveal it. That is what preserves
    -- scroll position and every component's state.
    self.page.Visible = true
    self.page.CanvasPosition = self.savedScroll or Vector2.new(0, 0)
    self.paint(true)
end

function Tab:Hide()
    if not self.active then return end
    self.active = false
    -- Roblox resets CanvasPosition on a hidden page, so keep it to restore on
    -- the way back.
    self.savedScroll = self.page.CanvasPosition
    self.page.Visible = false
    self.paint(true)
end

function Tab:IsActive() return self.active end
function Tab:SetName(name)
    self.name = name
    self.label.Text = tostring(name or "")
end

function Tab:Destroy()
    self.sections = {}
    self.maid:Destroy()
end

return Tab
