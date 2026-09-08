--=============================================================================
-- UI STUBS — types et services necessaires a la bibliotheque d'interface
--=============================================================================
--  Charge apres tools/stubs.lua. Deux choix guident ce fichier :
--
--    * les tweens s'appliquent IMMEDIATEMENT. Attendre une animation rendrait
--      les tests lents et intermittents ; ici `Play()` ecrit la valeur finale
--      et declenche Completed, ce qui permet d'affirmer l'etat d'arrivee sans
--      dormir.
--    * UserInputService expose ses signaux, donc un test peut simuler un
--      appui, un deplacement et un relachement — c'est ce qui rend le
--      deplacement de fenetre et le slider reellement verifiables.
--=============================================================================

-- UDim / UDim2 --------------------------------------------------------------
local UDimMt = { __index = {} }
local function udim(scale, offset)
    return setmetatable({ Scale = scale, Offset = offset, __udim = true }, UDimMt)
end
UDim = { new = function(scale, offset) return udim(scale or 0, offset or 0) end }

local UDim2Mt = {}
UDim2Mt.__index = UDim2Mt

local function udim2(xs, xo, ys, yo)
    return setmetatable({
        X = udim(xs, xo), Y = udim(ys, yo), __udim2 = true,
    }, UDim2Mt)
end

function UDim2Mt.__eq(a, b)
    return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset
        and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset
end

function UDim2Mt.__tostring(a)
    return string.format("{%g, %d}, {%g, %d}",
        a.X.Scale, a.X.Offset, a.Y.Scale, a.Y.Offset)
end

UDim2 = {
    new = function(xs, xo, ys, yo) return udim2(xs or 0, xo or 0, ys or 0, yo or 0) end,
    fromOffset = function(x, y) return udim2(0, x or 0, 0, y or 0) end,
    fromScale = function(x, y) return udim2(x or 0, 0, y or 0, 0) end,
}

-- Color3 --------------------------------------------------------------------
local Color3Mt = {}
Color3Mt.__index = Color3Mt
function Color3Mt.__eq(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
function Color3Mt.__tostring(a)
    return string.format("%d,%d,%d", a.R * 255, a.G * 255, a.B * 255)
end

Color3 = {
    new = function(r, g, b)
        return setmetatable({ R = r or 0, G = g or 0, B = b or 0, __color3 = true }, Color3Mt)
    end,
}
function Color3.fromRGB(r, g, b)
    return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

-- TweenInfo / TweenService --------------------------------------------------
TweenInfo = {
    new = function(time, style, direction)
        return { Time = time or 1, EasingStyle = style, EasingDirection = direction }
    end,
}

local tweenService = {
    played = 0,   -- compteur, utile pour verifier qu'une animation a bien eu lieu
}

function tweenService:Create(instance, info, goal)
    local tween = { Instance = instance, Goal = goal, Completed = newSignal() }

    function tween:Play()
        tweenService.played = tweenService.played + 1
        -- Application immediate : le test observe l'etat d'arrivee sans
        -- attendre. Les valeurs intermediaires ne sont pas testables de
        -- toute facon hors du moteur.
        for key, value in pairs(goal) do
            instance[key] = value
        end
        self.Completed:Fire(Enum.PlaybackState.Completed)
        return self
    end

    function tween:Cancel() end

    return tween
end

-- UserInputService ----------------------------------------------------------
local userInputService = {
    TouchEnabled = false,
    MouseEnabled = true,
    InputBegan = newSignal(),
    InputChanged = newSignal(),
    InputEnded = newSignal(),
}

-- Fabrique d'evenements d'entree, utilisee par les tests pour simuler la
-- souris et le doigt sans distinction cote bibliotheque.
function makeInput(inputType, x, y)
    return {
        UserInputType = inputType,
        Position = Vector3.new(x or 0, y or 0, 0),
    }
end

-- Services ------------------------------------------------------------------
-- game:GetService memorise ce qu'il rend : on injecte ici pour que la
-- bibliotheque recoive nos doubles.
local realGetService = game.GetService
game.GetService = function(self, name)
    if name == "TweenService" then return tweenService end
    if name == "UserInputService" then return userInputService end
    return realGetService(self, name)
end

-- Camera : la taille du viewport pilote l'echelle et le placement des menus.
local camera = newInstance("Camera", "Camera", nil)
camera.ViewportSize = Vector2.new(1280, 720)
workspace.CurrentCamera = camera

-- PlayerGui : destination de l'interface.
local players = game:GetService("Players")
local localPlayer = newInstance("Player", "LocalPlayer", nil)
newInstance("PlayerGui", "PlayerGui", localPlayer)
players.LocalPlayer = localPlayer

-- task.delay execute immediatement : les minuteurs de notification sont
-- ainsi observables sans horloge. Les tests qui veulent verifier le report
-- utilisent task.setDeferred.
local deferred = {}
task.delay = function(seconds, fn)
    if task.deferMode then
        deferred[#deferred + 1] = { at = seconds, fn = fn }
        return
    end
    fn()
end
task.setDeferred = function(value)
    task.deferMode = value and true or false
end
task.flushDeferred = function()
    local pending = deferred
    deferred = {}
    for _, entry in ipairs(pending) do entry.fn() end
end

_G.tweenService = tweenService
_G.userInputService = userInputService
