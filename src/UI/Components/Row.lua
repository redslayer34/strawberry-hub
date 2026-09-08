--=============================================================================
-- ROW — the shared template behind every component in a section
--=============================================================================
--  Button, Toggle, Dropdown and Slider share exactly the same shell: a
--  background, a title, an optional description, a slot on the right for the
--  control, and an optional body underneath. Factoring it here guarantees that
--  alignment, padding and hover stay identical everywhere — which is what
--  makes a list read as one thing rather than a stack of near-matching rows.
--
--  Height is automatic: a description or a slider bar grows the row without
--  any number needing to be recalculated elsewhere.
--=============================================================================

local Input = require("UI.Input")
local Theme = require("UI.Theme")
local Utility = require("UI.Utility")

local Row = {}

-- opts.interactive : builds a TextButton (so `Activated` exists) instead of a
-- Frame. opts.rightWidth : width reserved for the control on the right.
function Row.new(opts)
    local maid = Utility.maid()
    local rightWidth = opts.rightWidth or 0
    local className = opts.interactive and "TextButton" or "Frame"

    local container = Utility.new(className, {
        Name = opts.name or "Row",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.color("Element"),
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = opts.order or 1,
        Parent = opts.parent,
    })
    maid:give(container)

    Utility.corner(5, container)
    local stroke = Utility.stroke(Theme.color("Border"), 1, container)
    Utility.padding(container, 8, 8, 11, 11)
    Utility.list(container, 3)

    -- Header: title on the left, control on the right, on one line.
    local header = Utility.new("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = container,
    })

    local title = Utility.new("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, -(rightWidth + 6), 1, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = opts.title or "",
        TextSize = 13,
        TextColor3 = Theme.color("Text"),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = header,
    })

    local right = Utility.new("Frame", {
        Name = "Right",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, rightWidth, 1, 0),
        BackgroundTransparency = 1,
        Parent = header,
    })

    local description
    if opts.description and opts.description ~= "" then
        description = Utility.new("TextLabel", {
            Name = "Description",
            Size = UDim2.new(1, -(rightWidth + 6), 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            Text = opts.description,
            TextSize = 11,
            TextColor3 = Theme.color("MutedText"),
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            LayoutOrder = 2,
            Parent = container,
        })
    end

    -- Optional body, used by the Slider for its bar.
    local body
    if opts.body then
        body = Utility.new("Frame", {
            Name = "Body",
            Size = UDim2.new(1, 0, 0, opts.bodyHeight or 14),
            BackgroundTransparency = 1,
            LayoutOrder = 3,
            Parent = container,
        })
    end

    local self = {
        maid = maid,
        container = container,
        header = header,
        title = title,
        right = right,
        description = description,
        body = body,
        hovered = false,
        pressed = false,
    }

    -- One painter for the whole row: a theme change updates background, border
    -- and text at once, without the component having to care.
    local painterId = Theme.register(function(theme)
        container.BackgroundColor3 = self.hovered and theme.ElementHover or theme.Element
        stroke.Color = theme.Border
        title.TextColor3 = theme.Text
        if description then description.TextColor3 = theme.MutedText end
    end)
    maid:give(function() Theme.unregister(painterId) end)

    self.painterId = painterId

    -- Hover and press. There is no hover on mobile, so the press provides the
    -- only feedback there — hence both mechanisms side by side.
    if opts.interactive and not opts.noFeedback then
        for _, connection in ipairs(Input.onHover(container,
            function()
                self.hovered = true
                Utility.tween(container, { BackgroundColor3 = Theme.color("ElementHover") })
            end,
            function()
                self.hovered = false
                Utility.tween(container, { BackgroundColor3 = Theme.color("Element") })
            end)) do
            maid:give(connection)
        end

        for _, connection in ipairs(Input.onPress(container,
            function()
                Utility.tween(container, { BackgroundColor3 = Theme.color("ElementDown") })
            end,
            function()
                Utility.tween(container, {
                    BackgroundColor3 = self.hovered
                        and Theme.color("ElementHover") or Theme.color("Element"),
                })
            end)) do
            maid:give(connection)
        end
    end

    function self:setTitle(text)
        title.Text = tostring(text or "")
    end

    function self:setDescription(text)
        if description then description.Text = tostring(text or "") end
    end

    function self:Destroy()
        maid:Destroy()
    end

    return self
end

return Row
