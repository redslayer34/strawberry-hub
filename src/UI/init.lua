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
