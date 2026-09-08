--=============================================================================
-- TRUST — hierarchy of information sources
--=============================================================================
--  The centrepiece of the whole architecture. The same question ("where is
--  the quest giver?", "which mob should I hit?") admits several answers of
--  very unequal reliability. They are ranked once and for all:
--
--    1. QUEST_STATE     the real quest state read from the game
--    2. LIVE_ENTITY     an entity actually present in the Workspace
--    3. NPC_IDENTITY    an NPC's identity / dialogue / objective
--    4. SPAWN_CLUSTER   a spawn group actually detected
--    5. SERVER_MEMORY   something learned on THIS server, THIS session
--    6. STATIC_FALLBACK a coordinate known in advance (frozen table)
--
--  The direct consequence: an old coordinate is never a truth. It is the last
--  resort, and it is logged as such. When a game update moves an island,
--  levels 1 through 4 keep working; only level 6 becomes wrong, and it is
--  consulted only once everything else has failed.
--=============================================================================

local Log = require("AutomationCore.Log")

local Trust = {}

Trust.LEVEL = {
    QUEST_STATE = 1,
    LIVE_ENTITY = 2,
    NPC_IDENTITY = 3,
    SPAWN_CLUSTER = 4,
    SERVER_MEMORY = 5,
    STATIC_FALLBACK = 6,
}

Trust.LABEL = {
    [1] = "quest-state",
    [2] = "live-entity",
    [3] = "npc-identity",
    [4] = "spawn-cluster",
    [5] = "server-memory",
    [6] = "static-fallback",
}

-- Past this level the data is a stopgap: we use it, but we say so, and the
-- caller is expected to kick off a rescan in parallel.
Trust.DEGRADED_FROM = Trust.LEVEL.SERVER_MEMORY

-- sources : list of { level = Trust.LEVEL.*, get = function() -> value, why = "..." }
-- Returns value, level, why. Sources are tried by decreasing trust, whatever
-- their order in the table.
function Trust.resolve(question, sources)
    local ordered = table.clone and table.clone(sources) or (function()
        local copy = {}
        for i, v in ipairs(sources) do copy[i] = v end
        return copy
    end)()

    table.sort(ordered, function(a, b) return a.level < b.level end)

    for _, source in ipairs(ordered) do
        local ok, value = pcall(source.get)
        if ok and value ~= nil then
            if source.level >= Trust.DEGRADED_FROM then
                Log.Perception(question, "resolved in degraded mode via",
                    Trust.LABEL[source.level], "--", source.why or "")
            end
            return value, source.level, source.why
        end
    end

    return nil, nil, nil
end

function Trust.isDegraded(level)
    return level ~= nil and level >= Trust.DEGRADED_FROM
end

function Trust.label(level)
    return Trust.LABEL[level or 0] or "unknown"
end

return Trust
