--=============================================================================
-- ENEMIES — live mobs and where they spawn
--=============================================================================
--  Live mobs are the models under workspace.Enemies. Spawn points are parts
--  under workspace._WorldOrigin.EnemySpawns; when streaming has not loaded
--  them, the same parts can still be found among nil-parented instances.
--  Spawn parts may carry a level suffix ("Zombie [Lv. 950]"), mob models do
--  not, hence stripLevel.
--=============================================================================

local Player = require("Core.Player")

local Enemies = {}

-- "Zombie [Lv. 950]" -> "Zombie"
function Enemies.stripLevel(name)
    local stripped = tostring(name):gsub("%s*%p?Lv%.?%s*%d+%p?", "")
    return (stripped:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Enemies.isAlive(model)
    if not model or not model.Parent then return false end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
        and model:FindFirstChild("HumanoidRootPart") ~= nil
end

local function toSet(wanted)
    if type(wanted) == "table" then
        local set = {}
        for _, name in ipairs(wanted) do set[name] = true end
        return set
    end
    return { [wanted] = true }
end

local function folder()
    return workspace:FindFirstChild("Enemies")
end

-- Every alive mob whose name is `wanted` (a name or a list of names).
function Enemies.all(wanted, ignore)
    local out = {}
    local enemies = folder()
    if not enemies then return out end
    local set = toSet(wanted)
    for _, model in ipairs(enemies:GetChildren()) do
        if set[model.Name] and not (ignore and ignore[model]) and Enemies.isAlive(model) then
            out[#out + 1] = model
        end
    end
    return out
end

-- The alive mob named `wanted` closest to `from` (default: the player).
-- Returns the model and its distance.
function Enemies.nearest(wanted, from, ignore)
    from = from or Player.position()
    if not from then return nil end
    local best, bestDistance = nil, math.huge
    for _, model in ipairs(Enemies.all(wanted, ignore)) do
        local distance = (model.HumanoidRootPart.Position - from).Magnitude
        if distance < bestDistance then
            best, bestDistance = model, distance
        end
    end
    return best, bestDistance
end

---------------------------------------------------------------------------
-- Spawn points
---------------------------------------------------------------------------

-- Spawn parts do not move, so a found list is kept. An empty result is kept
-- only briefly: the parts may simply not have streamed in yet, but scanning
-- every nil-parented instance on every frame would cost far too much.
local spawnCache = {}
local missCache = {}
Enemies.MISS_RETRY = 5

local function scan(list, name, into, seen)
    for _, node in ipairs(list) do
        if not seen[node] and node:IsA("BasePart") and Enemies.stripLevel(node.Name) == name then
            seen[node] = true
            into[#into + 1] = node
        end
    end
end

function Enemies.spawnPoints(name)
    local cached = spawnCache[name]
    if cached then return cached end

    local missed = missCache[name]
    if missed and os.clock() - missed < Enemies.MISS_RETRY then return {} end

    local points, seen = {}, {}
    local origin = workspace:FindFirstChild("_WorldOrigin")
    local spawns = origin and origin:FindFirstChild("EnemySpawns")
    if spawns then scan(spawns:GetChildren(), name, points, seen) end

    if #points == 0 and getnilinstances then
        local ok, list = pcall(getnilinstances)
        if ok and type(list) == "table" then scan(list, name, points, seen) end
    end

    if #points > 0 then
        spawnCache[name] = points
        missCache[name] = nil
    else
        missCache[name] = os.clock()
    end
    return points
end

-- The spawn point of `name` closest to `position`, or nil.
function Enemies.nearestSpawn(name, position)
    local best, bestDistance = nil, math.huge
    for _, part in ipairs(Enemies.spawnPoints(name)) do
        local distance = (part.Position - position).Magnitude
        if distance < bestDistance then
            best, bestDistance = part, distance
        end
    end
    return best
end

-- Test hook.
function Enemies.reset()
    spawnCache, missCache = {}, {}
end

return Enemies
