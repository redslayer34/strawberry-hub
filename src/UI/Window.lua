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
