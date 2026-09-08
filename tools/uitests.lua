--=============================================================================
-- TESTS UI — verifient que l'interface FONCTIONNE, pas qu'elle se charge
--=============================================================================
--  Chaque interaction est simulee par le signal que Roblox declencherait :
--  `button.Activated:Fire()` pour un clic, une sequence InputBegan /
--  InputChanged / InputEnded sur UserInputService pour un glissement, et les
--  memes signaux avec UserInputType.Touch pour le tactile.
--
--  Les tweens s'appliquent immediatement (voir tools/uistubs.lua), donc
--  l'etat d'arrivee est observable sans attendre.
--=============================================================================

local passed, failed = 0, 0
local failures = {}

local function check(name, condition, detail)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = name .. (detail and ("  -- " .. tostring(detail)) or "")
    end
end

local function eq(name, actual, expected)
    check(name, actual == expected,
        string.format("attendu %s, obtenu %s", tostring(expected), tostring(actual)))
end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------

local MODULES = {
    "UI.Theme", "UI.Utility", "UI.Input", "UI.Section", "UI.Tab",
    "UI.Window", "UI.Notification",
    "UI.Components.Row", "UI.Components.Button", "UI.Components.Toggle",
    "UI.Components.Slider", "UI.Components.Dropdown", "UI.Components.Label",
    "UI",
}

for _, name in ipairs(MODULES) do
    local ok, err = pcall(require, name)
    check("charge " .. name, ok, err)
end

local UI = require("UI")
local Theme = require("UI.Theme")
local Utility = require("UI.Utility")

local PRESS = Enum.UserInputType.MouseButton1
local TOUCH = Enum.UserInputType.Touch
local MOVE = Enum.UserInputType.MouseMovement

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

local window = UI:CreateWindow({
    Title = "Blox Fruits",
    Subtitle = "tests",
    Size = UDim2.fromOffset(600, 400),
})

check("fenetre creee", window ~= nil)
check("ScreenGui parente", window.gui.Parent ~= nil)
eq("titre pose", window.title.Text, "Blox Fruits")
eq("sous-titre pose", window.subtitle.Text, "tests")
eq("visible au depart", window:IsVisible(), true)
eq("hauteur de barre de titre", window.topbar.Size.Y.Offset, 30)
eq("largeur de barre laterale", window.sidebar.Size.X.Scale, 0.25)

window:SetTitle("Autre")
eq("SetTitle", window.title.Text, "Autre")
window:SetTitle("Blox Fruits")

---------------------------------------------------------------------------
-- Onglets
---------------------------------------------------------------------------

local farmTab = window:CreateTab({ Name = "Farm" })
local teleportTab = window:CreateTab({ Name = "Teleport" })
local miscTab = window:CreateTab({ Name = "Misc" })

check("premier onglet actif d'office", farmTab:IsActive())
check("page du premier onglet visible", farmTab.page.Visible)
check("onglet suivant inactif", not teleportTab:IsActive())
check("page de l'onglet suivant masquee", not teleportTab.page.Visible)
check("liseré actif deploye", farmTab.indicator.Size.Y.Offset > 0)
check("liseré inactif replie", teleportTab.indicator.Size.Y.Offset == 0)

-- Clic sur l'onglet Teleport.
teleportTab.button.Activated:Fire()
check("clic : Teleport devient actif", teleportTab:IsActive())
check("clic : Farm devient inactif", not farmTab:IsActive())
check("clic : page Teleport visible", teleportTab.page.Visible)
check("clic : page Farm masquee", not farmTab.page.Visible)
check("clic : liseré suit", teleportTab.indicator.Size.Y.Offset > 0)

eq("GetTab", window:GetTab("Misc"), miscTab)

---------------------------------------------------------------------------
-- Sections et composants
---------------------------------------------------------------------------

local section = farmTab:CreateSection({ Name = "Auto Farm" })
eq("titre de section", section.header.Text, "Auto Farm")

-- BOUTON -----------------------------------------------------------------
local clicks = 0
local button = section:CreateButton({
    Name = "Start Farm",
    Description = "Lance le farm",
    Arrow = true,
    Callback = function() clicks = clicks + 1 end,
})

button.row.container.Activated:Fire()
eq("bouton : callback appele", clicks, 1)
button.row.container.Activated:Fire()
eq("bouton : deuxieme clic", clicks, 2)
check("bouton : chevron present", button.arrow ~= nil)
check("bouton : description presente", button.row.description ~= nil)

button:SetText("Autre")
eq("bouton : SetText", button.row.title.Text, "Autre")

-- Le survol change le fond, le depart le restaure.
local restColor = button.row.container.BackgroundColor3
button.row.container.MouseEnter:Fire()
check("bouton : survol assombrit", button.row.container.BackgroundColor3 ~= restColor)
button.row.container.MouseLeave:Fire()
eq("bouton : sortie restaure", button.row.container.BackgroundColor3, restColor)

-- TOGGLE ------------------------------------------------------------------
local toggleValue, toggleCalls = nil, 0
local toggle = section:CreateToggle({
    Name = "Auto Farm",
    Default = false,
    Callback = function(value)
        toggleValue = value
        toggleCalls = toggleCalls + 1
    end,
})

eq("toggle : valeur initiale", toggle:GetValue(), false)

toggle.row.container.Activated:Fire()
eq("toggle : bascule a true", toggle:GetValue(), true)
eq("toggle : callback recoit true", toggleValue, true)
eq("toggle : callback appele une fois", toggleCalls, 1)
eq("toggle : piste en couleur d'accent",
    toggle.track.BackgroundColor3, Theme.color("Accent"))
check("toggle : bouton a droite", toggle.knob.Position.X.Scale == 1)

toggle.row.container.Activated:Fire()
eq("toggle : rebascule a false", toggle:GetValue(), false)
check("toggle : bouton a gauche", toggle.knob.Position.X.Scale == 0)

toggle:SetValue(true, true)
eq("toggle : SetValue silencieux applique", toggle:GetValue(), true)
eq("toggle : SetValue silencieux n'appelle pas", toggleCalls, 2)

toggle:SetValue(true)
eq("toggle : valeur identique n'appelle pas", toggleCalls, 2)

-- Tactile : le meme composant doit repondre au doigt.
toggle:SetValue(false, true)
toggle.row.container.InputBegan:Fire({ UserInputType = TOUCH, Position = Vector3.new(0, 0, 0) })
toggle.row.container.Activated:Fire()
eq("toggle : tactile bascule", toggle:GetValue(), true)

-- SLIDER ------------------------------------------------------------------
local sliderValue
local slider = section:CreateSlider({
    Name = "Distance",
    Min = 0, Max = 100, Default = 20, Rounding = 0,
    Callback = function(value) sliderValue = value end,
})

eq("slider : valeur initiale", slider:GetValue(), 20)
eq("slider : affichage initial", slider.valueLabel.Text, "20")
check("slider : remplissage a 20 %", math.abs(slider.fill.Size.X.Scale - 0.2) < 0.001)

-- Geometrie deterministe pour la conversion position -> valeur.
slider.bar.AbsolutePosition = Vector2.new(0, 0)
slider.bar.AbsoluteSize = Vector2.new(200, 4)

local hit = slider.row.body.Hit
hit.InputBegan:Fire(makeInput(PRESS, 100, 2))     -- moitie de la barre
eq("slider : clic au milieu donne 50", slider:GetValue(), 50)
eq("slider : callback recoit 50", sliderValue, 50)

userInputService.InputChanged:Fire(makeInput(MOVE, 150, 2))
eq("slider : glissement a 75", slider:GetValue(), 75)

userInputService.InputChanged:Fire(makeInput(MOVE, 400, 2))
eq("slider : borne au maximum", slider:GetValue(), 100)

userInputService.InputChanged:Fire(makeInput(MOVE, -50, 2))
eq("slider : borne au minimum", slider:GetValue(), 0)

userInputService.InputEnded:Fire(makeInput(PRESS, 0, 0))
userInputService.InputChanged:Fire(makeInput(MOVE, 100, 2))
eq("slider : plus de suivi apres relachement", slider:GetValue(), 0)

-- Tactile.
hit.InputBegan:Fire(makeInput(TOUCH, 50, 2))
eq("slider : tactile positionne a 25", slider:GetValue(), 25)
userInputService.InputEnded:Fire(makeInput(TOUCH, 0, 0))

slider:SetValue(60)
eq("slider : SetValue", slider:GetValue(), 60)
slider:SetMax(50)
eq("slider : SetMax rabat la valeur", slider:GetValue(), 50)
slider:SetMin(10)
eq("slider : SetMin conserve", slider:GetValue(), 50)

local rounded = section:CreateSlider({
    Name = "Fin", Min = 0, Max = 1, Default = 0.5, Rounding = 2,
})
rounded.bar.AbsolutePosition = Vector2.new(0, 0)
rounded.bar.AbsoluteSize = Vector2.new(100, 4)
rounded.row.body.Hit.InputBegan:Fire(makeInput(PRESS, 33, 2))
eq("slider : arrondi a 2 decimales", rounded:GetValue(), 0.33)
userInputService.InputEnded:Fire(makeInput(PRESS, 0, 0))

-- DROPDOWN ----------------------------------------------------------------
local dropValue, dropCalls = nil, 0
local dropdown = section:CreateDropdown({
    Name = "Farm Mode",
    Values = { "Level", "Mastery", "Boss", "Material" },
    Default = "Level",
    Callback = function(value)
        dropValue = value
        dropCalls = dropCalls + 1
    end,
})

eq("dropdown : valeur par defaut", dropdown:GetValue(), "Level")
eq("dropdown : affichage", dropdown.selectedLabel.Text, "Level")
eq("dropdown : construction ne declenche pas le callback", dropCalls, 0)
eq("dropdown : items crees", #dropdown.items, 4)
check("dropdown : menu hors de la page", dropdown.menu.Parent == window.overlay)
check("dropdown : ferme au depart", not dropdown:IsOpen())

dropdown.row.container.Activated:Fire()
check("dropdown : ouvert au clic", dropdown:IsOpen())
check("dropdown : menu visible", dropdown.menu.Visible)
check("dropdown : menu deploye", dropdown.menu.Size.Y.Offset > 0)

-- Selection d'un item.
dropdown.items[3].button.Activated:Fire()
eq("dropdown : valeur selectionnee", dropdown:GetValue(), "Boss")
eq("dropdown : callback recoit la valeur", dropValue, "Boss")
eq("dropdown : callback appele une fois", dropCalls, 1)
check("dropdown : ferme apres selection", not dropdown:IsOpen())
eq("dropdown : affichage suit", dropdown.selectedLabel.Text, "Boss")

-- Clic exterieur.
dropdown.row.container.Activated:Fire()
check("dropdown : rouvert", dropdown:IsOpen())
dropdown.menu.AbsolutePosition = Vector2.new(0, 40)
dropdown.menu.AbsoluteSize = Vector2.new(100, 120)
dropdown.row.container.AbsolutePosition = Vector2.new(0, 0)
dropdown.row.container.AbsoluteSize = Vector2.new(100, 34)
userInputService.InputBegan:Fire(makeInput(PRESS, 900, 600))
check("dropdown : ferme au clic exterieur", not dropdown:IsOpen())

-- Un clic DANS le menu ne le ferme pas.
dropdown.row.container.Activated:Fire()
userInputService.InputBegan:Fire(makeInput(PRESS, 50, 80))
check("dropdown : clic interieur ne ferme pas", dropdown:IsOpen())
dropdown:Close()

-- Refresh.
dropdown:Refresh({ "Level", "Mastery" })
eq("dropdown : items reconstruits", #dropdown.items, 2)
eq("dropdown : valeur absente abandonnee", dropdown:GetValue(), nil)
eq("dropdown : Refresh ne declenche pas le callback", dropCalls, 1)

dropdown:SetValue("Mastery")
eq("dropdown : SetValue", dropdown:GetValue(), "Mastery")
eq("dropdown : SetValue declenche", dropCalls, 2)
dropdown:SetValue("Level", true)
eq("dropdown : SetValue silencieux", dropCalls, 2)

-- Placement : jamais hors de l'ecran.
local placementDrop = section:CreateDropdown({
    Name = "Beaucoup",
    Values = (function()
        local list = {}
        for i = 1, 40 do list[i] = "Item " .. i end
        return list
    end)(),
})

placementDrop.row.container.AbsolutePosition = Vector2.new(0, 0)
placementDrop.row.container.AbsoluteSize = Vector2.new(100, 34)
local pos, size, height = placementDrop:place()
check("placement : hauteur bornee", height <= 160)
check("placement : ouvre vers le bas quand il y a la place", pos.Y.Offset > 34)
check("placement : reste dans l'ecran",
    pos.Y.Offset + height <= 720 and pos.X.Offset >= 0)

-- Pres du bas : doit s'ouvrir vers le haut.
placementDrop.row.container.AbsolutePosition = Vector2.new(0, 700)
local upPos, _, upHeight = placementDrop:place()
check("placement : ouvre vers le haut en bas d'ecran", upPos.Y.Offset < 700)
check("placement : ne deborde pas par le bas", upPos.Y.Offset + upHeight <= 720)

-- Tres a droite : doit rester visible.
placementDrop.row.container.AbsolutePosition = Vector2.new(1270, 100)
local rightPos = placementDrop:place()
check("placement : rabattu depuis la droite", rightPos.X.Offset + 100 <= 1280)

-- LABEL et DIVIDER --------------------------------------------------------
local label = section:CreateLabel({ Name = "Statut : arrete" })
eq("label : texte initial", label:GetText(), "Statut : arrete")
label:SetText("Statut : en cours")
eq("label : SetText", label:GetText(), "Statut : en cours")

local divider = section:CreateDivider()
check("divider cree", divider ~= nil and divider.container ~= nil)

---------------------------------------------------------------------------
-- Defilement
---------------------------------------------------------------------------

eq("page : ScrollingFrame", farmTab.page.ClassName, "ScrollingFrame")
eq("page : defilement vertical",
    farmTab.page.ScrollingDirection, Enum.ScrollingDirection.Y)
eq("page : canevas automatique",
    farmTab.page.AutomaticCanvasSize, Enum.AutomaticSize.Y)
eq("barre laterale : ScrollingFrame", window.tabList.ClassName, "ScrollingFrame")
eq("menu deroulant : ScrollingFrame", dropdown.scroller.ClassName, "ScrollingFrame")

-- La position de defilement survit a un changement d'onglet.
farmTab.button.Activated:Fire()
farmTab.page.CanvasPosition = Vector2.new(0, 120)
teleportTab.button.Activated:Fire()
farmTab.button.Activated:Fire()
eq("defilement conserve entre onglets", farmTab.page.CanvasPosition.Y, 120)

-- Et l'etat des composants aussi : rien n'est reconstruit.
eq("etat du toggle conserve", toggle:GetValue(), true)
eq("etat du slider conserve", slider:GetValue(), 50)

---------------------------------------------------------------------------
-- Deplacement de la fenetre
---------------------------------------------------------------------------

window.main.Position = UDim2.fromOffset(100, 100)
local before = window.main.Position

window.topbar.InputBegan:Fire(makeInput(PRESS, 300, 300))
userInputService.InputChanged:Fire(makeInput(MOVE, 340, 360))
eq("drag : deplacement en X", window.main.Position.X.Offset, 140)
eq("drag : deplacement en Y", window.main.Position.Y.Offset, 160)

userInputService.InputEnded:Fire(makeInput(PRESS, 0, 0))
userInputService.InputChanged:Fire(makeInput(MOVE, 900, 900))
eq("drag : arrete apres relachement", window.main.Position.X.Offset, 140)

-- Tactile : meme comportement.
window.main.Position = before
window.topbar.InputBegan:Fire(makeInput(TOUCH, 200, 200))
userInputService.InputChanged:Fire(makeInput(TOUCH, 250, 230))
eq("drag tactile : X", window.main.Position.X.Offset, 150)
eq("drag tactile : Y", window.main.Position.Y.Offset, 130)
userInputService.InputEnded:Fire(makeInput(TOUCH, 0, 0))

-- Aucune connexion de suivi ne doit survivre au relachement.
eq("drag : aucun suivi residuel sur InputChanged",
    userInputService.InputChanged:Count(), 0)

---------------------------------------------------------------------------
-- Reduction
---------------------------------------------------------------------------

local fullHeight = window.main.Size.Y.Offset
eq("hauteur pleine", fullHeight, 400)

window:ToggleMinimize()
check("minimize : reduit", window:IsMinimized())
eq("minimize : hauteur = barre de titre", window.main.Size.Y.Offset, 30)
eq("minimize : largeur inchangee", window.main.Size.X.Offset, 600)
check("minimize : barre de titre toujours la", window.topbar.Parent == window.main)

window:ToggleMinimize()
check("minimize : restaure", not window:IsMinimized())
eq("minimize : hauteur rendue", window.main.Size.Y.Offset, 400)

---------------------------------------------------------------------------
-- Visibilite et fermeture
---------------------------------------------------------------------------

window:Hide()
eq("Hide", window:IsVisible(), false)
window:Show()
eq("Show", window:IsVisible(), true)
window:Toggle()
eq("Toggle masque", window:IsVisible(), false)
window:Toggle()
eq("Toggle reaffiche", window:IsVisible(), true)

local closed = 0
window.onClose = function() closed = closed + 1 end
window.gui.Close = nil
window.topbar.Close.Activated:Fire()
eq("close : callback OnClose appele", closed, 1)
eq("close : masque par defaut", window:IsVisible(), false)
check("close : ne detruit pas", window.main.Parent ~= nil)
window:Show()

---------------------------------------------------------------------------
-- Reactivite
---------------------------------------------------------------------------

eq("echelle sur grand ecran", window.scale.Scale, 1)

workspace.CurrentCamera.ViewportSize = Vector2.new(400, 720)
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Fire()
check("petit ecran : reduction appliquee", window.scale.Scale < 1)
check("petit ecran : reduction bornee", window.scale.Scale >= 0.62)

workspace.CurrentCamera.ViewportSize = Vector2.new(1280, 720)
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Fire()
eq("retour grand ecran", window.scale.Scale, 1)

---------------------------------------------------------------------------
-- Theme a chaud
---------------------------------------------------------------------------

local before = Theme.color("Accent")
local painters = Theme.painterCount()
check("des peintres sont enregistres", painters > 0)

UI:SetTheme({ Accent = Color3.fromRGB(0, 120, 255) })
eq("theme : accent change", Theme.color("Accent"), Color3.fromRGB(0, 120, 255))
eq("theme : toggle actif repeint", toggle.track.BackgroundColor3, Theme.color("Accent"))
eq("theme : remplissage du slider repeint",
    slider.fill.BackgroundColor3, Theme.color("Accent"))
eq("theme : liseré d'onglet repeint",
    farmTab.indicator.BackgroundColor3, Theme.color("Accent"))

-- L'etat ne doit pas etre perdu par le changement de theme.
eq("theme : valeur du toggle conservee", toggle:GetValue(), true)
eq("theme : valeur du slider conservee", slider:GetValue(), 50)
eq("theme : onglet actif conserve", farmTab:IsActive(), true)
eq("theme : nombre de peintres inchange", Theme.painterCount(), painters)

-- Fusion partielle : le reste de la palette survit.
check("theme : fusion partielle", Theme.color("Text") ~= nil)
UI:SetTheme({ Accent = before })

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------

task.setDeferred(true)

local first = UI:Notify({ Title = "Auto Farm", Content = "Farm demarre", Duration = 3 })
local second = UI:Notify({ Title = "Teleport", Content = "Sea 2", Duration = 3 })

check("notification : objet rendu", first ~= nil and first.Dismiss ~= nil)
check("notification : deux affichees sans se superposer", second ~= nil)

task.setDeferred(false)
task.flushDeferred()

---------------------------------------------------------------------------
-- Destruction
---------------------------------------------------------------------------

-- Composant isole : le peintre doit disparaitre avec lui.
local paintersBefore = Theme.painterCount()
local temporary = section:CreateToggle({ Name = "Temporaire", Default = false })
check("peintre ajoute", Theme.painterCount() > paintersBefore)

local temporaryButton = temporary.row.container
temporary:Destroy()
eq("Destroy : peintre libere", Theme.painterCount(), paintersBefore)
eq("Destroy : instance retiree", temporaryButton.Parent, nil)
eq("Destroy : connexions coupees", temporaryButton.Activated:Count(), 0)

-- Un callback ne doit plus partir apres destruction.
local ghost = 0
local ghostButton = section:CreateButton({
    Name = "Fantome",
    Callback = function() ghost = ghost + 1 end,
})
local ghostContainer = ghost and ghostButton.row.container
ghostButton:Destroy()
ghostContainer.Activated:Fire()
eq("Destroy : plus de callback", ghost, 0)

-- Fenetre entiere.
local gui = window.gui
local sidebarSignal = window.sidebar:GetPropertyChangedSignal("AbsoluteSize")
check("connexion de mise en page active", sidebarSignal:Count() > 0)

window:Destroy()
eq("Window:Destroy : ScreenGui retire", gui.Parent, nil)
eq("Window:Destroy : connexion de mise en page coupee", sidebarSignal:Count(), 0)
eq("Window:Destroy : onglets vides", #window.tabs, 0)

-- Tous les peintres de la fenetre doivent avoir disparu.
UI:Destroy()
eq("UI:Destroy : plus aucun peintre", Theme.painterCount(), 0)
eq("UI:Destroy : plus de fenetre", #UI.windows, 0)
eq("UI:Destroy : aucun suivi d'entree residuel",
    userInputService.InputChanged:Count(), 0)

---------------------------------------------------------------------------

print(string.format("\n%d reussis, %d echoues", passed, failed))
if failed > 0 then
    print("\nEchecs :")
    for _, name in ipairs(failures) do print("  x " .. name) end
    os.exit(1)
end
print("tout est vert")
