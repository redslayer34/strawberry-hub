--=============================================================================
-- TRAVEL CONTROLLER — se rendre quelque part, et savoir qu'on n'y arrive pas
--=============================================================================
--  Le deplacement lui-meme reste celui du runtime (tween borne en vitesse,
--  teleport court en deca du seuil). Ce qui manquait, c'est la surveillance :
--  un tween lance vers un point devenu inatteignable ne se signalait jamais,
--  et le farm restait bloque a mi-chemin sans qu'aucun timeout ne s'en
--  apercoive.
--
--  Ici chaque voyage a une cible, une distance de depart et un chrono. S'il
--  n'avance plus, il le dit ; la machine a etats s'en occupe.
--=============================================================================

local Log = require("AutomationCore.Log")
local SafeCombatAnchor = require("AutomationCore.Movement.SafeCombatAnchor")

local TravelController = {}

local function toVector(target)
    if not target then return nil end
    if typeof(target) == "Vector3" then return target end
    if typeof(target) == "CFrame" then return target.Position end
    if typeof(target) == "Instance" and target:IsA("BasePart") then return target.Position end
    return nil
end

---------------------------------------------------------------------------
-- Surveillance
---------------------------------------------------------------------------

local function tracker(ctx)
    ctx.travel = ctx.travel or {
        target = nil,
        startedAt = 0,
        lastPos = nil,
        lastProgressAt = 0,
        bestDistance = math.huge,
    }
    return ctx.travel
end

function TravelController.reset(ctx)
    ctx.travel = nil
end

-- Vrai si le joueur n'a pas progresse depuis StuckWindow secondes.
-- On mesure le RAPPROCHEMENT de la cible, pas le deplacement brut : tourner
-- en rond autour d'un obstacle deplace beaucoup sans avancer du tout.
function TravelController.isStuck(ctx)
    local state = tracker(ctx)
    if not state.target then return false end
    return os.clock() - state.lastProgressAt > ctx.cfg.Travel.StuckWindow
end

function TravelController.elapsed(ctx)
    local state = tracker(ctx)
    if not state.target then return 0 end
    return os.clock() - state.startedAt
end

---------------------------------------------------------------------------
-- Deplacement
---------------------------------------------------------------------------

function TravelController.distanceTo(ctx, target)
    local goal = toVector(target)
    local here = ctx:pos()
    if not goal or not here then return math.huge end
    return (goal - here).Magnitude
end

function TravelController.arrived(ctx, target, tolerance)
    return TravelController.distanceTo(ctx, target)
        <= (tolerance or ctx.cfg.Travel.ArriveDistance)
end

-- Un pas de voyage. A appeler a chaque tour de la machine a etats, pas une
-- fois pour toutes : le tween se relance seul si la destination bouge.
-- opts.validate : refuse une destination invalide (sous la carte, dans l'eau).
-- opts.lift     : hauteur ajoutee a la destination.
function TravelController.step(ctx, target, opts)
    opts = opts or {}
    local goal = toVector(target)
    if not goal then return false, "destination nulle" end

    if opts.lift then goal = goal + Vector3.new(0, opts.lift, 0) end

    if opts.validate then
        local ok, reason = SafeCombatAnchor.validatePosition(ctx, goal, opts.region)
        if not ok then
            -- On ne renonce pas au voyage : on vise le meme point, plus haut.
            -- Une destination au sol invalide reste souvent atteignable en vol.
            local lifted = goal + Vector3.new(0, ctx.cfg.Anchor.Height, 0)
            if SafeCombatAnchor.validatePosition(ctx, lifted, opts.region) then
                goal = lifted
            else
                return false, reason
            end
        end
    end

    local state = tracker(ctx)
    local here = ctx:pos()
    if not here then return false, "joueur absent" end

    local distance = (goal - here).Magnitude

    -- Nouvelle destination : on repart d'un chrono neuf.
    if not state.target or (state.target - goal).Magnitude > ctx.cfg.Travel.ArriveDistance then
        state.target = goal
        state.startedAt = os.clock()
        state.lastProgressAt = os.clock()
        state.bestDistance = distance
    elseif distance < state.bestDistance - ctx.cfg.Travel.StuckDistance then
        -- Progression reelle : le chrono d'immobilite repart.
        state.bestDistance = distance
        state.lastProgressAt = os.clock()
    end

    state.lastPos = here

    ctx.move.tweenTo(CFrame.new(goal))
    return true
end

function TravelController.stop(ctx)
    ctx.move.stop()
    TravelController.reset(ctx)
end

-- Passage vers une zone lointaine (Fishman, Sky, Ship). Le jeu expose une
-- entree dediee : tenter d'y aller en tween traverserait des dizaines de
-- milliers de studs.
function TravelController.requestEntrance(ctx, entrance)
    if not entrance then return false end
    local ok = pcall(function() ctx.remote.invoke("requestEntrance", entrance) end)
    if ok then Log.Travel("passage par requestEntrance") end
    return ok
end

return TravelController
