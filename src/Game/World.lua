--=============================================================================
-- WORLD — islands, NPCs and server status, read from the live game
--=============================================================================

local Data = require("Game.Data")
local Enemies = require("Game.Enemies")
local Player = require("Core.Player")
local Services = require("Core.Services")

local World = {}

---------------------------------------------------------------------------
-- Islands
---------------------------------------------------------------------------

-- name -> Vector3 for the current sea: the location markers the game keeps
-- in workspace._WorldOrigin.Locations, completed by the known positions for
-- islands whose marker has not streamed in.
function World.islands()
    local islands = {}
    local known = Data.ISLANDS[Player.sea() or 0] or {}
    for name, xyz in pairs(known) do
        islands[name] = Vector3.new(xyz[1], xyz[2], xyz[3])
    end
    local origin = workspace:FindFirstChild("_WorldOrigin")
    local locations = origin and origin:FindFirstChild("Locations")
    if locations then
        for _, marker in ipairs(locations:GetChildren()) do
            if marker:IsA("BasePart") then islands[marker.Name] = marker.Position end
        end
    end
    return islands
end

function World.islandNames()
    local names = {}
    for name in pairs(World.islands()) do names[#names + 1] = name end
    table.sort(names)
    return names
end

---------------------------------------------------------------------------
-- NPCs
---------------------------------------------------------------------------

local function npcFolders()
    local folders = {}
    local live = workspace:FindFirstChild("NPCs")
    local stored = Services.replicated():FindFirstChild("NPCs")
    if live then folders[#folders + 1] = live end
    if stored then folders[#folders + 1] = stored end
    return folders
end

local function listed(name)
    return not name:find("Boat", 1, true) and not name:find("Set Home", 1, true)
end

function World.npcNames()
    local seen, names = {}, {}
    for _, folder in ipairs(npcFolders()) do
        for _, npc in ipairs(folder:GetChildren()) do
            if listed(npc.Name) and not seen[npc.Name] then
                seen[npc.Name] = true
                names[#names + 1] = npc.Name
            end
        end
    end
    table.sort(names)
    return names
end

-- The position of the nearest NPC called `name` (live ones in workspace
-- first, then the ones the game keeps in ReplicatedStorage), or nil.
function World.npcPosition(name)
    local best, bestDistance = nil, math.huge
    for _, folder in ipairs(npcFolders()) do
        for _, npc in ipairs(folder:GetChildren()) do
            local root = npc.Name == name and npc:FindFirstChild("HumanoidRootPart")
            if root then
                local distance = Player.distanceTo(root.Position)
                if distance < bestDistance then
                    best, bestDistance = root.Position, distance
                end
            end
        end
    end
    return best
end

---------------------------------------------------------------------------
-- Server status
---------------------------------------------------------------------------

-- "Full Moon", "Next Night" (full moon tomorrow night) or "Normal". The
-- game's MoonPhase attribute on Lighting first (5 = full, 4 = the night
-- before), the sky's moon texture when it is missing.
function World.moon()
    local lighting = Services.get("Lighting")
    local phase = tonumber(lighting:GetAttribute("MoonPhase"))
    if phase == 5 then return "Full Moon" end
    if phase == 4 then return "Next Night" end
    if phase then return "Normal" end
    local sky = lighting:FindFirstChild("Sky") or lighting:FindFirstChild("FantasySky")
    if Player.sea() == 2 then sky = lighting:FindFirstChild("FantasySky") or sky end
    local texture = sky and sky.MoonTextureId
    if texture == Data.MOON_FULL then return "Full Moon" end
    if texture == Data.MOON_NEXT then return "Next Night" end
    return "Normal"
end

function World.clock()
    local time = Services.get("Lighting").ClockTime or 0
    local hours = math.floor(time)
    local minutes = math.floor((time - hours) * 60)
    return string.format("%02d:%02d", hours, minutes)
end

-- The Elite Hunter target currently alive, or nil.
function World.eliteHunter()
    local elite = Enemies.findBoss(Data.ELITE_HUNTERS)
    return elite and elite.Name or nil
end

return World
