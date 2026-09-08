--=============================================================================
-- STUBS — environnement Roblox minimal pour executer les tests hors du jeu
--=============================================================================
--  Ne cherche pas a imiter Roblox : reproduit seulement ce que l'AutomationCore
--  consomme reellement. Vector3 et l'arbre d'instances sont fideles parce que
--  la logique testee en depend (regroupement, validation) ; le reste est un
--  bouchon.
--=============================================================================

-- Extensions Luau absentes de Lua 5.4 --------------------------------------
table.clear = table.clear or function(t)
    for k in pairs(t) do t[k] = nil end
end
table.create = table.create or function(n, value)
    local t = {}
    for i = 1, n do t[i] = value end
    return t
end
table.clone = table.clone or function(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    return copy
end

warn = warn or function(...) io.stderr:write("[warn] ", table.concat({ ... }, " "), "\n") end

-- Vector3 ------------------------------------------------------------------
local Vector3mt = {}
Vector3mt.__index = Vector3mt

local function vec(x, y, z)
    return setmetatable({ X = x, Y = y, Z = z, __vector = true }, Vector3mt)
end

function Vector3mt.__add(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
function Vector3mt.__sub(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
function Vector3mt.__unm(a) return vec(-a.X, -a.Y, -a.Z) end
function Vector3mt.__eq(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end

function Vector3mt.__mul(a, b)
    if type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end
    return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end

function Vector3mt.__div(a, b)
    if type(b) == "number" then return vec(a.X / b, a.Y / b, a.Z / b) end
    return vec(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end

function Vector3mt.__tostring(a)
    return string.format("(%.1f, %.1f, %.1f)", a.X, a.Y, a.Z)
end

Vector3mt.__index = function(self, key)
    if key == "Magnitude" then
        return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
    elseif key == "Unit" then
        local m = math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
        if m == 0 then return vec(0, 0, 0) end
        return vec(self.X / m, self.Y / m, self.Z / m)
    end
    return rawget(Vector3mt, key)
end

Vector3 = { new = function(x, y, z) return vec(x or 0, y or 0, z or 0) end }
Vector3.zero = Vector3.new(0, 0, 0)

-- CFrame -------------------------------------------------------------------
local CFramemt = { __index = {} }
local function cframe(position)
    return setmetatable({ Position = position, __cframe = true }, CFramemt)
end
function CFramemt.__add(a, b) return cframe(a.Position + b) end
function CFramemt.__mul(a, b)
    if type(b) == "table" and b.__cframe then return cframe(a.Position + b.Position) end
    return a
end

CFrame = {
    new = function(x, y, z)
        if type(x) == "table" then return cframe(x) end
        return cframe(Vector3.new(x, y, z))
    end,
    lookAt = function(from, _to) return cframe(from) end,
}

-- typeof -------------------------------------------------------------------
function typeof(value)
    if type(value) ~= "table" then return type(value) end
    if value.__vector then return "Vector3" end
    if value.__cframe then return "CFrame" end
    if value.__instance then return "Instance" end
    return "table"
end

-- Instances ----------------------------------------------------------------
local Instance_mt = {}
local Instance_methods = {}

-- Roblox resout d'abord les proprietes, puis les methodes, puis les enfants
-- par nom. Le troisieme cas compte ici : c'est ce qui permet de tester le
-- chemin rapide `frame.Container.QuestTitle.Title.Text`.
Instance_mt.__index = function(self, key)
    local method = Instance_methods[key]
    if method then return method end
    for _, child in ipairs(rawget(self, "Children") or {}) do
        if child.Name == key then return child end
    end
    return nil
end

local function newInstance(className, name, parent)
    local self = setmetatable({
        __instance = true,
        ClassName = className,
        Name = name or className,
        Parent = parent,
        Children = {},
        Attributes = {},
    }, Instance_mt)
    if parent then table.insert(parent.Children, self) end
    return self
end

function Instance_methods:IsA(className)
    if self.ClassName == className then return true end
    -- Hierarchie reduite au strict necessaire pour les tests.
    if className == "BasePart" then
        return self.ClassName == "Part" or self.ClassName == "MeshPart"
    end
    if className == "GuiObject" then
        return self.ClassName == "TextLabel" or self.ClassName == "Frame"
    end
    return false
end

function Instance_methods:GetChildren()
    local copy = {}
    for i, c in ipairs(self.Children) do copy[i] = c end
    return copy
end

function Instance_methods:FindFirstChild(name, recursive)
    for _, c in ipairs(self.Children) do
        if c.Name == name then return c end
    end
    if recursive then
        for _, c in ipairs(self.Children) do
            local hit = c:FindFirstChild(name, true)
            if hit then return hit end
        end
    end
    return nil
end

function Instance_methods:FindFirstChildOfClass(className)
    for _, c in ipairs(self.Children) do
        if c.ClassName == className then return c end
    end
    return nil
end

function Instance_methods:FindFirstChildWhichIsA(className)
    for _, c in ipairs(self.Children) do
        if c:IsA(className) then return c end
    end
    return nil
end

function Instance_methods:GetDescendants()
    local out = {}
    local function walk(node)
        for _, c in ipairs(node.Children) do
            out[#out + 1] = c
            walk(c)
        end
    end
    walk(self)
    return out
end

function Instance_methods:IsDescendantOf(ancestor)
    local node = self.Parent
    while node do
        if node == ancestor then return true end
        node = node.Parent
    end
    return false
end

function Instance_methods:GetAttribute(key) return self.Attributes[key] end
function Instance_methods:SetAttribute(key, value) self.Attributes[key] = value end
function Instance_methods:GetPivot()
    return CFrame.new(self.Position or Vector3.new(0, 0, 0))
end

Instance = { new = function(className, parent) return newInstance(className, className, parent) end }
_G.newInstance = newInstance

-- Services -----------------------------------------------------------------
local players = {
    LocalPlayer = nil,
    GetPlayerFromCharacter = function(_, _character) return nil end,
}

workspace = newInstance("Workspace", "Workspace")
workspace.Raycast = function(_self, origin, _direction, _params)
    -- Sol plat a Y=0 : suffit pour valider la logique d'ancrage.
    return { Position = Vector3.new(origin.X, 0, origin.Z), Instance = workspace }
end
workspace.GetPartBoundsInRadius = function() return {} end

local services = {
    Players = players,
    RunService = { Heartbeat = {}, Stepped = {} },
    TweenService = {},
    HttpService = {},
    TeleportService = {},
}

game = {
    PlaceId = 2753915549,
    JobId = "test-job",
    GetService = function(_, name)
        services[name] = services[name] or {}
        return services[name]
    end,
}

RaycastParams = { new = function() return { FilterDescendantsInstances = {} } end }
OverlapParams = { new = function() return { FilterDescendantsInstances = {} } end }
Enum = {
    RaycastFilterType = { Exclude = "Exclude" },
    EasingStyle = { Linear = "Linear" },
    PlaybackState = { Playing = "Playing" },
}

task = { wait = function() end, spawn = function(fn) fn() end }

-- Pas de `return` ici : ce fichier est concatene avant le bundle, et un
-- return terminerait le chunk.
