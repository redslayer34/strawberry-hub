--=============================================================================
-- TARGET VALIDATOR — the only authority on whether a mob may be hit
--=============================================================================
--  No other module is allowed to conclude that an entity is a target.
--  BringController, AttackController and the farming modes receive lists that
--  are ALREADY filtered; they do not redo the sorting, and they do not relax
--  it.
--
--  Ten checks, in this order (cheapest first):
--
--    1. the entity exists and is still in the Workspace
--    2. it has a usable Humanoid
--    3. it has a manipulable root part
--    4. it is alive
--    5. it is not a player
--    6. it is not a quest NPC
--    7. its name matches the normalised target EXACTLY
--    8. it is not a boss, unless the quest names it explicitly
--    9. it belongs to the chosen spawn region
--   10. its reference is still fresh (neither destroyed nor moved off-world)
--
--  Check 7 is the heart of the system: equality of canonical forms, never
--  `string.find`, never "the name contains a close word". That is what stops
--  "Bandit" pulling in "Desert Bandit", and the reverse.
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")
local SpawnClusterResolver = require("AutomationCore.Perception.SpawnClusterResolver")

local Players = game:GetService("Players")

local TargetValidator = {}

-- Rejection counts by reason. Without them "0 valid targets" teaches nothing;
-- with them you know whether mobs are absent, out of zone, or all dead.
local rejections = {}

local function reject(reason)
    rejections[reason] = (rejections[reason] or 0) + 1
    return false, reason
end

function TargetValidator.stats()
    local out = {}
    for reason, count in pairs(rejections) do out[#out + 1] = { reason = reason, count = count } end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end

function TargetValidator.resetStats() table.clear(rejections) end

---------------------------------------------------------------------------
-- Boss
---------------------------------------------------------------------------

-- A boss is recognised by its health pool, not its name: no list to maintain,
-- and an update that adds a boss is covered automatically. An explicit
-- attribute, where the game sets one, wins over the heuristic.
function TargetValidator.isBoss(ctx, entry)
    local model = entry.model
    local flagged = model:GetAttribute("IsBoss")
    if flagged ~= nil then return flagged == true end

    if model:FindFirstChild("BossHealthBar") then return true end

    local maxHealth = entry.maxHealth or (entry.humanoid and entry.humanoid.MaxHealth) or 0
    return maxHealth >= ctx.cfg.Targets.BossHealthThreshold
end

---------------------------------------------------------------------------
-- Quest NPC
---------------------------------------------------------------------------

local function isQuestNPC(ctx, model)
    local npcs = ctx.world.npcs()
    if npcs and model:IsDescendantOf(npcs) then return true end

    -- A mob never carries an interaction prompt; a quest giver does.
    for _, node in ipairs(model:GetChildren()) do
        if node:IsA("ProximityPrompt") or node:IsA("ClickDetector") then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------

-- entry : an EnemyScanner entry, or a raw model (normalised here).
-- quest : QuestState. quest.AllowBoss is set only by BossFarm, which asks for
--         a boss explicitly.
-- Returns true, or false plus a reason.
function TargetValidator.isValidQuestTarget(ctx, entry, quest)
    -- Tolerates a raw model: the validator must be callable from anywhere,
    -- including on a reference a caller has been holding.
    if typeof(entry) == "Instance" then
        entry = {
            model = entry,
            humanoid = entry:FindFirstChildOfClass("Humanoid"),
            root = entry:FindFirstChild("HumanoidRootPart") or entry.PrimaryPart,
            name = entry.Name,
        }
    end

    -- 1. existence
    local model = entry and entry.model
    if not model or not model.Parent then return reject("gone") end

    -- 2. Humanoid
    local humanoid = entry.humanoid or model:FindFirstChildOfClass("Humanoid")
    if not humanoid or not humanoid.Parent then return reject("no humanoid") end

    -- 3. root part
    local root = entry.root
    if not root or not root.Parent or not root:IsA("BasePart") then
        return reject("no root")
    end

    -- 4. alive
    if humanoid.Health <= 0 then return reject("dead") end

    -- 5. not a player
    if Players:GetPlayerFromCharacter(model) then return reject("player") end

    -- 6. not a quest NPC
    if isQuestNPC(ctx, model) then return reject("quest npc") end

    -- 7. strict match against the quest objective
    if not quest or not quest.TargetName then
        -- No readable objective means no target is allowed. Better to do
        -- nothing than to hit at random: that gap is what used to vacuum up
        -- the whole zone between two targets.
        return reject("unknown objective")
    end
    local canonical = entry.canonical or Names.normalize(entry.name or model.Name)
    if canonical ~= quest.TargetName then return reject("name mismatch") end

    -- 8. boss
    if TargetValidator.isBoss(ctx, entry) then
        -- The name already matches (check 7). On top of that the active quest
        -- must actually name a boss, otherwise this is a beefy namesake we
        -- have no reason to engage.
        if not (quest.AllowBoss or quest.IsBossQuest) then
            return reject("boss not requested")
        end
    end

    -- 9. spawn region
    local position = root.Position
    if ctx.region and not SpawnClusterResolver.contains(ctx, ctx.region, position) then
        return reject("outside region")
    end

    -- 10. reference still usable
    if position.Y ~= position.Y then return reject("invalid position") end
    if humanoid.Health ~= humanoid.Health then return reject("invalid health") end

    return true
end

-- Filters a candidate list. This is the ONLY producer of target lists in the
-- whole system: the mandated flow is
--     QuestDetector -> TargetSelector -> TargetValidator -> BringController
function TargetValidator.filter(ctx, candidates, quest)
    local valid = {}
    for _, entry in ipairs(candidates) do
        if TargetValidator.isValidQuestTarget(ctx, entry, quest) then
            valid[#valid + 1] = entry
        end
    end
    return valid
end

-- Revalidation of a target held from one turn to the next. Called before EVERY
-- operation on a mob: never act on a reference that has aged.
function TargetValidator.stillValid(ctx, entry, quest)
    return TargetValidator.isValidQuestTarget(ctx, entry, quest)
end

function TargetValidator.logRejections(tag)
    local stats = TargetValidator.stats()
    if #stats == 0 then return end
    local parts = {}
    for i = 1, math.min(4, #stats) do
        parts[#parts + 1] = stats[i].reason .. "=" .. stats[i].count
    end
    Log.write(tag or "Target", "rejections:", table.concat(parts, ", "))
    TargetValidator.resetStats()
end

return TargetValidator
