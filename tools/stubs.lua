--=============================================================================
-- STUBS — a minimal Roblox environment to run the tests outside the game
--=============================================================================
--  Not an emulator: only what the hub actually touches. Vector3, CFrame
--  translation and the instance tree are faithful because the tested logic
--  depends on them (distances, lookups); everything else is a placeholder.
--
--  Concatenated before the bundle by tools/test.py: no `return` here.
--=============================================================================

-- Luau extensions missing from Lua 5.4 ---------------------------------------
table.clear = table.clear or function(t)
    for k in pairs(t) do t[k] = nil end
end
table.find = table.find or function(t, value)
    for i, v in ipairs(t) do
        if v == value then return i end
    end
    return nil
end
math.clamp = math.clamp or function(x, lo, hi)
    return math.max(lo, math.min(hi, x))
end
loadstring = loadstring or load

WARNINGS = {}
warn = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    WARNINGS[#WARNINGS + 1] = table.concat(parts, " ")
end

-- Vector3 --------------------------------------------------------------------
local Vector3mt = {}

local function vec(x, y, z)
    return setmetatable({ X = x, Y = y, Z = z, __vector = true }, Vector3mt)
end

Vector3mt.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3mt.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3mt.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
Vector3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
Vector3mt.__mul = function(a, b)
    if type(a) == "number" then a, b = b, a end
    if type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end
    return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3mt.__div = function(a, b)
    if type(b) == "number" then return vec(a.X / b, a.Y / b, a.Z / b) end
    return vec(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
Vector3mt.__tostring = function(a)
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
    return nil
end

Vector3 = { new = function(x, y, z) return vec(x or 0, y or 0, z or 0) end }
Vector3.zero = Vector3.new(0, 0, 0)

-- Vector2 --------------------------------------------------------------------
local Vector2mt = {}
local function vec2(x, y) return setmetatable({ X = x, Y = y, __vector2 = true }, Vector2mt) end
Vector2mt.__add = function(a, b) return vec2(a.X + b.X, a.Y + b.Y) end
Vector2mt.__sub = function(a, b) return vec2(a.X - b.X, a.Y - b.Y) end
Vector2mt.__index = function(self, key)
    if key == "Magnitude" then return math.sqrt(self.X ^ 2 + self.Y ^ 2) end
    return nil
end
Vector2 = { new = function(x, y) return vec2(x or 0, y or 0) end }

-- CFrame (translation only: rotation never matters to the tested logic) ------
local CFramemt = {}
local function cframe(position) return setmetatable({ Position = position, __cframe = true }, CFramemt) end
CFramemt.__mul = function(a, b)
    if type(b) == "table" and b.__cframe then return cframe(a.Position + b.Position) end
    if type(b) == "table" and b.__vector then return a.Position + b end
    return a
end
CFramemt.__add = function(a, b) return cframe(a.Position + b) end
CFramemt.__eq = function(a, b) return a.Position == b.Position end
CFramemt.__index = function() return nil end
CFrame = {
    new = function(x, y, z)
        if type(x) == "table" then return cframe(x) end
        return cframe(Vector3.new(x, y, z))
    end,
}

-- UI value types -------------------------------------------------------------
local UDimmt = { __eq = function(a, b) return a.Scale == b.Scale and a.Offset == b.Offset end }
local function udim(scale, offset)
    return setmetatable({ Scale = scale, Offset = offset, __udim = true }, UDimmt)
end
UDim = { new = udim }
local UDim2mt = { __eq = function(a, b) return a.X == b.X and a.Y == b.Y end }
local function udim2(xs, xo, ys, yo)
    return setmetatable({ X = udim(xs, xo), Y = udim(ys, yo), __udim2 = true }, UDim2mt)
end
UDim2 = {
    new = udim2,
    fromOffset = function(x, y) return udim2(0, x, 0, y) end,
}
local Color3mt = { __eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end }
local function color(r, g, b) return setmetatable({ R = r, G = g, B = b, __color3 = true }, Color3mt) end
Color3 = {
    new = color,
    fromRGB = function(r, g, b) return color(r / 255, g / 255, b / 255) end,
}

-- Enum: every category and member is created on first read ------------------
local function enumCategory(categoryName)
    return setmetatable({}, {
        __index = function(category, memberName)
            local member = { Name = memberName, EnumType = categoryName }
            rawset(category, memberName, member)
            return member
        end,
    })
end
Enum = setmetatable({}, {
    __index = function(root, categoryName)
        local category = enumCategory(categoryName)
        rawset(root, categoryName, category)
        return category
    end,
})

-- Signals ----------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal

function newSignal()
    return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
    local handlers = self.handlers
    local entry = { fn = fn }
    handlers[#handlers + 1] = entry
    local connection = { Connected = true, __connection = true }
    function connection:Disconnect()
        self.Connected = false
        for index, candidate in ipairs(handlers) do
            if candidate == entry then
                table.remove(handlers, index)
                break
            end
        end
    end
    return connection
end

function Signal:Fire(...)
    local snapshot = {}
    for i, entry in ipairs(self.handlers) do snapshot[i] = entry end
    for _, entry in ipairs(snapshot) do entry.fn(...) end
end

function Signal:Count() return #self.handlers end

-- typeof -----------------------------------------------------------------------
function typeof(value)
    if type(value) ~= "table" then return type(value) end
    if value.__vector then return "Vector3" end
    if value.__vector2 then return "Vector2" end
    if value.__cframe then return "CFrame" end
    if value.__udim2 then return "UDim2" end
    if value.__udim then return "UDim" end
    if value.__color3 then return "Color3" end
    if value.__connection then return "RBXScriptConnection" end
    if value.__instance then return "Instance" end
    return "table"
end

-- Instances --------------------------------------------------------------------
local SIGNALS = {
    Activated = true, InputBegan = true, InputChanged = true, InputEnded = true,
    Idled = true, Heartbeat = true, ChildAdded = true,
}

local CLASS_PARENTS = {
    Part = "BasePart", MeshPart = "BasePart",
    TextLabel = "GuiObject", TextButton = "GuiObject", Frame = "GuiObject",
}

local methods = {}
local Instancemt = {}

Instancemt.__index = function(self, key)
    local method = methods[key]
    if method then return method end
    if SIGNALS[key] then
        local signals = rawget(self, "_signals")
        signals[key] = signals[key] or newSignal()
        return signals[key]
    end
    for _, child in ipairs(rawget(self, "_children")) do
        if child.Name == key then return child end
    end
    return nil
end

Instancemt.__newindex = function(self, key, value)
    if key == "Parent" then
        local previous = rawget(self, "_parent")
        if previous == value then return end
        if previous then
            local list = rawget(previous, "_children")
            for i, child in ipairs(list) do
                if child == self then table.remove(list, i) break end
            end
        end
        rawset(self, "_parent", value)
        if value then table.insert(rawget(value, "_children"), self) end
        return
    end
    -- A part's CFrame and Position are one property seen two ways. Both live
    -- in _props, never as raw keys, so every assignment comes through here.
    if key == "CFrame" or key == "Position" then
        local props = rawget(self, "_props")
        props[key] = value
        if key == "CFrame" and type(value) == "table" and value.__cframe then
            props.Position = value.Position
        elseif key == "Position" and type(value) == "table" and value.__vector then
            props.CFrame = CFrame.new(value)
        end
        return
    end
    rawset(self, key, value)
end

function newInstance(className, name, parent)
    local self = setmetatable({
        __instance = true,
        ClassName = className,
        Name = name or className,
        _children = {},
        _signals = {},
        _attributes = {},
        _props = {},
        Visible = true,
        Text = "",
    }, Instancemt)
    if parent then self.Parent = parent end
    return self
end

-- `.Parent` lives in _parent so that assigning it can re-parent.
local rawIndex = Instancemt.__index
Instancemt.__index = function(self, key)
    if key == "Parent" then return rawget(self, "_parent") end
    if key == "CFrame" or key == "Position" then return rawget(self, "_props")[key] end
    return rawIndex(self, key)
end

function methods:IsA(className)
    return self.ClassName == className or CLASS_PARENTS[self.ClassName] == className
end
function methods:GetChildren()
    local copy = {}
    for i, child in ipairs(rawget(self, "_children")) do copy[i] = child end
    return copy
end
function methods:GetDescendants()
    local out = {}
    local function walk(node)
        for _, child in ipairs(rawget(node, "_children")) do
            out[#out + 1] = child
            walk(child)
        end
    end
    walk(self)
    return out
end
function methods:FindFirstChild(name, recursive)
    for _, child in ipairs(rawget(self, "_children")) do
        if child.Name == name then return child end
    end
    if recursive then
        for _, child in ipairs(rawget(self, "_children")) do
            local hit = child:FindFirstChild(name, true)
            if hit then return hit end
        end
    end
    return nil
end
function methods:FindFirstChildOfClass(className)
    for _, child in ipairs(rawget(self, "_children")) do
        if child.ClassName == className then return child end
    end
    return nil
end
function methods:FindFirstChildWhichIsA(className)
    for _, child in ipairs(rawget(self, "_children")) do
        if child:IsA(className) then return child end
    end
    return nil
end
function methods:Destroy()
    self.Parent = nil
    rawset(self, "Destroyed", true)
end
function methods:GetAttribute(key) return rawget(self, "_attributes")[key] end
function methods:SetAttribute(key, value) rawget(self, "_attributes")[key] = value end
function methods:FireServer(...)
    local log = rawget(self, "Fired") or {}
    rawset(self, "Fired", log)
    log[#log + 1] = table.pack(...)
end
function methods:InvokeServer(...)
    local log = rawget(self, "Invoked") or {}
    rawset(self, "Invoked", log)
    log[#log + 1] = table.pack(...)
    local handler = rawget(self, "OnInvoke")
    if handler then return handler(...) end
    return nil
end
function methods:EquipTool(tool)
    local character = self.Parent
    tool.Parent = character
end

Instance = { new = function(className, parent) return newInstance(className, className, parent) end }

-- ModuleScripts: `require(moduleScript)` returns its ModuleValue. The bundle
-- captures this global as its native require.
local luaRequire = require
require = function(target)
    if type(target) == "table" and target.__instance then
        if target.ModuleError then error(target.ModuleError) end
        return target.ModuleValue
    end
    return luaRequire(target)
end

-- Scheduler: task.spawn runs until the first wait, stepTasks() resumes ------
local queue = {}

local function resume(co, ...)
    local ok, err = coroutine.resume(co, ...)
    if not ok then error(err, 0) end
    if coroutine.status(co) ~= "dead" then queue[#queue + 1] = co end
end

task = {}
function task.spawn(fn, ...)
    resume(coroutine.create(fn), ...)
end
function task.wait(seconds)
    if coroutine.isyieldable() then coroutine.yield() end
    return seconds or 0
end
function task.delay(_seconds, fn, ...)
    local args = table.pack(...)
    queue[#queue + 1] = coroutine.create(function() fn(table.unpack(args, 1, args.n)) end)
end

-- Resumes every waiting task once.
function stepTasks()
    local current = queue
    queue = {}
    for _, co in ipairs(current) do
        if coroutine.status(co) == "suspended" then resume(co) end
    end
end

function clearTasks()
    queue = {}
end

-- World and services -----------------------------------------------------------
workspace = newInstance("Workspace", "Workspace")

local players = newInstance("Players", "Players")
function players:GetPlayerFromCharacter(character)
    return rawget(character, "OwnerPlayer")
end

local services = {
    Players = players,
    Workspace = workspace,
    ReplicatedStorage = newInstance("ReplicatedStorage", "ReplicatedStorage"),
    RunService = newInstance("RunService", "RunService"),
    CoreGui = newInstance("CoreGui", "CoreGui"),
    UserInputService = newInstance("UserInputService", "UserInputService"),
}

game = {
    PlaceId = 4442272183,
    JobId = "test-job",
    GetService = function(_, name)
        services[name] = services[name] or newInstance(name, name)
        return services[name]
    end,
    IsLoaded = function() return true end,
}
