-- Strawberry Hub — bundle genere par tools/pack.py. Ne pas editer.
local __modules = {}
local __loaded = {}
local function require(name)
    local cached = __loaded[name]
    if cached ~= nil then return cached end
    local factory = __modules[name]
    if not factory then
        error("[Strawberry Hub] module introuvable : " .. tostring(name), 2)
    end
    -- Marked before the body runs so a dependency cycle surfaces as a nil
    -- field instead of an unbounded recursion.
    __loaded[name] = true
    local value = factory()
    if value == nil then value = true end
    __loaded[name] = value
    return value
end

__modules["UI.Components.Button"] = function()
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
end

__modules["UI.Components.Dropdown"] = function()
--=============================================================================
-- DROPDOWN
--=============================================================================
--  Le menu n'est PAS un enfant de la ligne. Il est place dans une couche
--  superieure, a la racine de l'interface, pour deux raisons :
--
--    * une liste enfant serait rognee par le ScrollingFrame de la section,
--      et la derniere entree d'un menu ouvert en bas de page serait coupee ;
--    * seule une position ecran absolue permet de garantir que le menu ne
--      deborde jamais, quitte a s'ouvrir vers le haut.
--
--  Le menu se ferme a la selection et au clic exterieur. La connexion qui
--  surveille le clic exterieur n'existe que pendant l'ouverture.
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

    -- La valeur choisie s'affiche sous le titre, comme dans la reference :
    -- le titre dit ce que le reglage est, la ligne du dessous ce qu'il vaut.
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
        -- Les items vivent hors de la ligne : ils ne sont pas couverts par
        -- le peintre du Row et doivent etre repeints ici.
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

-- Calcule la position et la taille du menu de facon a ne jamais sortir de
-- l'ecran : ouverture vers le bas si la place le permet, vers le haut sinon,
-- et hauteur bornee (le ScrollingFrame prend le relais).
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
        -- Pas la place en dessous : on ouvre vers le haut.
        local above = origin.Y - height - GAP
        y = above >= 4 and above or Utility.clamp(viewport.Y - height - 4, 4, viewport.Y)
    end

    return UDim2.fromOffset(x, y), UDim2.fromOffset(size.X, height), height
end

---------------------------------------------------------------------------
-- Ouverture / fermeture
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

    -- Ouverte seulement pendant l'ouverture du menu : rien ne surveille les
    -- clics quand aucun menu n'est deroule.
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

    -- Masque seulement une fois l'animation finie, sinon le menu disparait
    -- d'un coup au lieu de se replier.
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
-- Valeurs
---------------------------------------------------------------------------

-- Reconstruit la liste d'items. Les anciens sont liberes par un Maid dedie :
-- un Refresh repete ne doit pas empiler des connexions mortes.
function Dropdown:Refresh(values, silent)
    if self.destroyed then return self end

    self.values = values or {}
    self.itemMaid:Destroy()
    self.itemMaid = Utility.maid()
    self.maid:give(self.itemMaid)

    -- Chaque bouton garde SA valeur. Retrouver la selection en comparant le
    -- texte affiche casserait des qu'une valeur contient une mise en forme.
    self.items = {}

    -- La valeur courante n'existe plus dans la nouvelle liste : on la lache
    -- plutot que d'afficher un choix devenu impossible.
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

    -- Reconstruire n'est pas choisir : on rafraichit l'affichage sans
    -- declencher le callback, la valeur n'ayant pas change du fait du Refresh.
    self.selectedLabel.Text = tostring(self.value or "-")
    self:paintSelection()
    return self
end

function Dropdown:SetValues(values, silent) return self:Refresh(values, silent) end

-- Repeint la selection sans reconstruire : moins couteux, et un menu ouvert
-- ne clignote pas au changement de valeur.
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
        if not ok then warn("[UI] Dropdown callback : " .. tostring(err)) end
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
end

__modules["UI.Components.Label"] = function()
--=============================================================================
-- LABEL & DIVIDER
--=============================================================================
--  Deux elements passifs, regroupes parce qu'ils partagent la meme absence
--  d'interaction : ni clic, ni survol, ni callback.
--
--  Le Label sert a afficher un etat qui change (progression, statut) : d'ou
--  SetText, et le retour a la ligne automatique pour un texte long.
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

    -- Le conteneur transparent donne la respiration ; seul le trait d'un
    -- pixel est visible. Un separateur qui touche les elements voisins ne
    -- separe rien.
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
end

__modules["UI.Components.Row"] = function()
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
end

__modules["UI.Components.Slider"] = function()
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
end

__modules["UI.Components.Toggle"] = function()
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
end

__modules["UI.Input"] = function()
--=============================================================================
-- INPUT — clic, survol et deplacement, souris comme tactile
--=============================================================================
--  Un seul module traite les entrees, pour que les composants n'aient jamais
--  a distinguer souris et doigt.
--
--  Sur le deplacement : aucune boucle. Les connexions de suivi (InputChanged,
--  InputEnded) ne sont ouvertes qu'au moment ou le drag commence, et fermees
--  des qu'il finit. Au repos, une fenetre ne coute qu'une seule connexion
--  InputBegan sur sa barre de titre — contre une connexion RenderStepped
--  permanente par fenetre dans l'approche naive.
--=============================================================================

local UserInputService = game:GetService("UserInputService")

local Input = {}

-- Types d'entree traites comme un appui. Le tactile et la souris sont
-- volontairement equivalents partout.
local function isPress(inputObject)
    local kind = inputObject.UserInputType
    return kind == Enum.UserInputType.MouseButton1
        or kind == Enum.UserInputType.Touch
end

local function isMove(inputObject)
    local kind = inputObject.UserInputType
    return kind == Enum.UserInputType.MouseMovement
        or kind == Enum.UserInputType.Touch
end

function Input.isTouchDevice()
    local ok, touch = pcall(function() return UserInputService.TouchEnabled end)
    local okMouse, mouse = pcall(function() return UserInputService.MouseEnabled end)
    return (ok and touch) and not (okMouse and mouse)
end

---------------------------------------------------------------------------
-- Activation
---------------------------------------------------------------------------

-- `Activated` couvre le clic, le tap et la manette d'un seul coup : c'est le
-- signal a utiliser pour "l'utilisateur a valide cet element".
function Input.onActivate(button, callback)
    return button.Activated:Connect(function()
        local ok, err = pcall(callback)
        if not ok then warn("[UI] callback : " .. tostring(err)) end
    end)
end

-- Retour visuel d'appui. Separe de l'activation : sur mobile il n'y a pas de
-- survol, l'appui est le seul retour disponible.
function Input.onPress(button, onDown, onUp)
    local connections = {}

    connections[#connections + 1] = button.InputBegan:Connect(function(inputObject)
        if isPress(inputObject) and onDown then onDown() end
    end)

    connections[#connections + 1] = button.InputEnded:Connect(function(inputObject)
        if isPress(inputObject) and onUp then onUp() end
    end)

    return connections
end

-- Survol souris uniquement — volontairement : simuler un survol au doigt
-- laisse des elements allumes apres le retrait du doigt.
function Input.onHover(button, onEnter, onLeave)
    local connections = {}

    if onEnter then
        connections[#connections + 1] = button.MouseEnter:Connect(onEnter)
    end
    if onLeave then
        connections[#connections + 1] = button.MouseLeave:Connect(onLeave)
    end

    return connections
end

---------------------------------------------------------------------------
-- Deplacement de fenetre
---------------------------------------------------------------------------

-- handle : la zone qui saisit (barre de titre). frame : ce qui se deplace.
-- Renvoie la connexion permanente et une fonction d'arret, a confier au Maid.
function Input.makeDraggable(frame, handle, options)
    options = options or {}

    local dragging = false
    local startInput, startPosition
    local moveConnection, endConnection

    local function stop()
        dragging = false
        if moveConnection then moveConnection:Disconnect() end
        if endConnection then endConnection:Disconnect() end
        moveConnection, endConnection = nil, nil
    end

    local function update(inputObject)
        local delta = inputObject.Position - startInput
        local goal = UDim2.new(
            startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)

        -- Pas de tween ici : interpoler la position pendant un drag ajoute un
        -- retard visible entre le doigt et la fenetre. Le suivi direct est ce
        -- qui donne la sensation de fluidite.
        frame.Position = goal
        if options.onDrag then options.onDrag(goal) end
    end

    local begin = handle.InputBegan:Connect(function(inputObject)
        if not isPress(inputObject) then return end

        dragging = true
        startInput = inputObject.Position
        startPosition = frame.Position

        -- Ouvertes seulement pendant le drag, refermees juste apres.
        moveConnection = UserInputService.InputChanged:Connect(function(moved)
            if dragging and isMove(moved) then update(moved) end
        end)

        endConnection = UserInputService.InputEnded:Connect(function(ended)
            if isPress(ended) then stop() end
        end)
    end)

    return begin, stop
end

---------------------------------------------------------------------------
-- Glissement sur une barre (slider)
---------------------------------------------------------------------------

-- Meme principe : suivi ouvert a l'appui, referme au relachement. `onMove`
-- recoit la position absolue du pointeur ; c'est au slider de la convertir
-- en valeur, lui seul connaissant sa geometrie.
function Input.makeScrubbable(target, onMove, onRelease)
    local active = false
    local moveConnection, endConnection

    local function stop()
        if not active then return end
        active = false
        if moveConnection then moveConnection:Disconnect() end
        if endConnection then endConnection:Disconnect() end
        moveConnection, endConnection = nil, nil
        if onRelease then onRelease() end
    end

    local begin = target.InputBegan:Connect(function(inputObject)
        if not isPress(inputObject) then return end

        active = true
        -- Le premier appui compte comme un deplacement : cliquer sur la barre
        -- doit deplacer le curseur sans avoir a glisser.
        onMove(inputObject.Position)

        moveConnection = UserInputService.InputChanged:Connect(function(moved)
            if active and isMove(moved) then onMove(moved.Position) end
        end)

        endConnection = UserInputService.InputEnded:Connect(function(ended)
            if isPress(ended) then stop() end
        end)
    end)

    return begin, stop
end

---------------------------------------------------------------------------
-- Clic exterieur
---------------------------------------------------------------------------

-- Ferme un menu quand l'appui tombe hors de sa zone. Utilise par le
-- Dropdown. La connexion est ouverte a l'ouverture du menu et fermee a sa
-- fermeture : rien ne tourne quand aucun menu n'est ouvert.
function Input.onOutsideClick(regions, callback)
    return UserInputService.InputBegan:Connect(function(inputObject)
        if not isPress(inputObject) then return end

        local position = inputObject.Position
        for _, region in ipairs(regions) do
            if region and region.Parent then
                local origin = region.AbsolutePosition
                local size = region.AbsoluteSize
                if position.X >= origin.X and position.X <= origin.X + size.X
                    and position.Y >= origin.Y and position.Y <= origin.Y + size.Y then
                    return
                end
            end
        end

        callback()
    end)
end

return Input
end

__modules["UI.Notification"] = function()
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
end

__modules["UI.Section"] = function()
--=============================================================================
-- SECTION — un titre discret et une pile de composants
--=============================================================================
--  La section n'est qu'un regroupement visuel : elle ne possede pas ses
--  composants au sens du cycle de vie du jeu, mais elle les garde en liste
--  pour pouvoir tous les detruire d'un coup. Sans cette liste, detruire une
--  section laisserait des peintres de theme et des connexions vivants alors
--  que leurs instances ont disparu.
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

-- Ordre d'ajout = ordre d'affichage. Un compteur plutot que #components :
-- retirer un composant ne doit pas faire remonter les suivants.
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

-- Le contexte porte la couche de superposition : le menu du dropdown doit
-- pouvoir sortir du ScrollingFrame de l'onglet.
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
end

__modules["UI.Tab"] = function()
--=============================================================================
-- TAB — bouton de barre laterale + page de contenu
--=============================================================================
--  Changer d'onglet ne fait que basculer `Visible`. Les pages sont construites
--  une fois et gardees : c'est ce qui preserve l'etat des composants (valeur
--  d'un slider, position de defilement, selection d'un dropdown) d'un aller-
--  retour a l'autre. Reconstruire a chaque clic serait plus simple a ecrire
--  et perdrait tout.
--
--  L'onglet actif se signale par un liseré rouge vertical et un fond
--  legerement plus clair, comme sur la reference.
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
    -- Bouton de la barre laterale
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

    -- Liseré d'onglet actif : hauteur nulle au repos, il grandit a la
    -- selection. L'animation part donc du centre et se lit comme un
    -- glissement, pas comme une apparition.
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
    -- Apparence
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

    -- Survol : uniquement quand l'onglet n'est pas deja actif, sinon le
    -- survol effacerait la mise en avant de l'onglet courant.
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
    -- La page existe deja : on ne fait que la reveler. C'est ce qui preserve
    -- la position de defilement et l'etat de chaque composant.
    self.page.Visible = true
    self.page.CanvasPosition = self.savedScroll or Vector2.new(0, 0)
    self.paint(true)
end

function Tab:Hide()
    if not self.active then return end
    self.active = false
    -- Roblox remet CanvasPosition a zero sur une page masquee : on la garde
    -- pour la restaurer au retour.
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
end

__modules["UI.Theme"] = function()
--=============================================================================
-- THEME — palette centrale, applicable a chaud
--=============================================================================
--  Aucun composant ne code une couleur en dur. Chacun enregistre un
--  "peintre" : une fonction qui applique la palette a ses instances. Changer
--  de theme consiste alors a rejouer tous les peintres, sans reconstruire
--  quoi que ce soit — l'etat des toggles, la position de la fenetre et
--  l'onglet actif survivent au changement.
--
--  Le peintre est appele une premiere fois a l'enregistrement : un composant
--  n'a donc jamais a peindre lui-meme a la construction.
--=============================================================================

local Theme = {}

-- Sombre, compact, accent rouge discret. Les ecarts entre Background,
-- Sidebar et Element sont volontairement faibles : c'est ce qui donne
-- l'aspect pose de la reference, sans bordures marquees.
Theme.DEFAULT = {
    Window       = Color3.fromRGB(13, 13, 15),
    Background   = Color3.fromRGB(20, 20, 23),
    Sidebar      = Color3.fromRGB(16, 16, 18),
    Topbar       = Color3.fromRGB(16, 16, 18),

    Element      = Color3.fromRGB(26, 26, 30),
    ElementHover = Color3.fromRGB(34, 34, 39),
    ElementDown  = Color3.fromRGB(22, 22, 26),

    TabActive    = Color3.fromRGB(26, 26, 30),
    TabHover     = Color3.fromRGB(22, 22, 26),

    Accent       = Color3.fromRGB(196, 54, 54),
    AccentMuted  = Color3.fromRGB(120, 38, 38),

    Text         = Color3.fromRGB(232, 232, 236),
    MutedText    = Color3.fromRGB(128, 128, 138),
    Border       = Color3.fromRGB(38, 38, 44),

    Toggle       = Color3.fromRGB(44, 44, 50),
    ToggleKnob   = Color3.fromRGB(150, 150, 158),
    Slider       = Color3.fromRGB(44, 44, 50),

    Notification = Color3.fromRGB(22, 22, 26),
}

local current = {}
for key, value in pairs(Theme.DEFAULT) do current[key] = value end

local painters = {}
local nextId = 0

function Theme.get() return current end

-- Lecture d'une teinte, avec repli sur la palette par defaut : un theme
-- partiel fourni par l'utilisateur ne doit pas laisser de trous.
function Theme.color(key)
    return current[key] or Theme.DEFAULT[key] or Color3.fromRGB(255, 0, 255)
end

-- painter : function(theme). Appele tout de suite, puis a chaque SetTheme.
-- Renvoie un identifiant a passer a Theme.unregister (garde par le Maid du
-- composant, ce qui evite les peintres orphelins apres Destroy).
function Theme.register(painter)
    nextId = nextId + 1
    painters[nextId] = painter
    local ok, err = pcall(painter, current)
    if not ok then warn("[UI] peintre en erreur : " .. tostring(err)) end
    return nextId
end

function Theme.unregister(id)
    if id then painters[id] = nil end
end

-- Fusion, pas remplacement : passer { Accent = ... } ne doit pas effacer le
-- reste de la palette.
function Theme.set(newTheme)
    if type(newTheme) ~= "table" then return current end

    for key, value in pairs(newTheme) do
        if typeof(value) == "Color3" then current[key] = value end
    end

    for _, painter in pairs(painters) do
        local ok, err = pcall(painter, current)
        if not ok then warn("[UI] peintre en erreur : " .. tostring(err)) end
    end
    return current
end

function Theme.reset()
    local copy = {}
    for key, value in pairs(Theme.DEFAULT) do copy[key] = value end
    return Theme.set(copy)
end

-- Utile aux tests et au diagnostic : un compteur qui ne redescend jamais
-- signale des composants detruits sans liberer leur peintre.
function Theme.painterCount()
    local n = 0
    for _ in pairs(painters) do n = n + 1 end
    return n
end

return Theme
end

__modules["UI.Utility"] = function()
--=============================================================================
-- UTILITY — fabrique d'instances, Maid, animations
--=============================================================================
--  Le Maid est la piece qui rend Destroy() fiable : chaque composant y depose
--  ses instances, ses connexions et son peintre de theme, et n'a plus qu'a
--  appeler maid:Destroy(). Sans lui, chaque composant reimplemente son propre
--  nettoyage et en oublie une partie — typiquement les connexions, qui
--  maintiennent l'objet en vie et continuent de tourner.
--=============================================================================

local TweenService = game:GetService("TweenService")

local Utility = {}

---------------------------------------------------------------------------
-- Fabrique
---------------------------------------------------------------------------

-- Parent est applique EN DERNIER : affecter les proprietes apres le
-- parentage provoque un reflow par propriete cote moteur.
function Utility.new(className, props, children)
    local instance = Instance.new(className)
    local parent = nil

    if props then
        for key, value in pairs(props) do
            if key == "Parent" then
                parent = value
            else
                instance[key] = value
            end
        end
    end

    if children then
        for _, child in ipairs(children) do child.Parent = instance end
    end

    if parent then instance.Parent = parent end
    return instance
end

function Utility.corner(radius, parent)
    return Utility.new("UICorner", {
        CornerRadius = UDim.new(0, radius or 4),
        Parent = parent,
    })
end

function Utility.stroke(color, thickness, parent)
    return Utility.new("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

function Utility.padding(parent, top, bottom, left, right)
    return Utility.new("UIPadding", {
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or top or 0),
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or left or 0),
        Parent = parent,
    })
end

function Utility.list(parent, spacing, direction)
    return Utility.new("UIListLayout", {
        Padding = UDim.new(0, spacing or 4),
        FillDirection = direction or Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = parent,
    })
end

---------------------------------------------------------------------------
-- Animation
---------------------------------------------------------------------------

-- Discrete par defaut : 0.12 s, sortie douce. Les animations longues donnent
-- une impression de lourdeur sur mobile, ou chaque interaction compte.
Utility.FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
Utility.SLOW = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Utility.tween(instance, goal, info)
    local tween = TweenService:Create(instance, info or Utility.FAST, goal)
    tween:Play()
    return tween
end

---------------------------------------------------------------------------
-- Maid
---------------------------------------------------------------------------

local Maid = {}
Maid.__index = Maid

function Utility.maid()
    return setmetatable({ tasks = {}, dead = false }, Maid)
end

-- Accepte une connexion, une instance, une fonction, ou un autre Maid.
-- Un seul point d'entree evite d'avoir a se souvenir du type de chaque tache.
function Maid:give(task)
    if self.dead then
        -- Deposer une tache sur un Maid deja detruit la libere aussitot :
        -- sinon elle fuirait silencieusement.
        Maid.dispose(task)
        return task
    end
    table.insert(self.tasks, task)
    return task
end

function Maid.dispose(task)
    if task == nil then return end
    local kind = typeof(task)

    if kind == "RBXScriptConnection" then
        task:Disconnect()
    elseif kind == "Instance" then
        task:Destroy()
    elseif kind == "function" then
        task()
    elseif kind == "table" then
        if task.Destroy then task:Destroy() end
    end
end

function Maid:Destroy()
    if self.dead then return end
    self.dead = true
    -- Ordre inverse : les enfants sont liberes avant leurs parents.
    for i = #self.tasks, 1, -1 do
        local ok, err = pcall(Maid.dispose, self.tasks[i])
        if not ok then warn("[UI] nettoyage : " .. tostring(err)) end
        self.tasks[i] = nil
    end
end

function Maid:count() return #self.tasks end

---------------------------------------------------------------------------
-- Divers
---------------------------------------------------------------------------

-- Rounding = 0 doit rendre un ENTIER, pas un flottant qui vaut un entier :
-- une division rend toujours un flottant, et le slider affichait donc "20.0".
function Utility.round(value, decimals)
    decimals = decimals or 0
    if decimals <= 0 then return math.floor(value + 0.5) end
    local factor = 10 ^ decimals
    return math.floor(value * factor + 0.5) / factor
end

-- Affichage stable : "20" pour un entier, "0.30" et non "0.3" quand deux
-- decimales sont demandees.
function Utility.format(value, decimals)
    if (decimals or 0) <= 0 then return tostring(math.floor(value + 0.5)) end
    return string.format("%." .. decimals .. "f", value)
end

function Utility.clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

-- Conteneur d'affichage. gethui() isole l'interface de PlayerGui, ou le jeu
-- (ou un autre script) peut la parcourir ; on y retombe s'il est absent.
function Utility.screenParent()
    local ok, hidden = pcall(function() return gethui and gethui() end)
    if ok and hidden then return hidden end

    local players = game:GetService("Players")
    local player = players.LocalPlayer
    return player and player:FindFirstChildOfClass("PlayerGui") or nil
end

return Utility
end

__modules["UI.Window"] = function()
--=============================================================================
-- WINDOW — cadre, barre de titre, barre laterale, zone de contenu
--=============================================================================
--  Mise en page : une barre de titre de 30 pixels, une barre laterale a 25 %
--  de la largeur (avec un plancher en pixels, sinon elle devient illisible
--  sur telephone), le reste pour le contenu.
--
--  Le redimensionnement passe par un UIScale pilote par la taille du
--  viewport, pas par un recalcul de chaque element : une seule valeur a
--  ajuster, et les proportions restent celles pensees au depart. La
--  connexion qui l'ecoute est unique et se coupe avec la fenetre.
--=============================================================================

local Input = require("UI.Input")
local Tab = require("UI.Tab")
local Theme = require("UI.Theme")
local Utility = require("UI.Utility")

local Window = {}
Window.__index = Window

local TOPBAR_HEIGHT = 30
local SIDEBAR_SCALE = 0.25
local SIDEBAR_MIN = 92
local SIDEBAR_MAX = 170

function Window.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Window)
    local maid = Utility.maid()

    self.maid = maid
    self.tabs = {}
    self.tabCount = 0
    self.activeTab = nil
    self.minimized = false
    self.visible = true
    self.onClose = opts.OnClose
    self.destroyOnClose = opts.DestroyOnClose == true

    local baseSize = opts.Size or UDim2.fromOffset(600, 400)
    self.baseWidth = baseSize.X.Offset > 0 and baseSize.X.Offset or 600
    self.baseHeight = baseSize.Y.Offset > 0 and baseSize.Y.Offset or 400

    if opts.Theme then Theme.set(opts.Theme) end

    ---------------------------------------------------------------------
    -- Racine
    ---------------------------------------------------------------------

    local gui = Utility.new("ScreenGui", {
        Name = "StrawberryUI",
        -- Les coordonnees ecran et les AbsolutePosition coincident : le
        -- placement du menu deroulant en depend.
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 100,
        Parent = Utility.screenParent(),
    })
    maid:give(gui)

    local scale = Utility.new("UIScale", { Scale = 1, Parent = gui })

    local main = Utility.new("Frame", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = opts.Position or UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(self.baseWidth, self.baseHeight),
        BackgroundColor3 = Theme.color("Window"),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = gui,
    })
    Utility.corner(7, main)
    local mainStroke = Utility.stroke(Theme.color("Border"), 1, main)

    ---------------------------------------------------------------------
    -- Barre de titre
    ---------------------------------------------------------------------

    local topbar = Utility.new("Frame", {
        Name = "Topbar",
        Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
        BackgroundColor3 = Theme.color("Topbar"),
        BorderSizePixel = 0,
        Parent = main,
    })

    -- Un UICorner arrondit les quatre coins : ce petit cache redonne des
    -- angles droits en bas de la barre, contre le corps de la fenetre.
    Utility.corner(7, topbar)
    local cornerPatch = Utility.new("Frame", {
        Name = "CornerPatch",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 7),
        BackgroundColor3 = Theme.color("Topbar"),
        BorderSizePixel = 0,
        Parent = topbar,
    })

    local separator = Utility.new("Frame", {
        Name = "Separator",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.color("Border"),
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = topbar,
    })

    -- Titre et sous-titre dans un flux horizontal : le sous-titre se place
    -- apres le titre quelle que soit sa longueur. Calculer sa position a
    -- partir du nombre de caracteres serait faux des le premier changement
    -- de police ou de titre.
    local titleGroup = Utility.new("Frame", {
        Name = "TitleGroup",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 11, 0.5, 0),
        Size = UDim2.new(1, -80, 1, 0),
        BackgroundTransparency = 1,
        Parent = topbar,
    })
    Utility.new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),
        Parent = titleGroup,
    })

    local title = Utility.new("TextLabel", {
        Name = "Title",
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = opts.Title or "Hub",
        TextSize = 13,
        TextColor3 = Theme.color("Text"),
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1,
        Parent = titleGroup,
    })

    local subtitle = Utility.new("TextLabel", {
        Name = "Subtitle",
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = opts.Subtitle or "",
        TextSize = 11,
        TextColor3 = Theme.color("MutedText"),
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 2,
        Parent = titleGroup,
    })

    local function topbarButton(text, offset, name)
        local button = Utility.new("TextButton", {
            Name = name,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -offset, 0.5, 0),
            -- 22 pixels : en dessous, la cible devient difficile a toucher.
            Size = UDim2.fromOffset(22, 22),
            BackgroundColor3 = Theme.color("Element"),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = Enum.Font.GothamBold,
            Text = text,
            TextSize = 12,
            TextColor3 = Theme.color("MutedText"),
            Parent = topbar,
        })
        Utility.corner(4, button)
        return button
    end

    local closeButton = topbarButton("X", 7, "Close")
    local minimizeButton = topbarButton("-", 33, "Minimize")

    ---------------------------------------------------------------------
    -- Corps
    ---------------------------------------------------------------------

    local body = Utility.new("Frame", {
        Name = "Body",
        Position = UDim2.new(0, 0, 0, TOPBAR_HEIGHT),
        Size = UDim2.new(1, 0, 1, -TOPBAR_HEIGHT),
        BackgroundTransparency = 1,
        Parent = main,
    })

    local sidebar = Utility.new("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(SIDEBAR_SCALE, 0, 1, 0),
        BackgroundColor3 = Theme.color("Sidebar"),
        BorderSizePixel = 0,
        Parent = body,
    })

    -- Bornes en pixels : 25 % d'un ecran de telephone ne suffit pas a lire
    -- un nom d'onglet, et 25 % d'un grand ecran gaspille la place.
    Utility.new("UISizeConstraint", {
        MinSize = Vector2.new(SIDEBAR_MIN, 0),
        MaxSize = Vector2.new(SIDEBAR_MAX, math.huge),
        Parent = sidebar,
    })

    local sidebarLine = Utility.new("Frame", {
        Name = "Edge",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = Theme.color("Border"),
        BorderSizePixel = 0,
        Parent = sidebar,
    })

    local tabList = Utility.new("ScrollingFrame", {
        Name = "Tabs",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Parent = sidebar,
    })
    Utility.padding(tabList, 8, 8, 6, 6)
    Utility.list(tabList, 2)

    local content = Utility.new("Frame", {
        Name = "Content",
        Position = UDim2.new(SIDEBAR_SCALE, 1, 0, 0),
        Size = UDim2.new(1 - SIDEBAR_SCALE, -1, 1, 0),
        BackgroundColor3 = Theme.color("Background"),
        BorderSizePixel = 0,
        Parent = body,
    })

    -- Le contenu doit suivre la largeur reelle de la barre laterale, qui est
    -- contrainte en pixels : une position en pourcentage seul laisserait un
    -- trou ou un chevauchement des que la contrainte s'applique.
    local function syncContent()
        local width = sidebar.AbsoluteSize.X
        content.Position = UDim2.new(0, width + 1, 0, 0)
        content.Size = UDim2.new(1, -(width + 1), 1, 0)
    end

    maid:give(sidebar:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncContent))
    syncContent()

    ---------------------------------------------------------------------
    -- Couche de superposition (menus deroulants)
    ---------------------------------------------------------------------

    local overlay = Utility.new("Frame", {
        Name = "Overlay",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 50,
        Parent = gui,
    })

    self.gui, self.main, self.topbar, self.body = gui, main, topbar, body
    self.sidebar, self.tabList, self.content, self.overlay = sidebar, tabList, content, overlay
    self.title, self.subtitle, self.scale = title, subtitle, scale
    self.context = { overlay = overlay, window = self }

    ---------------------------------------------------------------------
    -- Theme
    ---------------------------------------------------------------------

    local painterId = Theme.register(function(theme)
        main.BackgroundColor3 = theme.Window
        mainStroke.Color = theme.Border
        topbar.BackgroundColor3 = theme.Topbar
        cornerPatch.BackgroundColor3 = theme.Topbar
        separator.BackgroundColor3 = theme.Border
        sidebar.BackgroundColor3 = theme.Sidebar
        sidebarLine.BackgroundColor3 = theme.Border
        content.BackgroundColor3 = theme.Background
        title.TextColor3 = theme.Text
        subtitle.TextColor3 = theme.MutedText
        closeButton.TextColor3 = theme.MutedText
        minimizeButton.TextColor3 = theme.MutedText
    end)
    maid:give(function() Theme.unregister(painterId) end)

    ---------------------------------------------------------------------
    -- Interactions de la barre de titre
    ---------------------------------------------------------------------

    for _, entry in ipairs({
        { button = closeButton, accent = true },
        { button = minimizeButton, accent = false },
    }) do
        for _, connection in ipairs(Input.onHover(entry.button,
            function()
                Utility.tween(entry.button, { BackgroundTransparency = 0 })
                entry.button.BackgroundColor3 = entry.accent
                    and Theme.color("AccentMuted") or Theme.color("ElementHover")
                entry.button.TextColor3 = Theme.color("Text")
            end,
            function()
                Utility.tween(entry.button, { BackgroundTransparency = 1 })
                entry.button.TextColor3 = Theme.color("MutedText")
            end)) do
            maid:give(connection)
        end
    end

    maid:give(Input.onActivate(closeButton, function() self:Close() end))
    maid:give(Input.onActivate(minimizeButton, function() self:ToggleMinimize() end))

    local dragConnection, dragStop = Input.makeDraggable(main, topbar)
    maid:give(dragConnection)
    maid:give(dragStop)

    ---------------------------------------------------------------------
    -- Reactivite
    ---------------------------------------------------------------------

    self:applyResponsive()

    local camera = workspace.CurrentCamera
    if camera then
        maid:give(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            self:applyResponsive()
        end))
    end

    return self
end

---------------------------------------------------------------------------
-- Reactivite
---------------------------------------------------------------------------

-- Un seul facteur d'echelle, borne : en dessous de 0.62 le texte devient
-- illisible, mieux vaut alors laisser defiler que retrecir encore.
function Window:applyResponsive()
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

    local factor = math.min(
        1,
        (viewport.X * 0.94) / self.baseWidth,
        (viewport.Y * 0.90) / self.baseHeight)

    self.scale.Scale = Utility.clamp(factor, 0.62, 1)
end

---------------------------------------------------------------------------
-- Onglets
---------------------------------------------------------------------------

function Window:CreateTab(opts)
    self.tabCount = self.tabCount + 1
    local tab = Tab.new(self, opts or {}, self.tabCount)
    table.insert(self.tabs, tab)
    self.maid:give(tab)

    -- Le premier onglet cree devient l'onglet actif : ouvrir une fenetre sur
    -- une zone de contenu vide n'a pas de sens.
    if not self.activeTab then self:SelectTab(tab) end
    return tab
end

function Window:SelectTab(tab)
    if self.activeTab == tab then return end
    if self.activeTab then self.activeTab:Hide() end
    self.activeTab = tab
    tab:Show()
end

function Window:GetTab(name)
    for _, tab in ipairs(self.tabs) do
        if tab.name == name then return tab end
    end
    return nil
end

---------------------------------------------------------------------------
-- Etat
---------------------------------------------------------------------------

function Window:Show()
    self.visible = true
    self.gui.Enabled = true
    self.main.Visible = true
    return self
end

function Window:Hide()
    self.visible = false
    self.main.Visible = false
    return self
end

function Window:Toggle()
    if self.visible then return self:Hide() end
    return self:Show()
end

function Window:IsVisible() return self.visible end

-- Fermer masque et previent l'appelant. Detruire est une action distincte :
-- une fenetre fermee doit pouvoir etre rouverte avec son etat intact, sauf
-- si l'appelant demande explicitement le contraire.
function Window:Close()
    if self.onClose then
        local ok, err = pcall(self.onClose, self)
        if not ok then warn("[UI] OnClose : " .. tostring(err)) end
    end
    if self.destroyOnClose then return self:Destroy() end
    return self:Hide()
end

function Window:ToggleMinimize()
    self.minimized = not self.minimized

    local goal = self.minimized
        and UDim2.fromOffset(self.baseWidth, TOPBAR_HEIGHT)
        or UDim2.fromOffset(self.baseWidth, self.baseHeight)

    -- ClipsDescendants est deja actif sur la fenetre : le corps disparait
    -- derriere le bord pendant l'animation, sans avoir a le masquer.
    Utility.tween(self.main, { Size = goal }, Utility.SLOW)
    return self
end

function Window:IsMinimized() return self.minimized end

function Window:SetTitle(text)
    self.title.Text = tostring(text or "")
    return self
end

function Window:SetSubtitle(text)
    self.subtitle.Text = tostring(text or "")
    return self
end

function Window:SetSize(size)
    if typeof(size) == "UDim2" then
        self.baseWidth = size.X.Offset > 0 and size.X.Offset or self.baseWidth
        self.baseHeight = size.Y.Offset > 0 and size.Y.Offset or self.baseHeight
    end
    if not self.minimized then
        Utility.tween(self.main, { Size = UDim2.fromOffset(self.baseWidth, self.baseHeight) })
    end
    self:applyResponsive()
    return self
end

function Window:SetPosition(position)
    self.main.Position = position
    return self
end

function Window:Destroy()
    self.tabs = {}
    self.activeTab = nil
    self.onClose = nil
    self.maid:Destroy()
end

return Window
end

__modules["UI"] = function()
--=============================================================================
-- UI — point d'entree de la bibliotheque
--=============================================================================
--  Une bibliotheque, pas un singleton cache : la table renvoyee garde la
--  liste de ses fenetres pour pouvoir tout liberer d'un appel, ce qui est
--  indispensable quand un hub se recharge par-dessus lui-meme.
--
--  Dependances : aucune. Uniquement des services Roblox standards
--  (TweenService, UserInputService, Players). `gethui` est utilise s'il
--  existe, avec repli sur PlayerGui.
--=============================================================================

local Notification = require("UI.Notification")
local Theme = require("UI.Theme")
local Utility = require("UI.Utility")
local Window = require("UI.Window")

local UI = {}
UI.__index = UI

UI.Theme = Theme
UI.Utility = Utility
UI.windows = {}

local notifier

function UI:CreateWindow(opts)
    local window = Window.new(opts or {})
    table.insert(UI.windows, window)
    return window
end

-- Le gestionnaire de notifications est cree a la premiere utilisation :
-- un hub qui n'en emet jamais ne paie pas un ScreenGui pour rien.
function UI:Notify(opts)
    if not notifier or notifier.destroyed then
        notifier = Notification.new()
    end
    return notifier:Notify(opts)
end

function UI:ClearNotifications()
    if notifier then notifier:Clear() end
end

-- Applique une palette a chaud. Aucun composant n'est reconstruit : l'etat
-- des toggles, l'onglet actif et la position de la fenetre sont conserves.
function UI:SetTheme(newTheme)
    return Theme.set(newTheme)
end

function UI:GetTheme() return Theme.get() end
function UI:ResetTheme() return Theme.reset() end

function UI:Destroy()
    for index = #UI.windows, 1, -1 do
        local window = UI.windows[index]
        pcall(function() window:Destroy() end)
        UI.windows[index] = nil
    end
    if notifier then
        notifier:Destroy()
        notifier = nil
    end
end

return UI
end

__modules["uidemo"] = function()
--=============================================================================
-- DEMO — exemple complet et executable de la bibliotheque UI
--=============================================================================
--  Point d'entree alternatif du bundle :
--      python3 tools/pack.py --entry uidemo --bundle-only dist/StrawberryUI.lua
--
--  Tout ce qui suit est fonctionnel : les callbacks impriment reellement, les
--  composants gardent leur etat, et les references renvoyees permettent de
--  piloter l'interface depuis le reste du script.
--=============================================================================

local UI = require("UI")

local Window = UI:CreateWindow({
    Title = "Blox Fruits",
    Subtitle = "by strawberry",
    Size = UDim2.fromOffset(600, 400),
})

---------------------------------------------------------------------------
-- Farm
---------------------------------------------------------------------------

local Farm = Window:CreateTab({ Name = "Farm" })
local AutoFarm = Farm:CreateSection({ Name = "Auto Farm" })

local statusLabel

AutoFarm:CreateToggle({
    Name = "Auto Farm",
    Description = "Farm automatiquement les mobs de la quete active",
    Default = false,
    Callback = function(value)
        print("Auto Farm:", value)
        if statusLabel then
            statusLabel:SetText("Statut : " .. (value and "en cours" or "arrete"))
        end
        UI:Notify({
            Title = "Auto Farm",
            Content = value and "Farm demarre" or "Farm arrete",
            Duration = 3,
        })
    end,
})

AutoFarm:CreateDropdown({
    Name = "Farm Mode",
    Values = { "Level", "Mastery", "Boss", "Material" },
    Default = "Level",
    Callback = function(value) print("Mode:", value) end,
})

AutoFarm:CreateSlider({
    Name = "Distance",
    Min = 5,
    Max = 100,
    Default = 20,
    Rounding = 0,
    Callback = function(value) print("Distance:", value) end,
})

AutoFarm:CreateButton({
    Name = "Start Farm",
    Description = "Lance le cycle de farm immediatement",
    Arrow = true,
    Callback = function() print("Start") end,
})

local Status = Farm:CreateSection({ Name = "Status" })
statusLabel = Status:CreateLabel({ Name = "Statut : arrete" })

---------------------------------------------------------------------------
-- Teleport
---------------------------------------------------------------------------

local Teleport = Window:CreateTab({ Name = "Teleport" })
local Travel = Teleport:CreateSection({ Name = "Travel" })

Travel:CreateButton({
    Name = "Teleport to Sea 1",
    Description = "Main",
    Arrow = true,
    Callback = function() print("Sea 1") end,
})

Travel:CreateButton({
    Name = "Teleport to Sea 2",
    Description = "Dressrosa",
    Arrow = true,
    Callback = function() print("Sea 2") end,
})

Travel:CreateButton({
    Name = "Teleport to Sea 3",
    Description = "Zou",
    Arrow = true,
    Callback = function() print("Sea 3") end,
})

local Islands = Teleport:CreateSection({ Name = "Islands" })

local islandDropdown = Islands:CreateDropdown({
    Name = "Select Island",
    Values = {
        "Starter Island", "Jungle", "Pirate Village",
        "Desert", "Frozen Village", "Marine Fortress", "Skylands",
    },
    Default = "Starter Island",
    Callback = function(value) print("Island:", value) end,
})

Islands:CreateButton({
    Name = "Teleport to Island",
    Callback = function()
        print("Teleport ->", islandDropdown:GetValue())
    end,
})

---------------------------------------------------------------------------
-- Misc — montre SetTheme a chaud et le rafraichissement d'un dropdown
---------------------------------------------------------------------------

local Misc = Window:CreateTab({ Name = "Misc" })
local Interface = Misc:CreateSection({ Name = "Interface" })

Interface:CreateDropdown({
    Name = "Accent",
    Values = { "Rouge", "Bleu", "Vert", "Violet" },
    Default = "Rouge",
    Callback = function(value)
        local palettes = {
            Rouge  = Color3.fromRGB(196, 54, 54),
            Bleu   = Color3.fromRGB(66, 122, 210),
            Vert   = Color3.fromRGB(72, 172, 110),
            Violet = Color3.fromRGB(140, 96, 200),
        }
        -- Changement a chaud : rien n'est reconstruit, l'etat est conserve.
        UI:SetTheme({ Accent = palettes[value] })
    end,
})

Interface:CreateDivider()

Interface:CreateButton({
    Name = "Rafraichir la liste des iles",
    Description = "Demontre Dropdown:Refresh",
    Callback = function()
        islandDropdown:Refresh({ "Starter Island", "Jungle", "Desert" })
        UI:Notify({ Title = "Iles", Content = "Liste rafraichie", Duration = 2 })
    end,
})

Interface:CreateButton({
    Name = "Fermer l'interface",
    Arrow = true,
    Callback = function() Window:Hide() end,
})

UI:Notify({
    Title = "Strawberry UI",
    Content = "Interface chargee",
    Duration = 4,
})

return { UI = UI, Window = Window }
end

return require("uidemo")
