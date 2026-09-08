--=============================================================================
-- DYNAMIC MAP CACHE — what we have learned about THIS server
--=============================================================================
--  Working memory, not a database. Everything in here was observed during the
--  current session, carries a timestamp, and comes out through `:get()`, which
--  refuses to hand back stale or invalidated data.
--
--  The whole memory is dropped as soon as the context changes: server, sea, or
--  island. That is the answer to "the script must think on every server" --
--  instead of blindly reusing the previous server's positions, it starts from
--  an empty cache and re-detects.
--=============================================================================

local Cache = require("AutomationCore.Cache")
local Log = require("AutomationCore.Log")

local DynamicMapCache = {}
DynamicMapCache.__index = DynamicMapCache

-- Lifetimes by family. An NPC position barely moves; a spawn group empties in
-- a few seconds of farming.
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
        -- Validators usually close over fresh upvalues (expected position,
        -- reference entity), so replace it on every write rather than keeping
        -- the one from the first call.
        slot.validator = validator
    end
    return slot
end

-- validator : function(value, meta) -> boolean. Better than a TTL alone: an
-- entity can vanish well before expiry.
function DynamicMapCache:put(section, key, value, meta, validator)
    return entry(self, section, key, validator):set(value, meta)
end

function DynamicMapCache:get(section, key)
    local bucket = self.sections[section]
    local slot = bucket and bucket[key]
    if not slot then return nil end
    return slot:get()
end

-- Last known value, stale or not. To be used only behind Trust, at the
-- SERVER_MEMORY level, never as a direct answer.
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
    Log.Perception("map cache cleared --", reason or "no reason given")
end

-- Called on every perception pass. Any context change makes the whole memory
-- suspect: drop it, re-detect.
function DynamicMapCache:syncContext(serverId, sea, island)
    local changed, why = false, nil

    if serverId ~= nil and self.serverId ~= nil and serverId ~= self.serverId then
        changed, why = true, "server changed"
    elseif sea ~= nil and self.sea ~= nil and sea ~= self.sea then
        changed, why = true, "sea changed"
    elseif island ~= nil and self.island ~= nil and island ~= self.island then
        changed, why = true, "island changed (" .. tostring(self.island)
            .. " -> " .. tostring(island) .. ")"
    end

    self.serverId = serverId or self.serverId
    self.sea = sea or self.sea
    self.island = island or self.island

    if changed then self:clear(why) end
    return changed, why
end

return DynamicMapCache
