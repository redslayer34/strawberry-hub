--=============================================================================
-- TOGGLE
--=============================================================================
--  Interrupteur a bascule. L'etat visuel est reconstruit par `apply`, seule
--  fonction autorisee a toucher a l'apparence : SetValue, le clic et le
--  changement de theme y passent tous, ce qui evite qu'un chemin oublie de
--  mettre a jour le bouton ou la couleur de la piste.
--=============================================================================

local Input = require("UI.Input")
local Row = require("UI.Components.Row")
local Theme = require("UI.Theme")
local Utility = require("UI.Utility")

local Toggle = {}
Toggle.__index = Toggle

local TRACK_WIDTH = 34
local TRACK_HEIGHT = 18
local KNOB = 12

function Toggle.new(parent, opts, order)
    local self = setmetatable({}, Toggle)

    self.value = opts.Default == true
    self.callback = opts.Callback

    self.row = Row.new({
        parent = parent,
        name = "Toggle",
        title = opts.Name,
        description = opts.Description,
        interactive = true,
        rightWidth = TRACK_WIDTH,
        order = order,
    })

    local maid = self.row.maid
    self.maid = maid

    local track = Utility.new("Frame", {
        Name = "Track",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(TRACK_WIDTH, TRACK_HEIGHT),
        BackgroundColor3 = Theme.color("Toggle"),
        BorderSizePixel = 0,
        Parent = self.row.right,
    })
    Utility.corner(TRACK_HEIGHT / 2, track)

    local knob = Utility.new("Frame", {
        Name = "Knob",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(KNOB, KNOB),
        BackgroundColor3 = Theme.color("ToggleKnob"),
        BorderSizePixel = 0,
        Parent = track,
    })
    Utility.corner(KNOB / 2, knob)

    self.track, self.knob = track, knob

    -- Point unique de rendu de l'etat.
    local function apply(animate)
        local theme = Theme.get()
        local trackColor = self.value and theme.Accent or theme.Toggle
        local knobColor = self.value and Color3.fromRGB(255, 255, 255) or theme.ToggleKnob
        local knobPos = self.value
            and UDim2.new(1, -(KNOB + 3), 0.5, 0)
            or UDim2.new(0, 3, 0.5, 0)

        if animate then
            Utility.tween(track, { BackgroundColor3 = trackColor })
            Utility.tween(knob, { Position = knobPos, BackgroundColor3 = knobColor })
        else
            track.BackgroundColor3 = trackColor
            knob.Position = knobPos
            knob.BackgroundColor3 = knobColor
        end
    end

    self.apply = apply

    local painterId = Theme.register(function() apply(false) end)
    maid:give(function() Theme.unregister(painterId) end)

    maid:give(Input.onActivate(self.row.container, function()
        if self.destroyed then return end
        self:SetValue(not self.value)
    end))

    return self
end

-- silent : met a jour l'affichage sans declencher le callback. Utile pour
-- restaurer un etat sauvegarde sans relancer l'action associee.
function Toggle:SetValue(value, silent)
    value = value == true
    if value == self.value then return self end

    self.value = value
    self.apply(true)

    if not silent and self.callback then
        local ok, err = pcall(self.callback, value)
        if not ok then warn("[UI] Toggle callback : " .. tostring(err)) end
    end
    return self
end

function Toggle:GetValue() return self.value end
function Toggle:SetCallback(fn) self.callback = fn end
function Toggle:SetText(text) self.row:setTitle(text) end

function Toggle:Destroy()
    self.destroyed = true
    self.callback = nil
    self.maid:Destroy()
end

return Toggle
