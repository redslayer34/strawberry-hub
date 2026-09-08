--=============================================================================
-- SPAWN CLUSTER RESOLVER — where the pack of mobs actually is
--=============================================================================
--  Mobs from the same quest are not spread evenly: they form packs, sometimes
--  far apart, and an update redistributes those packs. Picking "the nearest"
--  one at a time means crossing the zone constantly; picking a fixed centre
--  misses the pack the moment the game moves it.
--
--  So we group the targets actually present, score each group, and keep the
--  best as the SpawnRegion. The region is live data: it expires, it is
--  recomputed, and it survives neither an island change nor an objective
--  change.
--
--  The region then acts as a geographic filter in TargetValidator: that is
--  what stops the neighbouring zone's mobs from being pulled in.
--=============================================================================

local Log = require("AutomationCore.Log")

local SpawnClusterResolver = {}

-- Greedy proximity grouping. Chosen for its cost: O(n * groups), with n bounded
-- by the scan budget and the group count very small in practice. K-means would
-- be more correct and far more expensive, for no gain on packs this distinct.
local function cluster(entries, radius)
    local groups = {}
    local radiusSq = radius * radius

    for _, entry in ipairs(entries) do
        local placed = false
        for _, group in ipairs(groups) do
            if (entry.position - group.center).Magnitude <= radius then
                group.members[#group.members + 1] = entry
                -- Incremental mean: the centre tracks the pack as we go, with
                -- no second pass.
                local n = #group.members
                group.center = group.center + (entry.position - group.center) / n
                placed = true
                break
            end
        end
        if not placed then
            groups[#groups + 1] = {
                center = entry.position,
                members = { entry },
            }
        end
    end

    -- Real radius of each group: distance to the most outlying member.
    for _, group in ipairs(groups) do
        local spread = 0
        for _, member in ipairs(group.members) do
            local d = (member.position - group.center).Magnitude
            if d > spread then spread = d end
        end
        group.radius = math.max(spread, radius * 0.5)
        group.count = #group.members
    end

    local _ = radiusSq
    return groups
end

-- Score for a group. Density positive, distance negative: a big pack slightly
-- further away beats a lone mob nearby.
local function score(ctx, group, reference)
    local cfg = ctx.cfg.Cluster
    local distance = reference and (group.center - reference).Magnitude or 0
    -- 1000-stud scale: past that, distance dominates density.
    local penalty = 1 + cfg.DistanceWeight * (distance / 1000)
    return (cfg.DensityWeight * group.count) / penalty, distance
end

-- entries : targets ALREADY validated (see TargetValidator). This module does
-- not filter, it groups: handing it invalid mobs would produce a region
-- centred on the wrong enemies.
-- reference : point of interest (quest giver when known, else the player).
function SpawnClusterResolver.resolve(ctx, entries, reference)
    if #entries == 0 then return nil end

    local cfg = ctx.cfg.Cluster
    local groups = cluster(entries, cfg.Radius)

    local best, bestScore, bestDistance
    for _, group in ipairs(groups) do
        if group.count >= cfg.MinSize then
            local value, distance = score(ctx, group, reference)
            if not bestScore or value > bestScore then
                best, bestScore, bestDistance = group, value, distance
            end
        end
    end

    if not best then return nil end

    return {
        center = best.center,
        radius = best.radius,
        count = best.count,
        distance = bestDistance,
        groups = #groups,
        stamp = os.clock(),
    }
end

-- A region holds as long as it is fresh, still contains targets, and the
-- objective has not changed.
function SpawnClusterResolver.isStale(ctx, region)
    if not region then return true end
    if os.clock() - region.stamp > ctx.cfg.Cluster.RefreshInterval then return true end
    return false
end

function SpawnClusterResolver.update(ctx, entries, reference)
    local current = ctx.region

    if not SpawnClusterResolver.isStale(ctx, current) then
        return current
    end

    local region = SpawnClusterResolver.resolve(ctx, entries, reference)
    if not region then
        if current then
            Log.Target("spawn region lost (no valid targets)")
        end
        ctx.region = nil
        return nil
    end

    local moved = current and (region.center - current.center).Magnitude or math.huge
    ctx.region = region

    -- Only a genuine pack relocation is logged, not the few studs of drift
    -- caused by mobs milling about.
    if moved > ctx.cfg.Cluster.Radius then
        Log.Target(string.format(
            "spawn region: %d targets across %d group(s), %.0f studs away",
            region.count, region.groups, region.distance or 0))
    end

    return region
end

-- True when a position belongs to the chosen region. RegionSlack leaves margin:
-- a mob chasing the player leaves the strict radius without thereby belonging
-- to another zone.
function SpawnClusterResolver.contains(ctx, region, position)
    if not region or not position then return true end
    local limit = region.radius * ctx.cfg.Targets.RegionSlack
    return (position - region.center).Magnitude <= limit
end

return SpawnClusterResolver
