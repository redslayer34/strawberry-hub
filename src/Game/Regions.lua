--=============================================================================
-- REGIONS — which island a position is on, and the spawn points of each
--=============================================================================
--  The game marks every island with a part in workspace._WorldOrigin.
--  Locations; its size (or its Mesh scale) is the island's extent. The
--  player spawns are models in _WorldOrigin.PlayerSpawns. The rules are
--  the reference's (Banana Cat Hub), used by its "Reset Teleport": move the
--  spawn point to the goal's island, then reset the character.
--=============================================================================

local Services = require("Core.Services")

local Regions = {}

Regions.SPAWN_CACHE = 10       -- seconds the spawn index is reused
Regions.CLOSER_BY = 500        -- a spawn must bring you this much closer...
Regions.MIN_JUMP = 1000        -- ...and be at least this far from you

local index, indexedAt

local function locations()
    local folder = Services.find(workspace, "_WorldOrigin.Locations")
    return folder and folder:GetChildren() or {}
end

-- The location marker nearest to `position`.
function Regions.nearest(position)
    local best, bestDistance
    for _, part in ipairs(locations()) do
        if part:IsA("BasePart") and not part:GetAttribute("IgnoreInTracking") then
            local distance = (part.Position - position).Magnitude
            if not bestDistance or distance < bestDistance then
                best, bestDistance = part, distance
            end
        end
    end
    return best
end

-- The location `position` is in: the nearest marker, when `position` is
-- inside its Mesh (a marker without a Mesh always counts), else nil.
function Regions.containing(position)
    local part = Regions.nearest(position)
    if not part then return nil end
    local mesh = part:FindFirstChild("Mesh")
    if mesh then
        if mesh.Scale.X / 2 >= (part.Position - position).Magnitude then return part end
        return nil
    end
    return part
end

local function radius(part)
    local mesh = part:FindFirstChildWhichIsA("SpecialMesh")
    local scale = mesh and mesh.Scale.X or 1
    local size = part.Size
    return (size and size.X or 0) * scale / 2
end

-- { [location name] = { part, radius, spawns = { { name, position } } } }:
-- the spawn points inside each location.
function Regions.spawnIndex()
    local now = os.clock()
    if index and now - indexedAt < Regions.SPAWN_CACHE then return index end
    index, indexedAt = {}, now
    local spawns = {}
    local folder = Services.find(workspace, "_WorldOrigin.PlayerSpawns")
    for _, group in ipairs(folder and folder:GetChildren() or {}) do
        for _, model in ipairs(group:GetChildren()) do
            if model:IsA("Model") then
                local ok, pivot = pcall(function() return model:GetPivot() end)
                if ok and pivot then spawns[#spawns + 1] = { name = model.Name, position = pivot.Position } end
            end
        end
    end
    for _, part in ipairs(locations()) do
        if part:IsA("BasePart") then
            local extent = radius(part)
            local inside = {}
            for _, spawn in ipairs(spawns) do
                if (spawn.position - part.Position).Magnitude <= extent then inside[#inside + 1] = spawn end
            end
            index[part.Name] = { part = part, radius = extent, spawns = inside }
        end
    end
    return index
end

-- The name of the spawn point nearest to `position`, among those of the
-- location `position` is in (what SetLastSpawnPoint expects), or nil.
function Regions.spawnNameAt(position)
    local bestName, bestDistance = nil, math.huge
    for _, entry in pairs(Regions.spawnIndex()) do
        if #entry.spawns > 0 and entry.radius >= (entry.part.Position - position).Magnitude then
            for _, spawn in ipairs(entry.spawns) do
                local distance = (spawn.position - position).Magnitude
                if distance < bestDistance then bestName, bestDistance = spawn.name, distance end
            end
        end
    end
    return bestName
end

-- Whether a respawn may help: the goal is on another island than you, or
-- on none.
function Regions.shouldRespawn(here, goal)
    local target = Regions.containing(goal)
    if not target then return true end
    local current = Regions.containing(here)
    return not (current and current.Name == target.Name)
end

-- The spawn to move to: the one nearest the goal that brings you CLOSER_BY
-- studs closer and is MIN_JUMP studs away from you. { name, position }.
function Regions.respawnTarget(here, goal)
    local seen, candidates = {}, {}
    for _, entry in pairs(Regions.spawnIndex()) do
        for _, spawn in ipairs(entry.spawns) do
            if not seen[spawn] then
                seen[spawn] = true
                candidates[#candidates + 1] = spawn
            end
        end
    end
    table.sort(candidates, function(a, b)
        return (a.position - goal).Magnitude < (b.position - goal).Magnitude
    end)
    local toGoal = (goal - here).Magnitude
    for _, spawn in ipairs(candidates) do
        local name = Regions.spawnNameAt(spawn.position)
        if name and toGoal > (spawn.position - goal).Magnitude + Regions.CLOSER_BY
            and (spawn.position - here).Magnitude >= Regions.MIN_JUMP then
            return { name = name, position = spawn.position }
        end
    end
    return nil
end

-- Test hook.
function Regions.reset()
    index, indexedAt = nil, nil
end

return Regions
