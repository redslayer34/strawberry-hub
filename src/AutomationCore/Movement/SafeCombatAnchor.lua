--=============================================================================
-- SAFE COMBAT ANCHOR — the flight point combat happens around
--=============================================================================
--  The anchor replaces the frozen `State.bringAnchor`: it is RECOMPUTED
--  regularly, never kept as a permanent truth. A CFrame held too long ends up
--  under the scenery as soon as the pack of mobs moves.
--
--  Every candidate position goes through ValidatePosition before use. The four
--  traps are handled explicitly:
--
--      under the map      -> no ground found beneath the position
--      in water           -> altitude below the water level
--      inside geometry    -> solid collision at that very spot
--      too far from spawn -> drift beyond MaxDriftFromRegion
--=============================================================================

local Log = require("AutomationCore.Log")

local SafeCombatAnchor = {}

---------------------------------------------------------------------------
-- Probing the world
---------------------------------------------------------------------------

-- The character and the enemies are excluded: we are looking for SCENERY, not
-- for bodies passing in front of the ray.
local function probeParams(ctx)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude

    local exclude = {}
    local character = ctx.player.character()
    if character then exclude[#exclude + 1] = character end
    local enemies = ctx.world.enemies()
    if enemies then exclude[#exclude + 1] = enemies end
    params.FilterDescendantsInstances = exclude
    params.IgnoreWater = true

    return params
end

-- Ground altitude beneath a position, or nil when there is only void.
function SafeCombatAnchor.groundBelow(ctx, position)
    local depth = ctx.cfg.Anchor.ProbeDepth
    local ok, result = pcall(function()
        return workspace:Raycast(
            position + Vector3.new(0, 5, 0),
            Vector3.new(0, -(depth + 5), 0),
            probeParams(ctx))
    end)
    if not ok or not result then return nil end
    return result.Position.Y, result.Instance
end

-- True when solid geometry already occupies the spot.
local function insideObstacle(ctx, position)
    local ok, parts = pcall(function()
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local exclude = {}
        local character = ctx.player.character()
        if character then exclude[#exclude + 1] = character end
        local enemies = ctx.world.enemies()
        if enemies then exclude[#exclude + 1] = enemies end
        params.FilterDescendantsInstances = exclude
        return workspace:GetPartBoundsInRadius(position, 3, params)
    end)
    if not ok or not parts then return false end

    for _, part in ipairs(parts) do
        if part.CanCollide then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------

-- Called before EVERY move. Returns true, or false plus a reason.
function SafeCombatAnchor.validatePosition(ctx, position, region)
    if not position then return false, "nil position" end
    -- A NaN propagates silently and throws the character off the map.
    if position.X ~= position.X or position.Y ~= position.Y or position.Z ~= position.Z then
        return false, "NaN position"
    end

    local cfg = ctx.cfg.Anchor

    if position.Y < cfg.WaterLevel then
        return false, "in water"
    end

    local groundY = SafeCombatAnchor.groundBelow(ctx, position)
    if not groundY then
        return false, "no ground below"
    end
    if position.Y < groundY then
        return false, "under the map"
    end
    if position.Y - groundY < cfg.MinGroundClearance then
        return false, "too close to the ground"
    end

    if insideObstacle(ctx, position) then
        return false, "inside an obstacle"
    end

    region = region or ctx.region
    if region and (position - region.center).Magnitude > cfg.MaxDriftFromRegion then
        return false, "too far from the spawn area"
    end

    return true
end

---------------------------------------------------------------------------
-- Computation
---------------------------------------------------------------------------

-- Candidate position: above the ground, directly over the requested point.
local function liftAboveGround(ctx, base)
    local groundY = SafeCombatAnchor.groundBelow(ctx, base)
    if not groundY then return nil end
    return Vector3.new(base.X, groundY + ctx.cfg.Anchor.Height, base.Z)
end

-- The current anchor. Recomputed at most every AnchorRefresh seconds, or
-- immediately if the previous one has become invalid.
function SafeCombatAnchor.compute(ctx, force)
    local now = os.clock()
    local held = ctx.anchor

    if not force and held and now - (ctx.anchorStamp or 0) < ctx.cfg.Bring.AnchorRefresh then
        if SafeCombatAnchor.validatePosition(ctx, held.Position) then
            return held
        end
        -- The held anchor has gone bad: do not hand it back, recompute at
        -- once. This is exactly the case that used to send mobs under the
        -- scenery.
        Log.Bring("anchor invalidated, recomputing")
    end

    -- The region centre first, the player's position second. Anchoring on the
    -- region keeps combat where the mobs respawn.
    local bases = {}
    if ctx.region then bases[#bases + 1] = ctx.region.center end
    local here = ctx:pos()
    if here then bases[#bases + 1] = here end

    for _, base in ipairs(bases) do
        local candidate = liftAboveGround(ctx, base)
        if candidate then
            local ok = SafeCombatAnchor.validatePosition(ctx, candidate)
            if ok then
                local cf = CFrame.new(candidate)
                ctx.anchor = cf
                ctx.anchorStamp = now
                return cf
            end
        end

        -- The exact point will not do: try a few lateral offsets before giving
        -- up. One rock should not be enough to fail the whole combat cycle.
        for _, offset in ipairs({
            Vector3.new(20, 0, 0), Vector3.new(-20, 0, 0),
            Vector3.new(0, 0, 20), Vector3.new(0, 0, -20),
        }) do
            local shifted = liftAboveGround(ctx, base + offset)
            if shifted and SafeCombatAnchor.validatePosition(ctx, shifted) then
                local cf = CFrame.new(shifted)
                ctx.anchor = cf
                ctx.anchorStamp = now
                return cf
            end
        end
    end

    ctx.anchor = nil
    ctx.anchorStamp = nil
    return nil
end

function SafeCombatAnchor.invalidate(ctx, reason)
    if ctx.anchor then Log.Bring("anchor dropped --", reason or "unspecified") end
    ctx.anchor = nil
    ctx.anchorStamp = nil
end

return SafeCombatAnchor
