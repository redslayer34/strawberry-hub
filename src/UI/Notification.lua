--=============================================================================
-- NOTIFICATION — pile en haut a droite
--=============================================================================
--  Les notifications s'empilent au lieu de se superposer. Le placement se
--  fait par un UIListLayout : quand la plus ancienne disparait, les suivantes
--  remontent d'elles-memes. Positionner chacune a la main obligerait a
--  recalculer toute la pile a chaque disparition.
--
--  Chaque notification detient son propre Maid, et son minuteur est annulable :
--  detruire l'interface pendant qu'une notification est affichee ne doit pas
--  laisser un `task.delay` toucher une instance detruite.
--=============================================================================

local Theme = require("UI.Theme")
local Utility = require("UI.Utility")

local Notification = {}
Notification.__index = Notification

local WIDTH = 250
local MARGIN = 12

function Notification.new()
    local self = setmetatable({}, Notification)
    self.maid = Utility.maid()
    self.active = {}

    local gui = Utility.new("ScreenGui", {
        Name = "StrawberryNotifications",
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        -- Au-dessus de la fenetre : une notification masquee par l'interface
        -- ne sert a rien.
        DisplayOrder = 200,
        Parent = Utility.screenParent(),
    })
    self.maid:give(gui)

    local holder = Utility.new("Frame", {
        Name = "Holder",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -MARGIN, 0, MARGIN),
        Size = UDim2.fromOffset(WIDTH, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = gui,
    })
    Utility.new("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Parent = holder,
    })

    self.gui, self.holder = gui, holder
    self.counter = 0

    return self
end

function Notification:Notify(opts)
    opts = opts or {}
    if self.destroyed then return end

    self.counter = self.counter + 1
    local maid = Utility.maid()

    local card = Utility.new("Frame", {
        Name = "Notification",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.color("Notification"),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = self.counter,
        Parent = self.holder,
    })
    maid:give(card)
    Utility.corner(6, card)
    local stroke = Utility.stroke(Theme.color("Border"), 1, card)
    Utility.padding(card, 9, 10, 11, 11)
    Utility.list(card, 3)

    -- Filet d'accent a gauche : identifie la source d'un coup d'oeil sans
    -- ajouter de couleur au texte.
    local accent = Utility.new("Frame", {
        Name = "Accent",
        Size = UDim2.new(0, 2, 1, 0),
        Position = UDim2.new(0, -11, 0, 0),
        BackgroundColor3 = Theme.color("Accent"),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = card,
    })

    local title = Utility.new("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, 0, 0, 15),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = opts.Title or "Notification",
        TextSize = 12,
        TextColor3 = Theme.color("Text"),
        TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1,
        Parent = card,
    })

    local content
    if opts.Content and opts.Content ~= "" then
        content = Utility.new("TextLabel", {
            Name = "Content",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            Text = opts.Content,
            TextSize = 11,
            TextColor3 = Theme.color("MutedText"),
            TextTransparency = 1,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            LayoutOrder = 2,
            Parent = card,
        })
    end

    local painterId = Theme.register(function(theme)
        card.BackgroundColor3 = theme.Notification
        stroke.Color = theme.Border
        accent.BackgroundColor3 = theme.Accent
        title.TextColor3 = theme.Text
        if content then content.TextColor3 = theme.MutedText end
    end)
    maid:give(function() Theme.unregister(painterId) end)

    -- Entree : fondu simultane du fond et des textes.
    Utility.tween(card, { BackgroundTransparency = 0 }, Utility.SLOW)
    Utility.tween(accent, { BackgroundTransparency = 0 }, Utility.SLOW)
    Utility.tween(title, { TextTransparency = 0 }, Utility.SLOW)
    if content then Utility.tween(content, { TextTransparency = 0 }, Utility.SLOW) end

    local entry = { maid = maid, card = card, dismissed = false }
    table.insert(self.active, entry)

    local function dismiss()
        if entry.dismissed then return end
        entry.dismissed = true

        Utility.tween(card, { BackgroundTransparency = 1 }, Utility.SLOW)
        Utility.tween(accent, { BackgroundTransparency = 1 }, Utility.SLOW)
        Utility.tween(title, { TextTransparency = 1 }, Utility.SLOW)
        if content then Utility.tween(content, { TextTransparency = 1 }, Utility.SLOW) end

        task.delay(0.22, function()
            maid:Destroy()
            for index, candidate in ipairs(self.active) do
                if candidate == entry then
                    table.remove(self.active, index)
                    break
                end
            end
        end)
    end

    entry.dismiss = dismiss

    -- Le minuteur verifie que la notification n'a pas deja ete liberee :
    -- sans ce garde, detruire l'interface avant l'echeance ferait toucher
    -- des instances mortes.
    local duration = tonumber(opts.Duration) or 3
    task.delay(duration, function()
        if not self.destroyed and not entry.dismissed then dismiss() end
    end)

    return { Dismiss = dismiss }
end

function Notification:Clear()
    for index = #self.active, 1, -1 do
        local entry = self.active[index]
        entry.dismissed = true
        entry.maid:Destroy()
        table.remove(self.active, index)
    end
end

function Notification:Destroy()
    self.destroyed = true
    self:Clear()
    self.maid:Destroy()
end

return Notification
