--=============================================================================
-- QUEST GIVER RESOLVER — identify the giver, do not memorise its position
--=============================================================================
--  The old approach stored QuestGiver = CFrame.new(...). An update moving the
--  NPC three metres was then enough to break the farm, with no way to notice.
--
--  Here the NPC is identified by what it IS: its name, the text of its
--  interaction prompt, the labels it carries. Its position is only a
--  consequence, cached so the NPCs folder is not re-swept every frame, and
--  invalidated the moment anything moves.
--
--  The cache drops on: server change, sea change, island change, NPC missing,
--  failed interaction, detected movement, expiry.
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")
local Trust = require("AutomationCore.Trust")

local QuestGiverResolver = {}

-- Below this, no NPC is considered a match: better to declare failure and let
-- recovery act than to go and talk to the wrong one.
local MIN_SCORE = 0.34
local MOVE_TOLERANCE = 15      -- studs before the NPC counts as having moved

---------------------------------------------------------------------------
-- NPC identity
---------------------------------------------------------------------------

local function rootOf(model)
    local root = model:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then return root end
    if model.PrimaryPart then return model.PrimaryPart end
    return model:FindFirstChildWhichIsA("BasePart")
end

-- Everything the NPC says about itself: its name, its prompts, its labels.
-- This is the NPC_IDENTITY level of the trust hierarchy.
local function identityTokens(model)
    local tokens = { model.Name }
    local interactive = false

    for _, node in ipairs(model:GetDescendants()) do
        if node:IsA("ProximityPrompt") then
            interactive = true
            if node.ObjectText ~= "" then tokens[#tokens + 1] = node.ObjectText end
            if node.ActionText ~= "" then tokens[#tokens + 1] = node.ActionText end
        elseif node:IsA("ClickDetector") then
            interactive = true
        elseif node:IsA("TextLabel") and node.Text ~= "" then
            -- Floating sign above the NPC: often carries the quest name rather
            -- than the character's.
            tokens[#tokens + 1] = node.Text
        end
    end

    return tokens, interactive
end

-- hints : { questId = "DesertQuest", target = "desert bandit", island = "Desert" }
-- Each hint is compared to each token; the best agreement wins.
local function scoreAgainst(tokens, hints)
    local best = 0
    for _, token in ipairs(tokens) do
        for _, hint in ipairs(hints) do
            if hint and hint ~= "" then
                local value = Names.similarity(token, hint)
                if value > best then best = value end
            end
        end
    end
    return best
end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------

-- Returns { model, root, position, name, score } or nil.
function QuestGiverResolver.find(ctx, hints, near)
    local folder = ctx.world.npcs()
    if not folder then return nil end

    local budget = ctx.cfg.Perception.MaxScanPerTick
    local seen = 0
    local best, bestScore

    for _, model in ipairs(folder:GetChildren()) do
        seen = seen + 1
        if seen > budget then break end

        local root = rootOf(model)
        if root then
            local tokens, interactive = identityTokens(model)
            local value = scoreAgainst(tokens, hints)

            -- An interactive NPC is a better candidate than a bystander that
            -- happens to share a word in its name.
            if interactive then value = value * 1.15 end

            -- Proximity bonus to the quest area: a giver sits on the same
            -- island as its mobs. Never decisive on its own.
            if near then
                local d = (root.Position - near).Magnitude
                if d < 600 then value = value * 1.2
                elseif d > 4000 then value = value * 0.5 end
            end

            if value > (bestScore or 0) then
                best, bestScore = {
                    model = model,
                    root = root,
                    position = root.Position,
                    name = model.Name,
                    score = value,
                    interactive = interactive,
                }, value
            end
        end
    end

    if not best or bestScore < MIN_SCORE then return nil end
    return best
end

---------------------------------------------------------------------------
-- Cache
---------------------------------------------------------------------------

local function cacheKey(hints)
    return table.concat(hints, "|")
end

-- Full resolution with the trust hierarchy applied:
--   3. identity of a present NPC
--   5. a giver settled on earlier on THIS server
--   6. a frozen coordinate from the historical table (last resort)
function QuestGiverResolver.resolve(ctx, hints, near, staticFallback)
    local key = cacheKey(hints)

    local position, level = Trust.resolve("quest giver", {
        {
            level = Trust.LEVEL.NPC_IDENTITY,
            why = "NPC identified in the Workspace",
            get = function()
                local found = QuestGiverResolver.find(ctx, hints, near)
                if not found then return nil end

                local model, origin = found.model, found.position
                -- The cache does not outlive the NPC: if it disappears or
                -- moves, the entry declares itself invalid.
                ctx.map:put("QuestGivers", key, origin, {
                    name = found.name, score = found.score,
                }, function()
                    if not model.Parent then return false end
                    local root = rootOf(model)
                    if not root then return false end
                    return (root.Position - origin).Magnitude <= MOVE_TOLERANCE
                end)

                Log.QuestGiver(string.format("%s (score %.2f)", found.name, found.score))
                return origin
            end,
        },
        {
            level = Trust.LEVEL.SERVER_MEMORY,
            why = "giver remembered on this server",
            get = function() return ctx.map:get("QuestGivers", key) end,
        },
        {
            level = Trust.LEVEL.STATIC_FALLBACK,
            why = "coordinate from the historical table",
            get = function() return staticFallback end,
        },
    })

    return position, level
end

-- Failed interaction: drop what we thought we knew immediately. Without this
-- the script keeps returning to the same empty spot forever.
function QuestGiverResolver.markFailed(ctx, hints, reason)
    ctx.map:invalidate("QuestGivers", cacheKey(hints), reason or "interaction failed")
    Log.QuestGiver("cache invalidated --", reason or "interaction failed")
end

return QuestGiverResolver
