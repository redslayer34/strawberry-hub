--=============================================================================
-- QUEST DETECTOR — reads the REAL objective of the active quest
--=============================================================================
--  The architecture's absolute rule: the active quest is the source of truth
--  for choosing mobs. This module therefore sits at the top of the trust
--  hierarchy; everything else follows from it.
--
--  The old loop merely read the title to check it contained the expected name,
--  the name coming from a frozen table indexed by level. This is the reverse:
--  the objective is extracted from the game, and the frozen table now only
--  suggests a quest to pick up when none is active.
--
--      "Defeat 8 Desert Bandits"  ->  TargetName = "desert bandit"
--                                     RequiredCount = 8
--
--  The extracted name is a CANONICAL form, not an instance name. Matching it
--  to the real entity is EnemyScanner's job -- only it knows what actually
--  exists in the Workspace.
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")

local QuestDetector = {}

-- Neutral quest state. Always the same shape, so no caller has to test for the
-- existence of a field.
function QuestDetector.blank()
    return {
        Active = false,
        QuestName = nil,       -- displayed title ("Bandit Hunter")
        TargetRaw = nil,       -- objective as written ("Desert Bandits")
        TargetName = nil,      -- canonical form ("desert bandit")
        ResolvedName = nil,    -- real instance name, filled in by EnemyScanner
        RequiredCount = 0,
        CurrentCount = 0,
        Remaining = 0,
        QuestGiver = nil,
        Island = nil,
        IsBossQuest = false,
        ReadAt = 0,
    }
end

---------------------------------------------------------------------------
-- Reading the text
---------------------------------------------------------------------------

-- Known path first (fast, one indirection), scan second (robust to a UI
-- rework). An update that moves the label slows the read down; it does not
-- break it.
local function knownPathText(frame)
    local ok, text = pcall(function()
        return frame.Container.QuestTitle.Title.Text
    end)
    if ok and type(text) == "string" and text ~= "" then return text end
    return nil
end

local function collectTexts(frame, limit)
    local texts = {}
    local seen = 0
    for _, node in ipairs(frame:GetDescendants()) do
        seen = seen + 1
        if seen > limit then break end
        if node:IsA("TextLabel") or node:IsA("TextButton") then
            local text = node.Text
            if type(text) == "string" and text ~= "" then
                texts[#texts + 1] = text
            end
        end
    end
    return texts
end

---------------------------------------------------------------------------
-- Extraction
---------------------------------------------------------------------------

local function matchObjective(text, patterns)
    for _, pattern in ipairs(patterns) do
        local count, target = text:match(pattern)
        if count and target then
            return tonumber(count), target
        end
    end
    return nil
end

local function matchProgress(text, patterns)
    for _, pattern in ipairs(patterns) do
        local current, required = text:match(pattern)
        if current and required then
            return tonumber(current), tonumber(required)
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

function QuestDetector.isActive(ctx)
    local frame = ctx.world.questFrame()
    return frame ~= nil and frame.Visible == true
end

-- Reads the current quest state. Guesses nothing: if the objective is not
-- readable, RequiredCount stays 0 and TargetName stays nil, which blocks the
-- bring upstream rather than letting an empty filter through.
function QuestDetector.read(ctx)
    local state = QuestDetector.blank()
    local frame = ctx.world.questFrame()

    if not frame or frame.Visible ~= true then
        return state
    end

    state.Active = true
    state.ReadAt = os.clock()

    local cfg = ctx.cfg.Quest
    local title = knownPathText(frame)
    local texts = collectTexts(frame, ctx.cfg.Perception.MaxScanPerTick)
    if title then table.insert(texts, 1, title) end

    state.QuestName = title or texts[1]

    -- Objective: the first text expressing "N targets to defeat".
    for _, text in ipairs(texts) do
        local count, target = matchObjective(text, cfg.Patterns)
        if count then
            -- The objective sometimes carries its own progress:
            -- "Defeat 8 Desert Bandits [3/8]". Strip it from the name.
            target = target:gsub("%[.-%]", ""):gsub("%(.-%)", "")
            target = target:gsub("%d+%s*/%s*%d+", "")
            state.RequiredCount = count
            state.TargetRaw = (target:gsub("^%s*(.-)%s*$", "%1"))
            state.TargetName = Names.normalize(target)
            break
        end
    end

    -- Progress: prefer the pair whose total matches the objective already
    -- read, otherwise the first one found.
    local fallbackCurrent, fallbackRequired
    for _, text in ipairs(texts) do
        local current, required = matchProgress(text, cfg.ProgressPatterns)
        if current then
            if state.RequiredCount > 0 and required == state.RequiredCount then
                state.CurrentCount = current
                break
            end
            fallbackCurrent = fallbackCurrent or current
            fallbackRequired = fallbackRequired or required
        end
    end

    if state.CurrentCount == 0 and fallbackCurrent then
        state.CurrentCount = fallbackCurrent
        if state.RequiredCount == 0 and fallbackRequired then
            state.RequiredCount = fallbackRequired
        end
    end

    state.Remaining = math.max(0, state.RequiredCount - state.CurrentCount)

    -- Boss-quest hint. Only confirmed when the real entity carries boss-level
    -- health: here we merely flag it, the decision to allow a boss belongs to
    -- TargetValidator.
    state.IsBossQuest = state.RequiredCount == 1

    return state
end

-- True when two states name the same objective. Used to detect a quest change
-- without rebuilding the whole decision chain.
function QuestDetector.sameObjective(a, b)
    if not a or not b then return false end
    if not a.Active or not b.Active then return a.Active == b.Active end
    return a.TargetName == b.TargetName and a.RequiredCount == b.RequiredCount
end

function QuestDetector.describe(state)
    if not state or not state.Active then return "no active quest" end
    if not state.TargetName then
        return "quest active, objective unreadable (" .. tostring(state.QuestName) .. ")"
    end
    return string.format("%s -- %s %d/%d",
        tostring(state.QuestName), state.TargetRaw or state.TargetName,
        state.CurrentCount, state.RequiredCount)
end

-- Logs changes only: the read runs several times a second and the journal has
-- to stay readable.
function QuestDetector.logChange(previous, current)
    if QuestDetector.sameObjective(previous, current) then
        if previous and current and previous.CurrentCount ~= current.CurrentCount then
            Log.Quest("Progress =", current.CurrentCount .. "/" .. current.RequiredCount)
            if current.Remaining == 0 then Log.Quest("Complete") end
        end
        return
    end

    if not current.Active then
        Log.Quest("quest lost")
        return
    end
    if current.TargetName then
        Log.Quest("Target =", current.TargetRaw or current.TargetName)
        Log.Quest("Progress =", current.CurrentCount .. "/" .. current.RequiredCount)
    else
        Log.Quest("objective unreadable --", tostring(current.QuestName))
    end
end

return QuestDetector
