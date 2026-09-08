--=============================================================================
-- NAMES — entity name normalisation
--=============================================================================
--  Quest text and instance names never match exactly:
--
--      "Defeat 8 Desert Bandits"   ->  entity  "Desert Bandit"
--      "Defeat 5 Fishmen Warriors" ->  entity  "Fishman Warrior"
--
--  Hence normalisation. It is PERMISSIVE (plurals, case, spacing,
--  punctuation) but its only job is to produce a canonical form: the final
--  comparison is STRICT EQUALITY between two canonical forms. No
--  `string.find`, no partial match, no edit distance anywhere in the target
--  selection path.
--
--  `Names.similarity` exists to rank NPC candidates -- where a wrong guess is
--  corrected by a failed interaction, at no cost -- never to pick a mob to
--  hit.
--=============================================================================

local Names = {}

-- Irregular forms the generic rules do not cover. A data table: one more
-- variant does not mean touching the algorithm.
local IRREGULAR = {
    ["men"] = "man",
    ["fishmen"] = "fishman",
    ["swordsmen"] = "swordsman",
    ["thieves"] = "thief",
    ["wolves"] = "wolf",
    ["people"] = "person",
    ["militia"] = "militia",
}

-- Stop words stripped from the front. "The Saw" stays "saw".
local LEADING_NOISE = { ["the"] = true, ["a"] = true, ["an"] = true }

local function singularizeWord(word)
    local direct = IRREGULAR[word]
    if direct then return direct end

    if #word <= 3 then return word end

    -- "-men" -> "-man": Fishmen, Swordsmen, Marinemen...
    local stem = word:match("^(.-)men$")
    if stem and #stem > 0 then return stem .. "man" end

    -- "-ies" -> "-y": Bounties -> Bounty
    stem = word:match("^(.-)ies$")
    if stem and #stem > 0 then return stem .. "y" end

    -- "-ves" -> "-f": Thieves -> Thief
    stem = word:match("^(.-)ves$")
    if stem and #stem > 0 then return stem .. "f" end

    -- "-ches/-shes/-sses/-xes/-zes": drop the "es"
    if word:match("ches$") or word:match("shes$") or word:match("sses$")
        or word:match("xes$") or word:match("zes$") then
        return word:sub(1, #word - 2)
    end

    -- Plain "-s". "-ss" (Boss) and "-us" (Cactus) are protected.
    if word:match("s$") and not word:match("ss$") and not word:match("us$") then
        return word:sub(1, #word - 1)
    end

    return word
end

-- Memo: normalisation runs on every mob on every scan, and the game reuses a
-- handful of names across hundreds of entities. Bounded so a dynamically
-- generated name cannot grow it without limit.
local memo = {}
local memoCount = 0
local MEMO_LIMIT = 512

-- Lowercase, punctuation removed, spacing normalised, words singularised.
-- The result is deterministic: it is the comparison key.
function Names.normalize(value)
    if type(value) ~= "string" then return nil end

    local hit = memo[value]
    if hit ~= nil then
        return hit ~= false and hit or nil
    end

    local text = value:lower()
    text = text:gsub("[%[%]%(%){}<>]", " ")   -- UI decoration
    text = text:gsub("[^%a%d%s]", " ")        -- punctuation, apostrophes
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

    -- Leading articles only: "the" mid-name is meaningful.
    while #words > 1 and LEADING_NOISE[words[1]] do
        table.remove(words, 1)
    end

    for i, word in ipairs(words) do
        words[i] = singularizeWord(word)
    end

    local out = table.concat(words, " ")
    return remember(out ~= "" and out or nil)
end

-- Strict equality of two canonical forms. This is the ONLY comparison allowed
-- when deciding that a mob is the quest target.
function Names.matches(a, b)
    local na, nb = Names.normalize(a), Names.normalize(b)
    if not na or not nb then return false end
    return na == nb
end

-- Similarity score in [0,1], reserved for ranking NPC candidates.
-- Deliberately coarse: shared words over total words. No substring search,
-- which would let "Bandit" pass for "Desert Bandit".
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
    -- Harmonic mean: penalises a candidate that contains the wanted name
    -- buried among ten other words.
    local precision = shared / other
    local recall = shared / total
    if precision + recall == 0 then return 0 end
    return 2 * precision * recall / (precision + recall)
end

return Names
