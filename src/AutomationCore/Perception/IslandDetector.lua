--=============================================================================
-- ISLAND DETECTOR — which island we are on, and where the others are
--=============================================================================
--  The game publishes each island's position itself, in
--  workspace._WorldOrigin.Locations. This is the data that replaces coordinate
--  tables: when an update moves an island, that folder moves with it and
--  detection follows, with no change to the script.
--
--  So we do NOT memorise an island position. The folder is read on demand, and
--  the cache exists only to avoid re-reading it sixty times a second.
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")

local IslandDetector = {}

local function positionOf(node)
    if node:IsA("BasePart") then return node.Position end
    if node:IsA("Model") then
        local ok, cf = pcall(function() return node:GetPivot() end)
        if ok and cf then return cf.Position end
        local primary = node.PrimaryPart or node:FindFirstChildWhichIsA("BasePart")
        if primary then return primary.Position end
    end
    local attachment = node:FindFirstChildWhichIsA("BasePart")
    return attachment and attachment.Position or nil
end

-- List of { name, position } for every published island. Returned as-is,
-- unfiltered: it is the only truth available about the geography.
function IslandDetector.all(ctx)
    local folder = ctx.world.locations()
    if not folder then return {} end

    local out = {}
    for _, node in ipairs(folder:GetChildren()) do
        local pos = positionOf(node)
        if pos then
            out[#out + 1] = { name = node.Name, position = pos, instance = node }
        end
    end
    return out
end

-- Published position of an island, by name. Compared on canonical form:
-- "Frozen Village" and "frozen village" name the same island.
function IslandDetector.positionOf(ctx, islandName)
    local wanted = Names.normalize(islandName)
    if not wanted then return nil end

    local cached = ctx.map:get("Islands", wanted)
    if cached then return cached end

    for _, island in ipairs(IslandDetector.all(ctx)) do
        if Names.normalize(island.name) == wanted then
            -- Validator: the entry holds as long as the instance lives and has
            -- not moved. An island relocated by an update invalidates its own
            -- cache entry on the next pass.
            local instance, origin = island.instance, island.position
            ctx.map:put("Islands", wanted, origin, { name = island.name }, function()
                if not instance or not instance.Parent then return false end
                local now = positionOf(instance)
                return now ~= nil and (now - origin).Magnitude < 25
            end)
            return origin
        end
    end
    return nil
end

-- Island nearest the player. That is the operational definition of "where I
-- am": no hardcoded zones, no bounding boxes to maintain.
function IslandDetector.current(ctx)
    local here = ctx:pos()
    if not here then return nil end

    local best, bestDist
    for _, island in ipairs(IslandDetector.all(ctx)) do
        local d = (island.position - here).Magnitude
        if not bestDist or d < bestDist then
            best, bestDist = island.name, d
        end
    end
    return best, bestDist
end

function IslandDetector.update(ctx)
    local island = IslandDetector.current(ctx)
    if island ~= ctx.island then
        Log.Island(ctx.island and (tostring(ctx.island) .. " -> " .. tostring(island))
            or tostring(island))
        ctx.island = island
    end
    return ctx.island
end

return IslandDetector
