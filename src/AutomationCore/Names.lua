--=============================================================================
-- NAMES — normalisation des noms d'entites
--=============================================================================
--  Le texte de quete et le nom d'instance ne coincident jamais exactement :
--
--      "Defeat 8 Desert Bandits"   ->  entite  "Desert Bandit"
--      "Defeat 5 Fishmen Warriors" ->  entite  "Fishman Warrior"
--
--  D'ou la normalisation. Elle est PERMISSIVE (pluriel, casse, espaces,
--  ponctuation) mais elle ne sert qu'a produire une forme canonique : la
--  comparaison finale, elle, est une EGALITE STRICTE entre deux formes
--  canoniques. Aucun `string.find`, aucune correspondance partielle, aucune
--  distance d'edition dans le chemin de selection des cibles.
--
--  `Names.similarity` existe pour classer des candidats PNJ (ou une erreur se
--  corrige par une interaction ratee, sans consequence), jamais pour choisir
--  un mob a frapper.
--=============================================================================

local Names = {}

-- Irregularites que les regles generiques ne couvrent pas. Table de donnees :
-- une variante de plus ne demande pas de toucher a l'algorithme.
local IRREGULAR = {
    ["men"] = "man",
    ["fishmen"] = "fishman",
    ["swordsmen"] = "swordsman",
    ["thieves"] = "thief",
    ["wolves"] = "wolf",
    ["people"] = "person",
    ["militia"] = "militia",
}

-- Mots vides retires en tete de chaine. "The Saw" reste "saw".
local LEADING_NOISE = { ["the"] = true, ["a"] = true, ["an"] = true }

local function singularizeWord(word)
    local direct = IRREGULAR[word]
    if direct then return direct end

    if #word <= 3 then return word end

    -- "-men" -> "-man" : Fishmen, Swordsmen, Marinemen...
    local stem = word:match("^(.-)men$")
    if stem and #stem > 0 then return stem .. "man" end

    -- "-ies" -> "-y" : Bounties -> Bounty
    stem = word:match("^(.-)ies$")
    if stem and #stem > 0 then return stem .. "y" end

    -- "-ves" -> "-f" : Thieves -> Thief
    stem = word:match("^(.-)ves$")
    if stem and #stem > 0 then return stem .. "f" end

    -- "-ches/-shes/-sses/-xes/-zes" -> on retire le "es"
    if word:match("ches$") or word:match("shes$") or word:match("sses$")
        or word:match("xes$") or word:match("zes$") then
        return word:sub(1, #word - 2)
    end

    -- "-s" simple. On protege "-ss" (Boss) et "-us" (Cactus).
    if word:match("s$") and not word:match("ss$") and not word:match("us$") then
        return word:sub(1, #word - 1)
    end

    return word
end

-- Memo : la normalisation tourne sur chaque mob a chaque scan, et le jeu
-- reutilise une poignee de noms pour des centaines d'entites. Borne pour ne
-- pas grossir indefiniment si un nom est genere dynamiquement.
local memo = {}
local memoCount = 0
local MEMO_LIMIT = 512

-- Minuscules, ponctuation retiree, espaces normalises, mots au singulier.
-- Resultat deterministe : c'est la cle de comparaison.
function Names.normalize(value)
    if type(value) ~= "string" then return nil end

    local hit = memo[value]
    if hit ~= nil then
        return hit ~= false and hit or nil
    end

    local text = value:lower()
    text = text:gsub("[%[%]%(%){}<>]", " ")   -- habillage d'UI
    text = text:gsub("[^%a%d%s]", " ")        -- ponctuation, apostrophes
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s*(.-)%s*$", "%1")

    local function remember(result)
        if memoCount >= MEMO_LIMIT then
            table.clear(memo)
            memoCount = 0
        end
        memo[value] = result == nil and false or result
        memoCount = memoCount + 1
        return result
    end

    if text == "" then return remember(nil) end

    local words = {}
    for word in text:gmatch("%S+") do
        words[#words + 1] = word
    end

    -- Articles de tete uniquement : "the" au milieu d'un nom est signifiant.
    while #words > 1 and LEADING_NOISE[words[1]] do
        table.remove(words, 1)
    end

    for i, word in ipairs(words) do
        words[i] = singularizeWord(word)
    end

    local out = table.concat(words, " ")
    return remember(out ~= "" and out or nil)
end

-- Egalite stricte de deux formes canoniques. C'est la SEULE comparaison
-- autorisee pour decider qu'un mob est la cible de la quete.
function Names.matches(a, b)
    local na, nb = Names.normalize(a), Names.normalize(b)
    if not na or not nb then return false end
    return na == nb
end

-- Score de ressemblance dans [0,1], reserve au classement de candidats PNJ.
-- Volontairement grossier : mots communs sur mots totaux. Pas de recherche
-- de sous-chaine, qui ferait passer "Bandit" pour "Desert Bandit".
function Names.similarity(a, b)
    local na, nb = Names.normalize(a), Names.normalize(b)
    if not na or not nb then return 0 end
    if na == nb then return 1 end

    local seen, total = {}, 0
    for word in na:gmatch("%S+") do
        seen[word] = true
        total = total + 1
    end

    local shared, other = 0, 0
    for word in nb:gmatch("%S+") do
        other = other + 1
        if seen[word] then shared = shared + 1 end
    end

    if total == 0 or other == 0 then return 0 end
    -- Moyenne harmonique : penalise un candidat qui contient le nom cherche
    -- noye dans dix autres mots.
    local precision = shared / other
    local recall = shared / total
    if precision + recall == 0 then return 0 end
    return 2 * precision * recall / (precision + recall)
end

return Names
