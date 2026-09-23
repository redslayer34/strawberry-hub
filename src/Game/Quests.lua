--=============================================================================
-- QUESTS — what the game says about quests, read from its own modules
--=============================================================================
--  No text parsing and no hand-written quest table. The game ships both:
--
--    ReplicatedStorage.Quests                 every quest:
--        Quests[questName][id] = { LevelReq, Task = { [mobName] = count } }
--    ReplicatedStorage.GuideModule.Data       live state:
--        .QuestData.Task = { [mobName] = count }   the ACTIVE quest
--        .NPCList[npc]   = { NPCName, InternalQuestName, Levels, Position }
--                                                  quest givers of THIS sea
--=============================================================================

local Services = require("Core.Services")

local Quests = {}

-- Quests present in the table that the level farm must never pick: story and
-- special quests with their own requirements.
Quests.EXCLUDED = {
    BartiloQuest = true,
    Trainees = true,
    MarineQuest = true,
    CitizenQuest = true,
}

local function guideData()
    local guide = Services.module("GuideModule")
    return type(guide) == "table" and guide.Data or nil
end

local function toVector(position)
    if typeof(position) == "CFrame" then return position.Position end
    return position
end

-- Every "Quest" frame directly under a ScreenGui of PlayerGui. The panel is
-- usually PlayerGui.Main.Quest, but some clients show it under
-- "Main (minimal)" or a second "Main": checking one path only made a taken
-- quest invisible to the farm.
local function questPanels()
    local panels = {}
    local player = Services.player()
    local gui = player and player:FindFirstChild("PlayerGui")
    if not gui then return panels end
    for _, screen in ipairs(gui:GetChildren()) do
        local panel = screen:FindFirstChild("Quest")
        if panel then panels[#panels + 1] = panel end
    end
    return panels
end

function Quests.panelVisible()
    for _, panel in ipairs(questPanels()) do
        if panel.Visible == true then return true end
    end
    return false
end

-- True when a GUI object is actually on screen: it and every ancestor up to
-- its ScreenGui are visible, and the ScreenGui is enabled.
local function shown(node)
    while node do
        if node:IsA("ScreenGui") then return node.Enabled ~= false end
        if node.Visible == false then return false end
        node = node.Parent
    end
    return true
end

-- "0/8" next to an objective title: the progress label sits a few levels up
-- from the title, inside the same panel.
local function progressNear(label)
    local root = label
    for _ = 1, 4 do
        if not root or not root.Parent then break end
        root = root.Parent
        for _, node in ipairs(root:GetDescendants()) do
            if node:IsA("TextLabel") then
                local current, required = tostring(node.Text):match("^%s*(%d+)%s*/%s*(%d+)%s*$")
                if current then return tonumber(current), tonumber(required) end
            end
        end
    end
    return nil
end

-- The objective, found by its text ("Defeat 8 Vampires") anywhere in
-- PlayerGui. This is what the reference reads too
-- (Main.Quest.Container.QuestTitle.Title), but searched rather than assumed:
-- on some clients the panel is not at that path, or reports itself hidden
-- while on screen. A label that is on screen wins; a hidden one still counts
-- until its counter shows the quest complete. Cached briefly because it
-- walks the whole PlayerGui.
Quests.SCAN_EVERY = 0.3
local lastScan, lastPanel = -math.huge, nil

function Quests.readPanel()
    local now = os.clock()
    if now - lastScan < Quests.SCAN_EVERY then return lastPanel end
    lastScan, lastPanel = now, nil

    local player = Services.player()
    local gui = player and player:FindFirstChild("PlayerGui")
    if not gui then return nil end

    local hiddenMatch
    for _, node in ipairs(gui:GetDescendants()) do
        if node:IsA("TextLabel") then
            local text = tostring(node.Text)
            local count = text:match("^%s*[Dd]efeat%s+(%d+)")
            if count then
                local entry = { title = text, count = tonumber(count), label = node }
                if shown(node) then
                    lastPanel = entry
                    break
                end
                hiddenMatch = hiddenMatch or entry
            end
        end
    end

    if not lastPanel and hiddenMatch then
        local current, required = progressNear(hiddenMatch.label)
        if not (current and required and current >= required) then
            hiddenMatch.hidden = true
            lastPanel = hiddenMatch
        end
    end
    return lastPanel
end

-- Every mob name any quest asks for, longest first, so "Swan Pirate" wins
-- over "Pirate" when both appear in a title.
local taskNames

local function allTaskNames()
    if taskNames then return taskNames end
    local all = Services.module("Quests")
    if type(all) ~= "table" then return {} end
    local seen, names = {}, {}
    for _, list in pairs(all) do
        if type(list) == "table" then
            for _, quest in pairs(list) do
                if type(quest) == "table" and type(quest.Task) == "table" then
                    for mob in pairs(quest.Task) do
                        if not seen[mob] then
                            seen[mob] = true
                            names[#names + 1] = mob
                        end
                    end
                end
            end
        end
    end
    table.sort(names, function(a, b) return #a > #b end)
    taskNames = names
    return names
end

-- The quest mob named in an objective title ("Defeat 8 Vampires" -> Vampire).
function Quests.mobFromTitle(title)
    for _, name in ipairs(allTaskNames()) do
        if title:find(name, 1, true) then return name end
    end
    return nil
end

-- The mob and count the active quest asks for: { mob = "Zombie", count = 8 },
-- or nil. GuideModule's live data first; then the objective on screen, since
-- some executors' require hands back a frozen copy of GuideModule whose
-- QuestData never fills in.
function Quests.target()
    local data = guideData()
    local quest = data and data.QuestData
    if type(quest) == "table" and type(quest.Task) == "table" then
        local mob, count = next(quest.Task)
        if mob then return { mob = mob, count = count, source = "GuideModule" } end
    end

    local panel = Quests.readPanel()
    if panel then
        local mob = Quests.mobFromTitle(panel.title)
        if mob then return { mob = mob, count = panel.count, source = "screen" } end
    end
    return nil
end

-- Progress shown next to the objective ("0/8"). Display only.
function Quests.progress()
    local panel = Quests.readPanel()
    if not panel then return nil end
    return progressNear(panel.label)
end

-- True while a quest is held: a quest panel or objective is on screen, or
-- GuideModule holds quest data.
function Quests.active()
    return Quests.panelVisible() or Quests.readPanel() ~= nil or Quests.target() ~= nil
end

-- Where the objective was found, for the status panel.
function Quests.describe()
    local panel = Quests.readPanel()
    local target = Quests.target()
    local where = "objective: not on screen"
    if panel then
        local ok, path = pcall(function() return panel.label:GetFullName() end)
        where = "objective: \"" .. panel.title .. "\"" .. (panel.hidden and " (hidden)" or "")
            .. (ok and (" @ " .. path) or "")
    end
    return where .. "  |  target: " .. (target and (target.mob .. " (" .. target.source .. ")") or "none")
end

-- Test hook.
function Quests.reset()
    lastScan, lastPanel, taskNames = -math.huge, nil, nil
end

-- The best quest for `level`, among the quest givers of the current sea (the
-- only ones NPCList contains): the highest LevelReq not above the level,
-- whose task asks for more than one mob (a count of 1 is a boss quest).
--
-- Returns { questName, id, mob, count, level, npc, position } or nil.
function Quests.best(level)
    local data = guideData()
    local npcs = data and data.NPCList
    local all = Services.module("Quests")
    if type(npcs) ~= "table" or type(all) ~= "table" then return nil end

    local best, bestLevel = nil, -1
    for _, npc in pairs(npcs) do
        local questName = npc.InternalQuestName
        local list = questName and all[questName]
        if type(list) == "table" and not Quests.EXCLUDED[questName]
            and type(npc.Levels) == "table" then
            for id, required in pairs(npc.Levels) do
                local quest = list[id]
                if type(quest) == "table" and type(quest.Task) == "table" then
                    local mob, count = next(quest.Task)
                    if mob and type(count) == "number" and count > 1
                        and required <= level and required >= bestLevel then
                        best = {
                            questName = questName,
                            id = id,
                            mob = mob,
                            count = count,
                            level = required,
                            npc = npc.NPCName,
                            position = toVector(npc.Position),
                        }
                        bestLevel = required
                    end
                end
            end
        end
    end
    return best
end

function Quests.start(plan)
    return Services.invoke("StartQuest", tostring(plan.questName), plan.id)
end

function Quests.abandon()
    return Services.invoke("AbandonQuest")
end

return Quests
