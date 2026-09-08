--=============================================================================
-- MATERIAL FARM — partir du materiau, pas d'une position
--=============================================================================
--  Chaine demandee :
--
--      Drop -> EnemyCandidates -> Sea -> Island -> SpawnRegion
--
--  Le materiau donne une LISTE de mobs susceptibles de le lacher. Lequel
--  farmer n'est pas une constante : cela depend de ce qui existe sur ce
--  serveur, en quelle quantite, et a quelle distance. Le choix est donc
--  refait a partir de l'observation, jamais lu dans une table de positions.
--
--  L'ancien Enemies.nearestOfList relançait un scan complet du Workspace par
--  nom de la liste. Ici l'index d'EnemyScanner est deja construit : chaque
--  candidat coute une lecture de table.
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

-- Mobs susceptibles de lacher ce materiau. La table du runtime sert de
-- catalogue de candidats — elle ne contient que des noms, aucune position.
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
        Log.Material("materiau demande :", name,
            "(" .. #self:enemyCandidates() .. " mob(s) candidat(s))")
    end
    return true
end

-- Meilleur candidat REELLEMENT present. Un mob absent du serveur est ecarte
-- d'office, quelle que soit sa place dans la table.
function MaterialFarm:pickMob()
    local scanner = self.perception.scanner
    local here = self.ctx:pos()

    local best, bestScore
    for _, mobName in ipairs(self:enemyCandidates()) do
        local canonical = Names.normalize(mobName)
        local live = canonical and scanner:candidatesFor(canonical) or {}

        if #live > 0 then
            -- Densite d'abord, proximite ensuite : un paquet un peu plus loin
            -- vaut mieux qu'un mob isole a cote.
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

    -- Aucun candidat present ici. On rend le premier de la liste : le moteur
    -- ira sur place (etat TRAVEL), ce qui declenche les spawns de la zone.
    local fallback = self:enemyCandidates()[1]
    if fallback then
        Log.Material("aucun candidat present -- approche de", fallback)
    end
    return fallback
end

function MaterialFarm:update() return self.engine:update() end
function MaterialFarm:stop()
    self.material = nil
    return self.engine:stop()
end
function MaterialFarm:describe()
    return self.engine:describe() .. " materiau=" .. tostring(self.material)
end

return MaterialFarm
