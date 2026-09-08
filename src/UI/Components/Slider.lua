--=============================================================================
-- SLIDER
--=============================================================================
--  La barre visible fait 4 pixels, mais la zone de saisie occupe toute la
--  hauteur du corps de la ligne : viser 4 pixels au doigt est impossible.
--  C'est la difference entre un slider utilisable sur telephone et un slider
--  qui ne l'est que sur PC.
--
--  Cliquer positionne immediatement (Input.makeScrubbable traite le premier
--  appui comme un deplacement), glisser continue, relacher termine.
--=============================================================================

local Input = require("UI.Input")
local Row = require("UI.Components.Row")
local Theme = require("UI.Theme")
local Utility = require("UI.Utility")

local Slider = {}
Slider.__index = Slider

local BAR_HEIGHT = 4
local KNOB = 10

function Slider.new(parent, opts, order)
    local self = setmetatable({}, Slider)

    self.min = opts.Min or 0
    self.max = opts.Max or 100
    self.rounding = opts.Rounding or 0
    self.callback = opts.Callback
    self.value = Utility.clamp(opts.Default or self.min, self.min, self.max)

    self.row = Row.new({
        parent = parent,
        name = "Slider",
        title = opts.Name,
        description = opts.Description,
        interactive = false,
        rightWidth = 44,
        order = order,
        body = true,
        bodyHeight = 16,
    })

    local maid = self.row.maid
    self.maid = maid

    local valueLabel = Utility.new("TextLabel", {
        Name = "Value",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        Text = "0",
        TextSize = 12,
        TextColor3 = Theme.color("MutedText"),
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = self.row.right,
    })

    -- Zone de saisie : toute la hauteur du corps, transparente.
    local hit = Utility.new("TextButton", {
        Name = "Hit",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = self.row.body,
    })

    local bar = Utility.new("Frame", {
        Name = "Bar",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
        BackgroundColor3 = Theme.color("Slider"),
        BorderSizePixel = 0,
        Parent = hit,
    })
    Utility.corner(BAR_HEIGHT / 2, bar)

    local fill = Utility.new("Frame", {
        Name = "Fill",
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Theme.color("Accent"),
        BorderSizePixel = 0,
        Parent = bar,
    })
    Utility.corner(BAR_HEIGHT / 2, fill)

    local knob = Utility.new("Frame", {
        Name = "Knob",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(KNOB, KNOB),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Parent = bar,
    })
    Utility.corner(KNOB / 2, knob)

    self.bar, self.fill, self.knob, self.valueLabel = bar, fill, knob, valueLabel

    local function alpha()
        local span = self.max - self.min
        if span <= 0 then return 0 end
        return Utility.clamp((self.value - self.min) / span, 0, 1)
    end

    local function render(animate)
        local a = alpha()
        local goalFill = UDim2.new(a, 0, 1, 0)
        local goalKnob = UDim2.new(a, 0, 0.5, 0)

        if animate then
            Utility.tween(fill, { Size = goalFill })
            Utility.tween(knob, { Position = goalKnob })
        else
            fill.Size = goalFill
            knob.Position = goalKnob
        end

        valueLabel.Text = Utility.format(self.value, self.rounding)
    end

    self.render = render

    local painterId = Theme.register(function(theme)
        bar.BackgroundColor3 = theme.Slider
        fill.BackgroundColor3 = theme.Accent
        valueLabel.TextColor3 = theme.MutedText
        render(false)
    end)
    maid:give(function() Theme.unregister(painterId) end)

    -- Conversion position ecran -> valeur. Pas d'animation pendant le
    -- glissement : le curseur doit coller au doigt.
    local function scrubTo(position)
        if self.destroyed then return end
        local origin = bar.AbsolutePosition.X
        local width = bar.AbsoluteSize.X
        if width <= 0 then return end

        local a = Utility.clamp((position.X - origin) / width, 0, 1)
        local raw = self.min + (self.max - self.min) * a
        self:SetValue(raw, false, true)
    end

    local begin, stop = Input.makeScrubbable(hit, scrubTo)
    maid:give(begin)
    maid:give(stop)

    render(false)
    return self
end

-- silent : n'appelle pas le callback. immediate : pas d'animation (glissement).
function Slider:SetValue(value, silent, immediate)
    value = Utility.clamp(tonumber(value) or self.min, self.min, self.max)
    value = Utility.round(value, self.rounding)

    if value == self.value then
        -- Reaffiche quand meme : un glissement borne doit repositionner le
        -- curseur sur la butee plutot que de le laisser suivre le doigt.
        self.render(not immediate)
        return self
    end

    self.value = value
    self.render(not immediate)

    if not silent and self.callback then
        local ok, err = pcall(self.callback, value)
        if not ok then warn("[UI] Slider callback : " .. tostring(err)) end
    end
    return self
end

function Slider:GetValue() return self.value end

function Slider:SetMin(min)
    self.min = min
    if self.value < min then return self:SetValue(min) end
    self.render(true)
    return self
end

function Slider:SetMax(max)
    self.max = max
    if self.value > max then return self:SetValue(max) end
    self.render(true)
    return self
end

function Slider:SetCallback(fn) self.callback = fn end
function Slider:SetText(text) self.row:setTitle(text) end

function Slider:Destroy()
    self.destroyed = true
    self.callback = nil
    self.maid:Destroy()
end

return Slider
