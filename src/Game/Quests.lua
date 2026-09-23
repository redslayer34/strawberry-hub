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

local function questPanel()
    local player = Services.player()
    local gui = player and player:FindFirstChild("PlayerGui")
    local main = gui and gui:FindFirstChild("Main")
    return main and main:FindFirstChild("Quest")
end

-- True while the game shows the quest panel.
function Quests.active()
    local panel = questPanel()
    return panel ~= nil and panel.Visible == true
end

-- The mob and count the active quest asks for: { mob = "Zombie", count = 8 },
-- or nil when no quest data is available.
function Quests.target()
    local data = guideData()
    local quest = data and data.QuestData
    if type(quest) ~= "table" or type(quest.Task) ~= "table" then return nil end
    local mob, count = next(quest.Task)
    if not mob then return nil end
    return { mob = mob, count = count }
end

-- Progress shown on the quest panel ("3/8"), as two numbers. Display only:
-- the farm never decides anything from it.
function Quests.progress()
    local panel = questPanel()
    if not panel or not panel.Visible then return nil end
    for _, node in ipairs(panel:GetDescendants()) do
        if node:IsA("TextLabel") then
            local current, required = tostring(node.Text):match("(%d+)%s*/%s*(%d+)")
            if current then return tonumber(current), tonumber(required) end
        end
    end
    return nil
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
