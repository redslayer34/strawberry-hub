--=============================================================================
-- DROPDOWN
--=============================================================================
--  The menu is NOT a child of the row. It lives in a layer above, at the root
--  of the interface, for two reasons:
--
--    * as a child it would be clipped by the section's ScrollingFrame, and the
--      last entry of a menu opened near the bottom would be cut off;
--    * only an absolute screen position lets us guarantee the menu never
--      overflows, opening upward when it has to.
--
--  It closes on selection and on an outside click. The connection watching for
--  that outside click exists only while the menu is open.
--=============================================================================

local Input = require("UI.Input")
local Row = require("UI.Components.Row")
local Theme = require("UI.Theme")
local Utility = require("UI.Utility")

local Dropdown = {}
Dropdown.__index = Dropdown

local ITEM_HEIGHT = 26
local MAX_MENU_HEIGHT = 160
local GAP = 4

function Dropdown.new(parent, opts, order, context)
    local self = setmetatable({}, Dropdown)

    self.values = opts.Values or {}
    self.value = opts.Default
    self.callback = opts.Callback
    self.open = false
    self.overlay = context and context.overlay
    self.itemMaid = Utility.maid()

    self.row = Row.new({
        parent = parent,
        name = "Dropdown",
        title = opts.Name,
        description = opts.Description,
        interactive = true,
        rightWidth = 16,
        order = order,
    })

    local maid = self.row.maid
    self.maid = maid
    maid:give(self.itemMaid)

    -- The chosen value sits under the title, as in the reference: the title
    -- says what the setting is, the line below says what it currently is.
    local selected = Utility.new("TextLabel", {
        Name = "Selected",
        Size = UDim2.new(1, -22, 0, 13),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = tostring(self.value or "-"),
        TextSize = 11,
        TextColor3 = Theme.color("MutedText"),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder = 2,
        Parent = self.row.container,
    })

    local chevron = Utility.new("TextLabel", {
        Name = "Chevron",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = "v",
        TextSize = 11,
        TextColor3 = Theme.color("MutedText"),
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = self.row.right,
    })

    self.selectedLabel, self.chevron = selected, chevron

    ---------------------------------------------------------------------
    -- Menu
    ---------------------------------------------------------------------

    local menu = Utility.new("Frame", {
        Name = "DropdownMenu",
        Size = UDim2.fromOffset(120, 0),
        BackgroundColor3 = Theme.color("Background"),
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 50,
        ClipsDescendants = true,
        Parent = self.overlay,
    })
    Utility.corner(5, menu)
    local menuStroke = Utility.stroke(Theme.color("Border"), 1, menu)
    maid:give(menu)

    local scroller = Utility.new("ScrollingFrame", {
        Name = "Items",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.color("Border"),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 51,
        Parent = menu,
    })
    Utility.padding(scroller, 4, 4, 4, 4)
    Utility.list(scroller, 2)

    self.menu, self.scroller = menu, scroller

    local painterId = Theme.register(function(theme)
        selected.TextColor3 = theme.MutedText
        chevron.TextColor3 = theme.MutedText
        menu.BackgroundColor3 = theme.Background
        menuStroke.Color = theme.Border
        scroller.ScrollBarImageColor3 = theme.Border
        -- Items live outside the row, so the Row painter does not cover them
        -- and they have to be repainted here.
        self:paintSelection()
    end)
    maid:give(function() Theme.unregister(painterId) end)

    self:Refresh(self.values, true)

    maid:give(Input.onActivate(self.row.container, function()
        if self.destroyed then return end
        self:Toggle()
    end))

    return self
end

---------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------

-- Works out position and size so the menu never leaves the screen: opening
-- downward when there is room, upward otherwise, with a bounded height (the
-- ScrollingFrame takes over from there).
function Dropdown:place()
    local row = self.row.container
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

    local count = #self.values
    local wanted = math.min(count * (ITEM_HEIGHT + 2) + 8, MAX_MENU_HEIGHT)
    local height = math.max(wanted, ITEM_HEIGHT + 8)

    local origin = row.AbsolutePosition
    local size = row.AbsoluteSize

    local x = Utility.clamp(origin.X, 4, math.max(4, viewport.X - size.X - 4))
    local below = origin.Y + size.Y + GAP
    local y

    if below + height <= viewport.Y - 4 then
        y = below
    else
        -- No room below: open upward.
        local above = origin.Y - height - GAP
        y = above >= 4 and above or Utility.clamp(viewport.Y - height - 4, 4, viewport.Y)
    end

    return UDim2.fromOffset(x, y), UDim2.fromOffset(size.X, height), height
end

---------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------

function Dropdown:Open()
    if self.open or self.destroyed or not self.overlay then return self end
    self.open = true

    local position, size, height = self:place()
    self.menu.Position = position
    self.menu.Size = UDim2.fromOffset(size.X.Offset, 0)
    self.menu.Visible = true

    Utility.tween(self.menu, { Size = UDim2.fromOffset(size.X.Offset, height) })
    Utility.tween(self.chevron, { Rotation = 180 })

    -- Open only while the menu is: nothing watches for clicks when no menu is
    -- expanded.
    self.outsideConnection = Input.onOutsideClick(
        { self.menu, self.row.container },
        function() self:Close() end)

    return self
end

function Dropdown:Close()
    if not self.open or self.destroyed then return self end
    self.open = false

    if self.outsideConnection then
        self.outsideConnection:Disconnect()
        self.outsideConnection = nil
    end

    local width = self.menu.Size.X.Offset
    local tween = Utility.tween(self.menu, { Size = UDim2.fromOffset(width, 0) })
    Utility.tween(self.chevron, { Rotation = 0 })

    -- Hide only once the animation is done, otherwise the menu vanishes
    -- instead of folding away.
    local connection
    connection = tween.Completed:Connect(function()
        connection:Disconnect()
        if not self.open then self.menu.Visible = false end
    end)

    return self
end

function Dropdown:Toggle()
    if self.open then return self:Close() end
    return self:Open()
end

function Dropdown:IsOpen() return self.open end

---------------------------------------------------------------------------
-- Values
---------------------------------------------------------------------------

-- Rebuilds the item list. The old items are released by a dedicated Maid: a
-- repeated Refresh must not pile up dead connections.
function Dropdown:Refresh(values, silent)
    if self.destroyed then return self end

    self.values = values or {}
    self.itemMaid:Destroy()
    self.itemMaid = Utility.maid()
    self.maid:give(self.itemMaid)

    -- Each button keeps ITS value. Finding the selection by comparing the
    -- displayed text would break the moment a value carries any formatting.
    self.items = {}

    -- The current value no longer exists in the new list: drop it rather than
    -- display a choice that can no longer be made.
    local stillValid = false
    for _, value in ipairs(self.values) do
        if value == self.value then
            stillValid = true
            break
        end
    end
    if not stillValid then self.value = nil end

    for index, value in ipairs(self.values) do
        local item = Utility.new("TextButton", {
            Name = "Item",
            Size = UDim2.new(1, 0, 0, ITEM_HEIGHT),
            BackgroundColor3 = Theme.color("Element"),
            BackgroundTransparency = value == self.value and 0 or 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = Enum.Font.Gotham,
            Text = "  " .. tostring(value),
            TextSize = 12,
            TextColor3 = value == self.value and Theme.color("Text") or Theme.color("MutedText"),
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = index,
            ZIndex = 52,
            Parent = self.scroller,
        })
        Utility.corner(4, item)
        self.itemMaid:give(item)
        self.items[#self.items + 1] = { button = item, value = value }

        for _, connection in ipairs(Input.onHover(item,
            function()
                if value ~= self.value then
                    item.BackgroundTransparency = 0
                    item.BackgroundColor3 = Theme.color("ElementHover")
                end
            end,
            function()
                if value ~= self.value then item.BackgroundTransparency = 1 end
            end)) do
            self.itemMaid:give(connection)
        end

        self.itemMaid:give(Input.onActivate(item, function()
            self:SetValue(value)
            self:Close()
        end))
    end

    -- Rebuilding is not choosing: refresh the display without firing the
    -- callback, since the value did not change as a result of the refresh.
    self.selectedLabel.Text = tostring(self.value or "-")
    self:paintSelection()
    return self
end

function Dropdown:SetValues(values, silent) return self:Refresh(values, silent) end

-- Repaints the selection without rebuilding: cheaper, and an open menu does
-- not flicker when the value changes.
function Dropdown:paintSelection()
    local theme = Theme.get()
    for _, entry in ipairs(self.items or {}) do
        local isSelected = entry.value == self.value
        entry.button.BackgroundTransparency = isSelected and 0 or 1
        entry.button.BackgroundColor3 = theme.Element
        entry.button.TextColor3 = isSelected and theme.Text or theme.MutedText
    end
end

function Dropdown:SetValue(value, silent)
    if self.destroyed then return self end

    local changed = value ~= self.value
    self.value = value
    self.selectedLabel.Text = tostring(value or "-")
    self:paintSelection()

    if changed and not silent and self.callback then
        local ok, err = pcall(self.callback, value)
        if not ok then warn("[UI] Dropdown callback: " .. tostring(err)) end
    end
    return self
end

function Dropdown:GetValue() return self.value end
function Dropdown:GetValues() return self.values end
function Dropdown:SetCallback(fn) self.callback = fn end
function Dropdown:SetText(text) self.row:setTitle(text) end

function Dropdown:Destroy()
    self.destroyed = true
    if self.outsideConnection then self.outsideConnection:Disconnect() end
    self.callback = nil
    self.maid:Destroy()
end

return Dropdown
