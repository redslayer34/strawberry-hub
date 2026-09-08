--=============================================================================
-- COMBAT POSITION CONTROLLER — where to stand to hit
--=============================================================================
--  Standing ABOVE and BEHIND puts you out of reach of the mob's melee while
--  staying inside hit-send range. The position is recomputed on every step: a
--  combat position held from one turn to the next follows a mob that is no
--  longer there.
--
--  ValidatePosition runs before every write. A refused position is not forced:
--  we take the high variant, and failing that we do not move.
--=============================================================================

local SafeCombatAnchor = require("AutomationCore.Movement.SafeCombatAnchor")

local CombatPositionController = {}

-- Strike point for a target: horizontally offset, raised, facing it. Melee M1
-- is directional server-side: without the facing, the blow does not land.
function CombatPositionController.stanceFor(ctx, entry)
    local root = entry and entry.root
    if not root or not root.Parent then return nil end

    local here = ctx:pos()
    if not here then return nil end

    local legacyFarming = ctx.legacyConfig.Farming
    local targetPos = root.Position

    -- The direction we approach from: the one we are already coming from, so
    -- we do not orbit the mob every frame.
    local away = Vector3.new(here.X - targetPos.X, 0, here.Z - targetPos.Z)
    if away.Magnitude < 0.1 then away = Vector3.new(0, 0, 1) end

    local stance = targetPos
        + away.Unit * (legacyFarming.SafeDistance or 4)
        + Vector3.new(0, legacyFarming.AttackHeight or 10, 0)

    -- Two coincident points give a NaN CFrame.lookAt, which throws the
    -- character off the map.
    if (stance - targetPos).Magnitude < 0.5 then
        stance = targetPos + Vector3.new(0, 3, 3)
    end

    return stance, targetPos
end

-- Puts the player in the strike position. Returns true when the move
-- happened, false plus a reason otherwise.
function CombatPositionController.hold(ctx, entry)
    local stance, lookAt = CombatPositionController.stanceFor(ctx, entry)
    if not stance then return false, "target has no root" end

    local ok, reason = SafeCombatAnchor.validatePosition(ctx, stance)
    if not ok then
        -- Try the same position higher before giving up: under a bridge or in
        -- a cave, the high variant usually works.
        stance = stance + Vector3.new(0, ctx.cfg.Anchor.Height, 0)
        ok, reason = SafeCombatAnchor.validatePosition(ctx, stance)
        if not ok then return false, reason end
    end

    local hrp = ctx.player.hrp()
    if not hrp then return false, "no player" end

    hrp.CFrame = CFrame.lookAt(stance, lookAt)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    return true
end

-- Usable combat state: player alive, attack engine ready. Called before every
-- attack.
function CombatPositionController.validateCombatState(ctx)
    if not ctx.player.alive() then return false, "player dead" end
    if not ctx.player.hrp() then return false, "player has no root" end
    if not ctx.attack.ready() then return false, "combat engine unavailable" end
    return true
end

return CombatPositionController
