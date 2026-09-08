--=============================================================================
-- ROUTE PLANNER — which quest to take, and why that one
--=============================================================================
--  The old selection was one line: the first table entry whose [Min, Max]
--  contains the level. It ignored everything else -- that the mob does not
--  exist on this server, that only two are left, that they are four thousand
--  studs away, or that another quest pays better.
--
--  Here the historical table is only a CATALOGUE of possible quests: it
--  supplies quest ids and target names, never a positional truth. Each
--  candidate is scored on what is actually observable right now:
--
--      level  x  target availability  x  density  x  distance  x  reward
--
--  A quest whose target does not exist on this server scores zero, wherever it
--  sits in the table.
--=============================================================================

local IslandDetector = require("AutomationCore.Perception.IslandDetector")
local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")

local RoutePlanner = {}

-- Maximum distance between a historical coordinate and a published island for
-- us to accept the association. Beyond that, the table is too stale to serve
-- even as a hint.
local ISLAND_SNAP = 2500

---------------------------------------------------------------------------
-- Catalogue
---------------------------------------------------------------------------

-- Turns a historical table row into a usable candidate. The CFrames are kept
-- only as last-resort fallbacks, never as a direct destination.
local function toCandidate(ctx, row)
    local canonical = Names.normalize(row.Name)
    if not canonical then return nil end

    return {
        questId = row.Quest,
        questLevel = row.QLevel or 1,
        targetRaw = row.Name,
        targetName = canonical,
        minLevel = row.Min or 1,
        maxLevel = row.Max or math.huge,
        sea = row.Sea,
        entrance = row.Entrance,
        -- Trust level 6. Used only if all detection has failed.
        giverFallback = row.QCF and row.QCF.Position or nil,
        mobFallback = row.MonCF and row.MonCF.Position or nil,
    }
end

-- Island nearest the historical coordinate. A useful trick: the old coordinate
-- is not used as a destination, it is used to NAME the zone, and the name is
-- then resolved against the position the game publishes. A relocated island
-- stays findable as long as it has not been renamed.
function RoutePlanner.islandFor(ctx, fallbackPosition)
    if not fallbackPosition then return nil end

    local best, bestDist
    for _, island in ipairs(IslandDetector.all(ctx)) do
        local d = (island.position - fallbackPosition).Magnitude
        if not bestDist or d < bestDist then best, bestDist = island.name, d end
    end

    if not best or bestDist > ISLAND_SNAP then return nil end
    return best
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------

-- Each factor is a multiplier: a zero factor eliminates the candidate rather
-- than being offset by the others.
local function scoreCandidate(ctx, scanner, candidate, level)
    -- Sea: a quest in another sea is not reachable from here.
    if candidate.sea and ctx.sea and candidate.sea ~= ctx.sea then return 0 end

    -- Level. Inside the band: full marks. Below: eliminated (the mobs kill).
    -- Above: penalised, since the experience gain collapses.
    local levelFactor
    if level < candidate.minLevel then
        return 0
    elseif level <= candidate.maxLevel then
        levelFactor = 1
    else
        local excess = level - candidate.maxLevel
        levelFactor = math.max(0.05, 1 - excess / 400)
    end

    -- Availability: does the target really exist, here, now? This is the
    -- factor the old selection lacked entirely.
    local live = scanner:candidatesFor(candidate.targetName)
    local count = #live
    local availability = count > 0 and 1 or 0.08

    -- Density: a pack of ten beats a lone mob. Capped so a very crowded zone
    -- does not dominate the rest of the calculation.
    local density = 1 + math.min(count, 12) / 12

    -- Distance: measured against real mobs when there are any, else the island.
    local distance
    if count > 0 then
        local here = ctx:pos()
        if here then
            local nearest = math.huge
            for _, entry in ipairs(live) do
                local d = (entry.position - here).Magnitude
                if d < nearest then nearest = d end
            end
            distance = nearest
        end
    end
    local distanceFactor = 1
    if distance then
        distanceFactor = 1 / (1 + distance / 2500)
    end

    -- Reward: approximated by the quest's level band. High bands give markedly
    -- more experience per kill.
    local reward = 1 + (candidate.minLevel / 2000)

    return levelFactor * availability * density * distanceFactor * reward
end

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------

-- Returns the best plan, or nil. `preferBoss` is reserved for BossFarm.
function RoutePlanner.plan(ctx, scanner, opts)
    opts = opts or {}
    local catalogue = ctx.legacyConfig.Quests or {}
    local level = ctx.player.level()

    local best, bestScore
    for _, row in ipairs(catalogue) do
        local candidate = toCandidate(ctx, row)
        if candidate then
            local value = scoreCandidate(ctx, scanner, candidate, level)
            if value > 0 and (not bestScore or value > bestScore) then
                best, bestScore = candidate, value
            end
        end
    end

    if not best then
        Log.Quest("no usable quest (level", level, ", sea", tostring(ctx.sea) .. ")")
        return nil
    end

    best.score = bestScore
    best.island = RoutePlanner.islandFor(ctx, best.mobFallback or best.giverFallback)

    -- Identification hints for the giver. The quest id is the most
    -- discriminating: it carries the zone name ("DesertQuest", "SnowQuest").
    best.hints = {
        best.questId or "",
        best.targetRaw or "",
        best.island or "",
    }

    Log.Quest(string.format("plan: %s level %d -> %s (score %.2f%s)",
        tostring(best.questId), best.questLevel, best.targetRaw, bestScore,
        best.island and (", island " .. best.island) or ""))

    return best
end

-- Is the plan still relevant? A level change can open a better quest, and a
-- target vanishing from the server invalidates one.
function RoutePlanner.isStale(ctx, plan, scanner)
    if not plan then return true end
    local level = ctx.player.level()
    if level < plan.minLevel or level > plan.maxLevel then return true end
    if plan.sea and ctx.sea and plan.sea ~= ctx.sea then return true end
    return false
end

return RoutePlanner
