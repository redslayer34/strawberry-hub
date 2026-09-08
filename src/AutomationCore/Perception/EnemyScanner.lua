--=============================================================================
-- ENEMY SCANNER — index of the enemies actually present
--=============================================================================
--  One pass over the Enemies folder per perception turn, instead of a full
--  sweep per name searched (the old Enemies.nearestOfList restarted a complete
--  scan for every name in its list).
--
--  The scanner decides nothing. It answers one question: what exists, here,
--  now. It is also the bridge between the name read from the quest ("Desert
--  Bandits") and the real instance name ("Desert Bandit"): the quest supplies
--  the intent, the Workspace supplies the spelling. Neither can do it alone.
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")

local EnemyScanner = {}
EnemyScanner.__index = EnemyScanner

function EnemyScanner.new(ctx)
    return setmetatable({
        ctx = ctx,
        byCanonical = {},   -- canonical form -> { entries = {}, liveName = "..." }
        entries = {},       -- every entry from the last scan
        scannedAt = 0,
        lastCount = 0,
    }, EnemyScanner)
end

-- A mob's manipulable part. HumanoidRootPart first, fallbacks after: some boss
-- rigs do not expose a conventional HRP.
local function rootOf(model)
    local root = model:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then return root end
    if model.PrimaryPart then return model.PrimaryPart end
    local torso = model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
    if torso and torso:IsA("BasePart") then return torso end
    return model:FindFirstChildWhichIsA("BasePart")
end

-- Rebuilds the index. Bounded by MaxScanPerTick so a busy server cannot drop
-- the frame rate.
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
            Log.Perception("scan truncated at", budget, "entities")
            break
        end

        local humanoid = model:FindFirstChildOfClass("Humanoid")
        local root = humanoid and rootOf(model)
        if root then
            local position = root.Position
            -- The radius bounds the index, not validity: a mob out of range is
            -- not invalid, merely out of useful reach.
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

-- The real instance name matching a canonical form, or nil if no such thing
-- currently exists. This is the only sanctioned path from quest text to an
-- entity: no `find`, no fuzzy matching.
function EnemyScanner:resolveName(canonical)
    if not canonical then return nil end
    local bucket = self.byCanonical[canonical]
    return bucket and bucket.liveName or nil
end

-- Live entries carrying this canonical form. Empty list if none: the caller
-- must handle that case, it is what triggers the region search.
function EnemyScanner:candidatesFor(canonical)
    local bucket = canonical and self.byCanonical[canonical]
    if not bucket then return {} end

    local alive = {}
    for _, entry in ipairs(bucket.entries) do
        -- Re-checked on read: between the scan and its use, a mob may have
        -- died or been removed. No stale reference leaves this function.
        if entry.model.Parent and entry.humanoid.Health > 0 then
            entry.health = entry.humanoid.Health
            entry.position = entry.root.Position
            alive[#alive + 1] = entry
        end
    end
    return alive
end

-- Highest max health observed for this name. Used to tell a boss from an
-- ordinary mob without a hardcoded list.
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
