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
