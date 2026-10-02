--=============================================================================
-- ISLAND LOADER — keeps every island loaded, as the reference does
--=============================================================================
--  The game loads an island's detailed model only near a "LoDPosition"
--  point (normally the camera). The reference (Banana Cat Hub) puts one
--  invisible point on every island at start, so every island, its NPCs and
--  its portals stay loaded wherever the player is. Uses more memory: the
--  "Load every island" setting turns it on.
--
--  The light way (always on): IslandLoader.focus(position) loads only the
--  place a farm is looking for mobs in, when it finds none there. On low
--  graphics the game keeps far islands as stand-ins, and their mobs and
--  spawn points never show (the God's Guards: fine on high graphics, lost
--  on low). Two things, paced per place:
--    * the game's own RequestStreamAroundAsync remote (the Teddy Kaitun's
--      RenderFunc): the server streams that area in for a while;
--    * one LoDPosition point on the island nearest to it (Banana's trick,
--      for that island only; FOCUS_POINTS at most, the oldest moved).
--=============================================================================

local Services = require("Core.Services")
local Settings = require("Core.Settings")

local IslandLoader = {}

IslandLoader.TAG = "LoDPosition"

local points = {}
local stopListening

IslandLoader.FOCUS_EVERY = 20      -- seconds before the same place is asked again
IslandLoader.FOCUS_CELL = 500      -- studs: places this close are the same place
IslandLoader.FOCUS_RADIUS = 600    -- studs the server streams around it
IslandLoader.FOCUS_SHOW = 90       -- seconds it keeps them
IslandLoader.FOCUS_POINTS = 2
IslandLoader.ISLAND_RANGE = 4000   -- studs: an island pivot this close to the place
IslandLoader.ISLANDS_EVERY = 60    -- seconds the island list is reused

local focused = {}                 -- [cell] = os.clock() of the last ask
local focusPoints = {}
local islands = { at = -math.huge, list = {} }

local function addPoint(model, camera)
    local ok, pivot = pcall(function() return model:GetPivot() end)
    if not ok or not pivot then return end
    local part = Instance.new("Part")
    part.Name = "StrawberryIslandPoint"
    part.Transparency = 1
    part.CanCollide = false
    part.Anchored = true
    part.Size = Vector3.new(0, 0, 0)
    part.CFrame = CFrame.new(pivot.Position)
    pcall(function() Services.get("CollectionService"):AddTag(part, IslandLoader.TAG) end)
    part.Parent = camera
    points[#points + 1] = part
end

-- Puts a point on every island model: the models of workspace that carry a
-- level of detail, those of workspace.Map, and the far-away stand-ins in
-- ReplicatedStorage.FakeIslands. Returns how many points exist.
function IslandLoader.load()
    if #points > 0 then return #points end
    local camera = workspace.CurrentCamera
    if not camera then return 0 end
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child:GetAttribute("LevelOfDetailDiameter") then addPoint(child, camera) end
    end
    local map = workspace:FindFirstChild("Map")
    for _, child in ipairs(map and map:GetChildren() or {}) do
        if child:IsA("Model") then addPoint(child, camera) end
    end
    local fakes = Services.replicated():FindFirstChild("FakeIslands")
    for _, child in ipairs(fakes and fakes:GetChildren() or {}) do
        if child:IsA("Model") then addPoint(child, camera) end
    end
    return #points
end

-- Every island model and its pivot (cached).
local function islandList()
    if os.clock() - islands.at < IslandLoader.ISLANDS_EVERY then return islands.list end
    local list = {}
    local function add(model)
        local ok, pivot = pcall(function() return model:GetPivot() end)
        if ok and pivot then list[#list + 1] = pivot.Position end
    end
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child:GetAttribute("LevelOfDetailDiameter") then add(child) end
    end
    local map = workspace:FindFirstChild("Map")
    for _, child in ipairs(map and map:GetChildren() or {}) do
        if child:IsA("Model") then add(child) end
    end
    local fakes = Services.replicated():FindFirstChild("FakeIslands")
    for _, child in ipairs(fakes and fakes:GetChildren() or {}) do
        if child:IsA("Model") then add(child) end
    end
    islands = { at = os.clock(), list = list }
    return list
end

local function focusPoint(position)
    local camera = workspace.CurrentCamera
    if not camera then return end
    local best, bestDistance = nil, IslandLoader.ISLAND_RANGE
    for _, pivot in ipairs(islandList()) do
        local distance = (pivot - position).Magnitude
        if distance < bestDistance then best, bestDistance = pivot, distance end
    end
    if not best then return end
    for _, part in ipairs(focusPoints) do
        if part.Parent and (part.Position - best).Magnitude < 1 then return end
    end
    local part
    if #focusPoints >= IslandLoader.FOCUS_POINTS then
        part = table.remove(focusPoints, 1)
    end
    if not part or not part.Parent then
        part = Instance.new("Part")
        part.Name = "StrawberryFocusPoint"
        part.Transparency = 1
        part.CanCollide = false
        part.Anchored = true
        part.Size = Vector3.new(0, 0, 0)
        pcall(function() Services.get("CollectionService"):AddTag(part, IslandLoader.TAG) end)
        part.Parent = camera
    end
    part.CFrame = CFrame.new(best)
    focusPoints[#focusPoints + 1] = part
end

-- Loads the place around `position` (see the header). Paced: returns true
-- when it asked now.
function IslandLoader.focus(position)
    if typeof(position) == "CFrame" then position = position.Position end
    if typeof(position) ~= "Vector3" then return false end
    local size = IslandLoader.FOCUS_CELL
    local cell = math.floor(position.X / size) .. ":" .. math.floor(position.Y / size) .. ":" .. math.floor(position.Z / size)
    local now = os.clock()
    if focused[cell] and now - focused[cell] < IslandLoader.FOCUS_EVERY then return false end
    focused[cell] = now
    pcall(function()
        local remotes = Services.replicated():FindFirstChild("Remotes")
        local stream = remotes and remotes:FindFirstChild("RequestStreamAroundAsync")
        if stream then
            stream:FireServer({ { cf = CFrame.new(position), distance = IslandLoader.FOCUS_RADIUS,
                showTime = IslandLoader.FOCUS_SHOW } })
        end
    end)
    if #points == 0 then pcall(focusPoint, position) end
    return true
end

function IslandLoader.unload()
    for _, part in ipairs(points) do
        pcall(function() part:Destroy() end)
    end
    points = {}
end

function IslandLoader.count()
    return #points
end

-- Loads the islands when the setting is on and follows the setting.
-- Returns the listener's remover.
function IslandLoader.start()
    if Settings.get("LoadIslands") then pcall(IslandLoader.load) end
    if stopListening then stopListening() end
    stopListening = Settings.onChanged(function(key, value)
        if key ~= "LoadIslands" then return end
        if value then pcall(IslandLoader.load) else IslandLoader.unload() end
    end)
    return stopListening
end

function IslandLoader.destroy()
    if stopListening then
        stopListening()
        stopListening = nil
    end
    IslandLoader.unload()
    for _, part in ipairs(focusPoints) do pcall(function() part:Destroy() end) end
    focusPoints = {}
end

-- Test hook.
function IslandLoader.reset()
    points, stopListening = {}, nil
    focused, focusPoints = {}, {}
    islands = { at = -math.huge, list = {} }
end

return IslandLoader
