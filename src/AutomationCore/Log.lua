--=============================================================================
-- LOG — journal categorise de l'AutomationCore
--=============================================================================
--  Un seul point de sortie, une categorie par sous-systeme. On peut couper
--  une categorie sans toucher au code qui l'emet, ce qui evite les `print`
--  laisses en place puis commentes.
--
--  Un tampon circulaire garde les dernieres lignes meme categories coupees :
--  quand le farm part en vrille, l'historique est deja la, sans avoir eu a
--  reactiver les logs avant que le probleme se produise.
--=============================================================================

local Log = {}

Log.TAGS = {
    "Core", "Quest", "Island", "Sea", "QuestGiver", "Target", "Bring",
    "Combat", "Travel", "Mastery", "Material", "Boss", "CDK", "Recovery",
    "ServerHop", "State", "Perception",
}

local HISTORY_LIMIT = 200

local enabled = true
local muted = {}            -- tag -> true : categorie coupee
local history = {}          -- tampon circulaire des dernieres lignes
local cursor = 0
local sink = nil            -- destination optionnelle (UI, fichier)
local lastLine = {}         -- tag -> derniere ligne, pour l'anti-repetition
local repeats = {}          -- tag -> nombre de repetitions consecutives

function Log.setEnabled(value) enabled = value and true or false end
function Log.isEnabled() return enabled end

function Log.mute(tag, value)
    muted[tag] = value and true or nil
end

function Log.setSink(fn) sink = fn end

-- Concatene en tolerant les nil au milieu des arguments : un log ne doit
-- jamais lever d'erreur dans un chemin de farm.
local function join(...)
    local n = select("#", ...)
    local parts = table.create and table.create(n) or {}
    for i = 1, n do
        local v = select(i, ...)
        parts[i] = tostring(v)
    end
    return table.concat(parts, " ")
end

function Log.write(tag, ...)
    local text = join(...)
    local line = "[" .. tag .. "] " .. text

    cursor = cursor + 1
    history[(cursor - 1) % HISTORY_LIMIT + 1] = { tag = tag, text = text, clock = os.clock() }

    if not enabled or muted[tag] then return end

    -- Une machine a etats qui boucle emet la meme ligne des centaines de fois
    -- par minute. On n'affiche que les changements, avec un compteur.
    if lastLine[tag] == text then
        repeats[tag] = (repeats[tag] or 0) + 1
        if repeats[tag] % 50 ~= 0 then return end
        line = line .. "  (x" .. repeats[tag] .. ")"
    else
        lastLine[tag] = text
        repeats[tag] = 0
    end

    if sink then
        pcall(sink, tag, text)
    else
        print("[Strawberry]" .. line)
    end
end

-- Raccourcis : Log.Quest("Target =", name) se lit mieux que Log.write("Quest", ...)
for _, tag in ipairs(Log.TAGS) do
    Log[tag] = function(...) Log.write(tag, ...) end
end

-- Lignes du tampon, de la plus ancienne a la plus recente.
function Log.history()
    local out = {}
    local n = math.min(cursor, HISTORY_LIMIT)
    for i = 1, n do
        local idx = (cursor - n + i - 1) % HISTORY_LIMIT + 1
        out[i] = history[idx]
    end
    return out
end

function Log.clear()
    table.clear(history)
    table.clear(lastLine)
    table.clear(repeats)
    cursor = 0
end

return Log
