--=============================================================================
-- DYNAMIC MAP CACHE — ce que l'on a appris de CE serveur
--=============================================================================
--  Memoire de travail, pas base de donnees. Tout ce qui entre ici a ete
--  observe pendant la session en cours, porte une date, et sort par `:get()`
--  qui refuse de rendre une donnee perimee ou invalidee.
--
--  La memoire entiere est jetee des que le contexte change : serveur, mer, ou
--  ile. C'est ce qui repond a "le script doit reflechir a chaque serveur" —
--  au lieu de reutiliser aveuglement les positions du serveur precedent, il
--  repart d'un cache vide et redetecte.
--=============================================================================

local Cache = require("AutomationCore.Cache")
local Log = require("AutomationCore.Log")

local DynamicMapCache = {}
DynamicMapCache.__index = DynamicMapCache

-- Durees de vie par famille. Une position de PNJ bouge peu ; un groupe de
-- spawn se vide en quelques secondes de farm.
local TTL = {
    Islands = 120,
    QuestGivers = 45,
    EnemySpawns = 20,
    SpawnClusters = 12,
    Sea = 300,
}

function DynamicMapCache.new()
    local self = setmetatable({
        sections = {},
        serverId = nil,
        sea = nil,
        island = nil,
    }, DynamicMapCache)
    for name in pairs(TTL) do self.sections[name] = {} end
    return self
end

local function entry(self, section, key, validator)
    local bucket = self.sections[section]
    if not bucket then
        bucket = {}
        self.sections[section] = bucket
    end
    local slot = bucket[key]
    if not slot then
        slot = Cache.new({
            name = section .. "." .. tostring(key),
            ttl = TTL[section],
            validator = validator,
        })
        bucket[key] = slot
    elseif validator then
        -- Le validateur porte souvent des upvalues fraiches (position
        -- attendue, entite de reference) : on le remplace a chaque ecriture
        -- plutot que de garder celui du premier appel.
        slot.validator = validator
    end
    return slot
end

-- validator : function(value, meta) -> boolean. Vaut mieux qu'un TTL seul :
-- une entite peut disparaitre bien avant l'expiration.
function DynamicMapCache:put(section, key, value, meta, validator)
    return entry(self, section, key, validator):set(value, meta)
end

function DynamicMapCache:get(section, key)
    local bucket = self.sections[section]
    local slot = bucket and bucket[key]
    if not slot then return nil end
    return slot:get()
end

-- Derniere valeur connue, meme perimee. A n'utiliser que derriere Trust,
-- au niveau SERVER_MEMORY, jamais comme reponse directe.
function DynamicMapCache:peek(section, key)
    local bucket = self.sections[section]
    local slot = bucket and bucket[key]
    if not slot then return nil end
    return slot:peek()
end

function DynamicMapCache:invalidate(section, key, reason)
    local bucket = self.sections[section]
    if not bucket then return end
    if key == nil then
        for _, slot in pairs(bucket) do slot:invalidate(reason) end
        return
    end
    local slot = bucket[key]
    if slot then slot:invalidate(reason) end
end

function DynamicMapCache:clear(reason)
    for name in pairs(self.sections) do
        self.sections[name] = {}
    end
    Log.Perception("cache de carte vide --", reason or "raison non precisee")
end

-- Appele a chaque tour de perception. Le moindre changement de contexte
-- rend toute la memoire suspecte : on la jette, on redetecte.
function DynamicMapCache:syncContext(serverId, sea, island)
    local changed, why = false, nil

    if serverId ~= nil and self.serverId ~= nil and serverId ~= self.serverId then
        changed, why = true, "changement de serveur"
    elseif sea ~= nil and self.sea ~= nil and sea ~= self.sea then
        changed, why = true, "changement de mer"
    elseif island ~= nil and self.island ~= nil and island ~= self.island then
        changed, why = true, "changement d'ile (" .. tostring(self.island)
            .. " -> " .. tostring(island) .. ")"
    end

    self.serverId = serverId or self.serverId
    self.sea = sea or self.sea
    self.island = island or self.island

    if changed then self:clear(why) end
    return changed, why
end

return DynamicMapCache
