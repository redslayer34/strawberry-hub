--=============================================================================
-- ROW — le gabarit commun a tous les composants d'une section
--=============================================================================
--  Bouton, Toggle, Dropdown et Slider partagent exactement la meme carcasse :
--  un fond, un titre, une description facultative, une zone a droite pour le
--  controle, et un corps facultatif en dessous. Les factoriser ici garantit
--  que l'alignement, les marges et le survol restent identiques partout —
--  c'est ce qui donne une liste reguliere plutot qu'un empilement d'elements
--  aux hauteurs legerement differentes.
--
--  La hauteur est automatique : une description ou une barre de slider
--  agrandit la ligne sans qu'aucun nombre n'ait a etre recalcule ailleurs.
--=============================================================================

local Input = require("UI.Input")
local Theme = require("UI.Theme")
local Utility = require("UI.Utility")

local Row = {}

-- opts.interactive : cree un TextButton (donc `Activated`) plutot qu'un Frame.
-- opts.rightWidth  : largeur reservee au controle a droite.
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

    -- En-tete : titre a gauche, controle a droite, sur une seule ligne.
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

    -- Corps facultatif : utilise par le Slider pour sa barre.
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

    -- Un seul peintre pour toute la ligne : le changement de theme met a jour
    -- fond, bordure et textes d'un coup, sans que le composant s'en occupe.
    local painterId = Theme.register(function(theme)
        container.BackgroundColor3 = self.hovered and theme.ElementHover or theme.Element
        stroke.Color = theme.Border
        title.TextColor3 = theme.Text
        if description then description.TextColor3 = theme.MutedText end
    end)
    maid:give(function() Theme.unregister(painterId) end)

    self.painterId = painterId

    -- Survol et appui. Sur mobile il n'y a pas de survol : l'appui fournit
    -- seul le retour, d'ou les deux mecanismes en parallele.
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
