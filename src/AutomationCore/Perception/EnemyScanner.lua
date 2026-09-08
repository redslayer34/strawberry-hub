--=============================================================================
-- ENEMY SCANNER — index des ennemis reellement presents
--=============================================================================
--  Un seul parcours du dossier Enemies par tour de perception, au lieu d'un
--  balayage complet par cible cherchee (l'ancien Enemies.nearestOfList
--  relançait un scan entier par nom de la liste).
--
--  Le scanner ne decide de rien. Il repond a une seule question : qu'est-ce
--  qui existe, la, maintenant. C'est lui qui fait le pont entre le nom lu
--  dans la quete ("Desert Bandits") et le nom d'instance reel
--  ("Desert Bandit") : la quete donne l'intention, le Workspace donne
--  l'orthographe. Aucun des deux ne peut le faire seul.
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")

local EnemyScanner = {}
EnemyScanner.__index = EnemyScanner

function EnemyScanner.new(ctx)
    return setmetatable({
        ctx = ctx,
        byCanonical = {},   -- forme canonique -> { entries = {}, liveName = "..." }
        entries = {},       -- toutes les entrees du dernier scan
        scannedAt = 0,
        lastCount = 0,
    }, EnemyScanner)
end

-- Partie manipulable d'un mob. HumanoidRootPart d'abord, replis ensuite :
-- certains rigs de boss n'exposent pas de HRP classique.
local function rootOf(model)
    local root = model:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then return root end
    if model.PrimaryPart then return model.PrimaryPart end
    local torso = model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
    if torso and torso:IsA("BasePart") then return torso end
    return model:FindFirstChildWhichIsA("BasePart")
end

-- Reconstruit l'index. Borne par MaxScanPerTick pour qu'un serveur charge ne
-- fasse pas tomber le framerate.
function EnemyScanner:scan()
    local ctx = self.ctx
    local folder = ctx.world.enemies()

    table.clear(self.byCanonical)
    table.clear(self.entries)
    self.scannedAt = os.clock()

    if not folder then
        self.lastCount = 0
        return self
    end

    local here = ctx:pos()
    local radius = ctx.cfg.Targets.ScanRadius
    local budget = ctx.cfg.Perception.MaxScanPerTick
    local seen = 0

    for _, model in ipairs(folder:GetChildren()) do
        seen = seen + 1
        if seen > budget then
            Log.Perception("scan tronque a", budget, "entites")
            break
        end

        local humanoid = model:FindFirstChildOfClass("Humanoid")
        local root = humanoid and rootOf(model)
        if root then
            local position = root.Position
            -- Le rayon borne l'index, pas la validite : un mob hors rayon
            -- n'est pas invalide, il est seulement hors de portee utile.
            if not here or (position - here).Magnitude <= radius then
                local canonical = Names.normalize(model.Name)
                if canonical then
                    local entry = {
                        model = model,
                        root = root,
                        humanoid = humanoid,
                        name = model.Name,
                        canonical = canonical,
                        position = position,
                        health = humanoid.Health,
                        maxHealth = humanoid.MaxHealth,
                    }
                    self.entries[#self.entries + 1] = entry

                    local bucket = self.byCanonical[canonical]
                    if not bucket then
                        bucket = { entries = {}, liveName = model.Name, maxHealth = 0 }
                        self.byCanonical[canonical] = bucket
                    end
                    bucket.entries[#bucket.entries + 1] = entry
                    if entry.maxHealth > bucket.maxHealth then
                        bucket.maxHealth = entry.maxHealth
                    end
                end
            end
        end
    end

    self.lastCount = #self.entries
    ctx.stats.scans = ctx.stats.scans + 1
    return self
end

function EnemyScanner:age()
    return os.clock() - self.scannedAt
end

-- Nom d'instance reel correspondant a une forme canonique, ou nil si rien de
-- tel n'existe actuellement. C'est le seul chemin autorise pour passer du
-- texte de quete a une entite : pas de `find`, pas de rapprochement flou.
function EnemyScanner:resolveName(canonical)
    if not canonical then return nil end
    local bucket = self.byCanonical[canonical]
    return bucket and bucket.liveName or nil
end

-- Entrees vivantes portant cette forme canonique. Liste vide si aucune :
-- l'appelant doit traiter ce cas, il declenche la recherche de region.
function EnemyScanner:candidatesFor(canonical)
    local bucket = canonical and self.byCanonical[canonical]
    if not bucket then return {} end

    local alive = {}
    for _, entry in ipairs(bucket.entries) do
        -- Re-verification a la lecture : entre le scan et l'usage, un mob a
        -- pu mourir ou etre retire. Aucune reference obsolete ne sort d'ici.
        if entry.model.Parent and entry.humanoid.Health > 0 then
            entry.health = entry.humanoid.Health
            entry.position = entry.root.Position
            alive[#alive + 1] = entry
        end
    end
    return alive
end

-- Vie maximale observee pour ce nom. Sert a distinguer un boss d'un mob
-- ordinaire sans liste codee en dur.
function EnemyScanner:maxHealthFor(canonical)
    local bucket = canonical and self.byCanonical[canonical]
    return bucket and bucket.maxHealth or 0
end

function EnemyScanner:names()
    local out = {}
    for canonical, bucket in pairs(self.byCanonical) do
        out[#out + 1] = { canonical = canonical, name = bucket.liveName, count = #bucket.entries }
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end

return EnemyScanner
