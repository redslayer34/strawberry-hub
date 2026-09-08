--=============================================================================
-- COMBAT POSITION CONTROLLER — ou se tenir pour frapper
--=============================================================================
--  Se placer AU-DESSUS et EN RETRAIT met hors de portee des attaques au corps
--  a corps du mob tout en restant dans la portee d'envoi des touches. La
--  position est recalculee a chaque pas : une position de combat gardee d'un
--  tour a l'autre suit un mob qui n'est plus la.
--
--  ValidatePosition est appelee avant chaque ecriture. Une position refusee
--  n'est pas forcee : on prend la variante haute, et a defaut on ne bouge pas.
--=============================================================================

local SafeCombatAnchor = require("AutomationCore.Movement.SafeCombatAnchor")

local CombatPositionController = {}

-- Point de frappe pour une cible : en retrait horizontal, en hauteur, oriente
-- vers elle. Le M1 melee est directionnel cote serveur : sans orientation, le
-- coup ne porte pas.
function CombatPositionController.stanceFor(ctx, entry)
    local root = entry and entry.root
    if not root or not root.Parent then return nil end

    local here = ctx:pos()
    if not here then return nil end

    local legacyFarming = ctx.legacyConfig.Farming
    local targetPos = root.Position

    -- Direction depuis laquelle on aborde : celle d'ou l'on vient deja, pour
    -- ne pas tourner autour du mob a chaque frame.
    local away = Vector3.new(here.X - targetPos.X, 0, here.Z - targetPos.Z)
    if away.Magnitude < 0.1 then away = Vector3.new(0, 0, 1) end

    local stance = targetPos
        + away.Unit * (legacyFarming.SafeDistance or 4)
        + Vector3.new(0, legacyFarming.AttackHeight or 10, 0)

    -- Deux points confondus donnent un CFrame.lookAt NaN, qui ejecte le
    -- personnage hors de la carte.
    if (stance - targetPos).Magnitude < 0.5 then
        stance = targetPos + Vector3.new(0, 3, 3)
    end

    return stance, targetPos
end

-- Place le joueur en position de frappe. Renvoie true si le deplacement a eu
-- lieu, false + motif sinon.
function CombatPositionController.hold(ctx, entry)
    local stance, lookAt = CombatPositionController.stanceFor(ctx, entry)
    if not stance then return false, "cible sans racine" end

    local ok, reason = SafeCombatAnchor.validatePosition(ctx, stance)
    if not ok then
        -- On tente la meme position plus haut avant de renoncer : sous un
        -- pont ou dans une grotte, la variante haute passe souvent.
        stance = stance + Vector3.new(0, ctx.cfg.Anchor.Height, 0)
        ok, reason = SafeCombatAnchor.validatePosition(ctx, stance)
        if not ok then return false, reason end
    end

    local hrp = ctx.player.hrp()
    if not hrp then return false, "joueur absent" end

    hrp.CFrame = CFrame.lookAt(stance, lookAt)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    return true
end

-- Etat de combat exploitable : joueur vivant, moteur d'attaque pret.
-- Appelee avant chaque attaque.
function CombatPositionController.validateCombatState(ctx)
    if not ctx.player.alive() then return false, "joueur mort" end
    if not ctx.player.hrp() then return false, "joueur sans racine" end
    if not ctx.attack.ready() then return false, "moteur de combat indisponible" end
    return true
end

return CombatPositionController
