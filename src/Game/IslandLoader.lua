--=============================================================================
-- ISLAND LOADER — keeps every island loaded, as the reference does
--=============================================================================
--  The game loads an island's detailed model only near a "LoDPosition"
--  point (normally the camera). The reference (Banana Cat Hub) puts one
--  invisible point on every island at start, so every island, its NPCs and
--  its portals stay loaded wherever the player is. Uses more memory: the
--  "Load every island" setting turns it off.
--=============================================================================

local Services = require("Core.Services")
local Settings = require("Core.Settings")

local IslandLoader = {}

IslandLoader.TAG = "LoDPosition"

local points = {}
local stopListening

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
end

-- Test hook.
function IslandLoader.reset()
    points, stopListening = {}, nil
end

return IslandLoader
