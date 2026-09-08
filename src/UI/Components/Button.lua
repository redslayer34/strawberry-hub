--=============================================================================
-- BUTTON
--=============================================================================
--  Ligne cliquable, avec description et chevron facultatifs. Le chevron sert
--  a signaler une action qui emmene ailleurs (un teleport, un sous-menu) par
--  opposition a une action qui s'execute sur place.
--=============================================================================

local Input = require("UI.Input")
local Row = require("UI.Components.Row")
local Theme = require("UI.Theme")
local Utility = require("UI.Utility")

local Button = {}
Button.__index = Button

function Button.new(parent, opts, order)
    local self = setmetatable({}, Button)

    self.callback = opts.Callback
    self.row = Row.new({
        parent = parent,
        name = "Button",
        title = opts.Name,
        description = opts.Description,
        interactive = true,
        rightWidth = opts.Arrow and 14 or 0,
        order = order,
    })

    local maid = self.row.maid
    self.maid = maid

    if opts.Arrow then
        local arrow = Utility.new("TextLabel", {
            Name = "Arrow",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            -- Chevron typographique plutot qu'une image : aucun asset a
            -- charger, et le rendu suit la couleur du theme.
            Text = ">",
            TextSize = 12,
            TextColor3 = Theme.color("MutedText"),
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = self.row.right,
        })

        local painterId = Theme.register(function(theme)
            arrow.TextColor3 = theme.MutedText
        end)
        maid:give(function() Theme.unregister(painterId) end)
        self.arrow = arrow
    end

    maid:give(Input.onActivate(self.row.container, function()
        if self.destroyed then return end
        if self.callback then self.callback() end
    end))

    return self
end

function Button:SetText(text) self.row:setTitle(text) end
function Button:SetDescription(text) self.row:setDescription(text) end
function Button:SetCallback(fn) self.callback = fn end

function Button:Destroy()
    self.destroyed = true
    self.callback = nil
    self.maid:Destroy()
end

return Button
