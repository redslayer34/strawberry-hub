--=============================================================================
-- UTILITY — fabrique d'instances, Maid, animations
--=============================================================================
--  Le Maid est la piece qui rend Destroy() fiable : chaque composant y depose
--  ses instances, ses connexions et son peintre de theme, et n'a plus qu'a
--  appeler maid:Destroy(). Sans lui, chaque composant reimplemente son propre
--  nettoyage et en oublie une partie — typiquement les connexions, qui
--  maintiennent l'objet en vie et continuent de tourner.
--=============================================================================

local TweenService = game:GetService("TweenService")

local Utility = {}

---------------------------------------------------------------------------
-- Fabrique
---------------------------------------------------------------------------

-- Parent est applique EN DERNIER : affecter les proprietes apres le
-- parentage provoque un reflow par propriete cote moteur.
function Utility.new(className, props, children)
    local instance = Instance.new(className)
    local parent = nil

    if props then
        for key, value in pairs(props) do
            if key == "Parent" then
                parent = value
            else
                instance[key] = value
            end
        end
    end

    if children then
        for _, child in ipairs(children) do child.Parent = instance end
    end

    if parent then instance.Parent = parent end
    return instance
end

function Utility.corner(radius, parent)
    return Utility.new("UICorner", {
        CornerRadius = UDim.new(0, radius or 4),
        Parent = parent,
    })
end

function Utility.stroke(color, thickness, parent)
    return Utility.new("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

function Utility.padding(parent, top, bottom, left, right)
    return Utility.new("UIPadding", {
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or top or 0),
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or left or 0),
        Parent = parent,
    })
end

function Utility.list(parent, spacing, direction)
    return Utility.new("UIListLayout", {
        Padding = UDim.new(0, spacing or 4),
        FillDirection = direction or Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = parent,
    })
end

---------------------------------------------------------------------------
-- Animation
---------------------------------------------------------------------------

-- Discrete par defaut : 0.12 s, sortie douce. Les animations longues donnent
-- une impression de lourdeur sur mobile, ou chaque interaction compte.
Utility.FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
Utility.SLOW = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Utility.tween(instance, goal, info)
    local tween = TweenService:Create(instance, info or Utility.FAST, goal)
    tween:Play()
    return tween
end

---------------------------------------------------------------------------
-- Maid
---------------------------------------------------------------------------

local Maid = {}
Maid.__index = Maid

function Utility.maid()
    return setmetatable({ tasks = {}, dead = false }, Maid)
end

-- Accepte une connexion, une instance, une fonction, ou un autre Maid.
-- Un seul point d'entree evite d'avoir a se souvenir du type de chaque tache.
function Maid:give(task)
    if self.dead then
        -- Deposer une tache sur un Maid deja detruit la libere aussitot :
        -- sinon elle fuirait silencieusement.
        Maid.dispose(task)
        return task
    end
    table.insert(self.tasks, task)
    return task
end

function Maid.dispose(task)
    if task == nil then return end
    local kind = typeof(task)

    if kind == "RBXScriptConnection" then
        task:Disconnect()
    elseif kind == "Instance" then
        task:Destroy()
    elseif kind == "function" then
        task()
    elseif kind == "table" then
        if task.Destroy then task:Destroy() end
    end
end

function Maid:Destroy()
    if self.dead then return end
    self.dead = true
    -- Ordre inverse : les enfants sont liberes avant leurs parents.
    for i = #self.tasks, 1, -1 do
        local ok, err = pcall(Maid.dispose, self.tasks[i])
        if not ok then warn("[UI] nettoyage : " .. tostring(err)) end
        self.tasks[i] = nil
    end
end

function Maid:count() return #self.tasks end

---------------------------------------------------------------------------
-- Divers
---------------------------------------------------------------------------

-- Rounding = 0 doit rendre un ENTIER, pas un flottant qui vaut un entier :
-- une division rend toujours un flottant, et le slider affichait donc "20.0".
function Utility.round(value, decimals)
    decimals = decimals or 0
    if decimals <= 0 then return math.floor(value + 0.5) end
    local factor = 10 ^ decimals
    return math.floor(value * factor + 0.5) / factor
end

-- Affichage stable : "20" pour un entier, "0.30" et non "0.3" quand deux
-- decimales sont demandees.
function Utility.format(value, decimals)
    if (decimals or 0) <= 0 then return tostring(math.floor(value + 0.5)) end
    return string.format("%." .. decimals .. "f", value)
end

function Utility.clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

-- Conteneur d'affichage. gethui() isole l'interface de PlayerGui, ou le jeu
-- (ou un autre script) peut la parcourir ; on y retombe s'il est absent.
function Utility.screenParent()
    local ok, hidden = pcall(function() return gethui and gethui() end)
    if ok and hidden then return hidden end

    local players = game:GetService("Players")
    local player = players.LocalPlayer
    return player and player:FindFirstChildOfClass("PlayerGui") or nil
end

return Utility
