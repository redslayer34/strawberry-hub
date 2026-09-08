--=============================================================================
-- SAFE COMBAT ANCHOR — le point de vol autour duquel le combat se deroule
--=============================================================================
--  L'ancre remplace le `State.bringAnchor` fige : elle est RECALCULEE
--  regulierement, jamais conservee comme verite permanente. Un CFrame retenu
--  trop longtemps finit sous le decor des que le paquet de mobs se deplace.
--
--  Toute position candidate passe par ValidatePosition avant d'etre utilisee.
--  Les quatre pieges sont traites explicitement :
--
--      sous la carte        -> aucun sol touche sous la position
--      dans l'eau           -> altitude sous le niveau d'eau
--      dans un obstacle     -> geometrie solide a l'emplacement meme
--      trop loin du spawn   -> derive au-dela de MaxDriftFromRegion
--=============================================================================

local Log = require("AutomationCore.Log")

local SafeCombatAnchor = {}

---------------------------------------------------------------------------
-- Sondage du monde
---------------------------------------------------------------------------

-- Le personnage et les ennemis sont exclus : on cherche le DECOR, pas les
-- corps qui passent devant le rayon.
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

-- Altitude du sol sous une position, ou nil si le vide est en dessous.
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

-- Vrai si de la geometrie solide occupe deja l'emplacement.
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

-- Appele avant CHAQUE deplacement. Renvoie true, ou false + motif.
function SafeCombatAnchor.validatePosition(ctx, position, region)
    if not position then return false, "position nulle" end
    -- Un NaN se propage silencieusement et ejecte le personnage hors carte.
    if position.X ~= position.X or position.Y ~= position.Y or position.Z ~= position.Z then
        return false, "position NaN"
    end

    local cfg = ctx.cfg.Anchor

    if position.Y < cfg.WaterLevel then
        return false, "dans l'eau"
    end

    local groundY = SafeCombatAnchor.groundBelow(ctx, position)
    if not groundY then
        return false, "aucun sol dessous"
    end
    if position.Y < groundY then
        return false, "sous la carte"
    end
    if position.Y - groundY < cfg.MinGroundClearance then
        return false, "trop pres du sol"
    end

    if insideObstacle(ctx, position) then
        return false, "dans un obstacle"
    end

    region = region or ctx.region
    if region and (position - region.center).Magnitude > cfg.MaxDriftFromRegion then
        return false, "trop loin de la zone de spawn"
    end

    return true
end

---------------------------------------------------------------------------
-- Calcul
---------------------------------------------------------------------------

-- Position candidate : au-dessus du sol, a l'aplomb du point demande.
local function liftAboveGround(ctx, base)
    local groundY = SafeCombatAnchor.groundBelow(ctx, base)
    if not groundY then return nil end
    return Vector3.new(base.X, groundY + ctx.cfg.Anchor.Height, base.Z)
end

-- Ancre courante. Recalculee au plus toutes les AnchorRefresh secondes, ou
-- immediatement si la precedente est devenue invalide.
function SafeCombatAnchor.compute(ctx, force)
    local now = os.clock()
    local held = ctx.anchor

    if not force and held and now - (ctx.anchorStamp or 0) < ctx.cfg.Bring.AnchorRefresh then
        if SafeCombatAnchor.validatePosition(ctx, held.Position) then
            return held
        end
        -- L'ancre retenue est devenue mauvaise : on ne la rend pas, on la
        -- recalcule tout de suite. C'est exactement le cas qui envoyait les
        -- mobs sous le decor.
        Log.Bring("ancre invalidee, recalcul")
    end

    -- Le centre de region d'abord, la position du joueur ensuite. Ancrer sur
    -- la region garde le combat la ou les mobs reapparaissent.
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

        -- Le point exact ne convient pas : on essaie quelques decalages
        -- lateraux avant d'abandonner. Un rocher ne doit pas suffire a faire
        -- echouer tout le cycle de combat.
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
    if ctx.anchor then Log.Bring("ancre abandonnee --", reason or "non precise") end
    ctx.anchor = nil
    ctx.anchorStamp = nil
end

return SafeCombatAnchor
