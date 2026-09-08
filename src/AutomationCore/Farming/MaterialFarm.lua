--=============================================================================
-- MATERIAL FARM — start from the material, not from a position
--=============================================================================
--  The required chain:
--
--      Drop -> EnemyCandidates -> Sea -> Island -> SpawnRegion
--
--  A material gives a LIST of mobs that may drop it. Which one to farm is not
--  a constant: it depends on what exists on this server, in what numbers, and
--  how far away. So the choice is remade from observation, never read out of a
--  position table.
--
--  The old Enemies.nearestOfList restarted a full Workspace scan for every name
--  in its list. Here EnemyScanner's index is already built: each candidate
--  costs one table lookup.
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")
local TargetedFarm = require("AutomationCore.Farming.TargetedFarm")

local MaterialFarm = {}
MaterialFarm.__index = MaterialFarm

function MaterialFarm.new(ctx, perception, recovery)
    local self = setmetatable({
        ctx = ctx,
        perception = perception,
        material = nil,
    }, MaterialFarm)

    self.engine = TargetedFarm.new(ctx, perception, recovery, "Material", function()
        return self:pickMob()
    end)

    return self
end

-- Mobs that may drop this material. The runtime's table serves as a catalogue
-- of candidates -- it holds names only, no positions.
function MaterialFarm:enemyCandidates()
    if not self.material then return {} end
    local entry = self.ctx.legacyConfig.Materials[self.material]
    return entry and entry.mobs or {}
end

function MaterialFarm:setMaterial(name)
    if name == self.material then return true end
    self.material = name
    self.ctx.region = nil
    if name then
        Log.Material("material requested:", name,
            "(" .. #self:enemyCandidates() .. " candidate mob(s))")
    end
    return true
end

-- Best candidate ACTUALLY present. A mob absent from the server is discarded
-- outright, wherever it sits in the table.
function MaterialFarm:pickMob()
    local scanner = self.perception.scanner
    local here = self.ctx:pos()

    local best, bestScore
    for _, mobName in ipairs(self:enemyCandidates()) do
        local canonical = Names.normalize(mobName)
        local live = canonical and scanner:candidatesFor(canonical) or {}

        if #live > 0 then
            -- Density first, proximity second: a pack slightly further away
            -- beats a lone mob nearby.
            local nearest = math.huge
            if here then
                for _, e in ipairs(live) do
                    local d = (e.position - here).Magnitude
                    if d < nearest then nearest = d end
                end
            else
                nearest = 0
            end

            local score = (1 + math.min(#live, 10)) / (1 + nearest / 2000)
            if not bestScore or score > bestScore then
                best, bestScore = scanner:resolveName(canonical) or mobName, score
            end
        end
    end

    if best then return best end

    -- No candidate present here. Return the first of the list: the engine will
    -- travel there (TRAVEL state), which triggers the zone's spawns.
    local fallback = self:enemyCandidates()[1]
    if fallback then
        Log.Material("no candidate present -- approaching", fallback)
    end
    return fallback
end

function MaterialFarm:update() return self.engine:update() end
function MaterialFarm:stop()
    self.material = nil
    return self.engine:stop()
end
function MaterialFarm:describe()
    return self.engine:describe() .. " material=" .. tostring(self.material)
end

return MaterialFarm
