--=============================================================================
-- FARMING OTHER: DOJO TRAINER AND DRAGON HUNTER (Sea 3, Hydra Island)
--=============================================================================
--  Dojo Trainer (RF/InteractDragonQuest) hands out one belt task at a time:
--    White   kill 20 mobs of your level quest
--    Yellow  sink or kill 5 sea events (ships, sharks, piranhas) at Zone 6
--    Green   sail in the danger-6 sea at Zone 6 for the quest's time
--    Purple  kill 3 Elite Hunters
--    Red     kill a Terrorshark
--  The boat belts use the Sea Events boat. Once the trainer's Progress
--  reaches its Goal the quest is claimed.
--
--  Dragon Hunter (RF/DragonHunter) asks for Hydra Enforcers, Venomous
--  Assailants or trees to cut on Waterfall island (skills fired at them).
--  Embers dropped on the way are collected first. A new task is asked once
--  the game says "Head back to the Dojo".
--=============================================================================

local Boat = require("Game.Boat")
local Common = require("Features.Stack.Common")
local EliteHunter = require("Features.Stack.EliteHunter")
local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local LevelFarm = require("Features.LevelFarm")
local Mastery = require("Game.Mastery")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Services = require("Core.Services")
local World = require("Game.World")

local Dragon = {}

Dragon.TRAINER = Vector3.new(5868.453125, 1211.7784423828125, 868.819580078125)
Dragon.WATERFALL = Vector3.new(5251.900390625, 17.18115234375, 453.6025390625)
Dragon.BELTS = {
    White = { kills = 20, what = "level quest mobs" },
    Yellow = { kills = 5, what = "sea events" },
    Green = { kills = 1, what = "a stay in the danger-6 sea" },
    Purple = { kills = 3, what = "Elite Hunters" },
    Red = { kills = 1, what = "a Terrorshark" },
}
Dragon.YELLOW_KINDS = { Ship = true, Shark = true, Piranha = true }
Dragon.YELLOW_RADIUS = 500
Dragon.DANGER_ZONE = "Zone 6"
Dragon.MIN_STAY = 30      -- seconds in the danger-6 sea when the goal is unknown
Dragon.TREE_TIME = 15     -- seconds on one tree
Dragon.BACK_TO_DOJO = "Head back to the Dojo to complete more tasks."

---------------------------------------------------------------------------
-- Dojo Trainer
---------------------------------------------------------------------------

local belt, kills, lastTarget, restUntil, stayFor, staySince
local seaBelt

local function trainer(command)
    return Common.netInvoke("RF/InteractDragonQuest", { NPC = "Dojo Trainer", Command = command })
end

-- Counts the engaged target once it dies.
local function countKill(target)
    if lastTarget and lastTarget ~= target and not Enemies.isAlive(lastTarget) then
        kills = kills + 1
    end
    lastTarget = target
end

local function askTrainer()
    Common.goTo(Dragon.TRAINER)
    if not Common.near(Dragon.TRAINER, 8) then return "Going to the Dojo Trainer" end
    if not Common.every("DojoAsk", 2) then return "Talking to the Dojo Trainer" end
    local info = trainer("RequestQuest")
    local quest = type(info) == "table" and info.Quest
    if type(quest) ~= "table" then
        restUntil = os.clock() + 600
        return "No task from the trainer (come back later)"
    end
    if (quest.Progress or 0) >= (quest.Goal or math.huge) then
        trainer("ClaimQuest")
        return "Claiming the belt"
    end
    if Dragon.BELTS[quest.BeltName] then
        belt, kills, lastTarget = quest.BeltName, 0, nil
        stayFor = math.max((tonumber(quest.Goal) or 0) - (tonumber(quest.Progress) or 0), Dragon.MIN_STAY)
        staySince = nil
        return quest.BeltName .. " belt started"
    end
    restUntil = os.clock() + 300
    return "That's enough training for today"
end

-- The Compass' danger level, or 0 when it is hidden.
function Dragon.danger()
    local player = Services.player()
    local level = player and Services.find(player, "PlayerGui.Main.Compass.Frame.DangerLevel")
    local label = level and level.Visible and level:FindFirstChild("TextLabel")
    return label and tonumber(label.Text) or 0
end

-- The boat belts: fights at sea, or sails to Zone 6.
seaBelt = function(mode)
    local Events = require("Features.Sea.Events")
    local kinds = belt == "Red" and { Terrorshark = true } or belt == "Yellow" and Dragon.YELLOW_KINDS or nil
    local target = kinds and Events.find(kinds, belt == "Yellow" and Dragon.YELLOW_RADIUS or Events.RADIUS)
    if lastTarget and lastTarget ~= target and not Events.alive(lastTarget) then kills = kills + 1 end
    lastTarget = target
    if target then return Events.fight(mode, target) end

    local status = Events.patrol(Boat.ZONES[Dragon.DANGER_ZONE], Dragon.DANGER_ZONE)
    if belt ~= "Green" then return status end
    if Dragon.danger() < 6 then
        staySince = nil
        return status
    end
    staySince = staySince or os.clock()
    local left = stayFor - (os.clock() - staySince)
    if left <= 0 then
        kills = kills + 1
        return "Stay done"
    end
    return string.format("In the danger-6 sea, %d s left", math.ceil(left))
end

Dragon.dojo = Mode({
    name = "Dojo Trainer",
    key = "OtherDojo",
    sea = 3,
    want = function()
        if restUntil and os.clock() < restUntil then return false end
        if belt == "Purple" then return EliteHunter.find() ~= nil end
        return true
    end,
    idleStatus = "Resting (no task from the trainer)",
    tick = function(mode)
        local goal = belt and Dragon.BELTS[belt]
        if goal and kills >= goal.kills then belt = nil end
        if not belt then return askTrainer() end

        local prefix = string.format("%s belt %d/%d: ", belt, kills, goal.kills)
        if belt == "White" then
            LevelFarm.tick()
            mode.target = LevelFarm.target
            countKill(LevelFarm.target)
            return prefix .. tostring(LevelFarm.status)
        end
        if belt == "Yellow" or belt == "Red" or belt == "Green" then return prefix .. seaBelt(mode) end
        local elite, inWorld = EliteHunter.find()
        if not elite then
            Movement.stop()
            return prefix .. "waiting for an Elite Hunter"
        end
        local status = EliteHunter.run(mode, elite, inWorld)
        countKill(mode.target)
        return prefix .. status
    end,
    stop = function()
        LevelFarm.stop()
        Boat.stop()
        lastTarget = nil
    end,
})

---------------------------------------------------------------------------
-- Dragon Hunter
---------------------------------------------------------------------------

local hunterTask, seenNotes = nil, {}
local ignored, tree, treeSince = {}, nil, nil
local hunterSearch = Fight.newSearch()

local function dragonHunter(context)
    return Common.netInvoke("RF/DragonHunter", { Context = context })
end

-- The game's "Head back to the Dojo" notification ends the task.
local function taskFinished()
    local player = Services.player()
    local notes = player and Services.find(player, "PlayerGui.Notifications")
    for _, note in ipairs(notes and notes:GetChildren() or {}) do
        local text = note:FindFirstChild("TranslateMe")
        if text and not seenNotes[note] and tostring(text.Text) == Dragon.BACK_TO_DOJO then
            seenNotes[note] = true
            return true
        end
    end
    return false
end

local function ember()
    for _, child in ipairs(workspace:GetChildren()) do
        local part = child.Name == "EmberTemplate" and not ignored[child] and child:FindFirstChild("Part")
        if part and part.Position.Y > -100 then return child, part end
    end
    return nil
end

local function isTree(model)
    if not model:IsA("Model") or model.Name ~= "Tree" or ignored[model] then return false end
    if model:GetAttribute("AlreadyDestroyedClient") then return false end
    local group = model:FindFirstChild("Group")
    return group ~= nil and (group:FindFirstChild("Meshes/bambootree") ~= nil
        or group:FindFirstChild("Meshes/plant1_Icosphere") ~= nil)
end

local function findTree(root)
    for _, child in ipairs(root:GetChildren()) do
        if isTree(child) then return child end
        local deeper = findTree(child)
        if deeper then return deeper end
    end
    return nil
end

local function cutTrees()
    local island = Services.find(workspace, "Map.Waterfall.IslandModel")
    if not island then
        Common.goTo(Dragon.WATERFALL)
        return "Going to Waterfall island"
    end
    local now = os.clock()
    if tree and (not tree.Parent or tree:GetAttribute("AlreadyDestroyedClient")
        or now - (treeSince or now) >= Dragon.TREE_TIME) then
        ignored[tree], tree = true, nil
    end
    if not tree then
        tree, treeSince = findTree(island), now
        if not tree then
            ignored = {}
            return "No tree left"
        end
    end

    local pivot = Common.pivot(tree)
    local aim
    if tree:FindFirstChild("Meshes/plant1_Icosphere", true) then
        Common.goTo(pivot)
        aim = pivot
    else
        Common.goTo(pivot * CFrame.new(5, -20, 0))
        aim = pivot * CFrame.new(0, -20, 0)
    end
    if Common.near(pivot.Position, 50) then Mastery.fireAt(aim) end
    return "Cutting a tree"
end

-- One step of the Dragon Hunter's tasks (also used to get Blaze Embers
-- for the Volcanic Magnet). Returns the status.
function Dragon.hunterStep(mode)
    if taskFinished() then hunterTask = nil end
    if not hunterTask then
        local npc = World.npcPosition("Dragon Hunter")
        if not npc then
            Movement.stop()
            return "Dragon Hunter not loaded (go to Hydra Island)"
        end
        Common.goTo(CFrame.new(npc) * CFrame.new(0, 0, 4))
        if Common.near(npc, 8) and Common.every("DragonHunterAsk", 2) then
            local check = dragonHunter("Check")
            if type(check) == "table" and check.Text then
                hunterTask = check.Text
            else
                local asked = dragonHunter("RequestQuest")
                hunterTask = type(asked) == "table" and asked.Text or nil
            end
        end
        return "Asking the Dragon Hunter"
    end

    local found, part = ember()
    if found then
        Common.goTo(part.CFrame)
        if Common.near(part.Position, 5) then ignored[found] = true end
        return "Collecting an ember"
    end

    local text = tostring(hunterTask)
    if text:find("Hydra Enforcers", 1, true) then
        return Common.farm(mode, { "Hydra Enforcer" }, hunterSearch)
    end
    if text:find("Venomous Assailants", 1, true) then
        return Common.farm(mode, { "Venomous Assailant" }, hunterSearch)
    end
    if text:find("trees", 1, true) then return cutTrees() end
    Movement.stop()
    return "Unknown task: " .. text
end

Dragon.hunter = Mode({
    name = "Dragon Hunter",
    key = "OtherDragonHunter",
    sea = 3,
    tick = function(mode) return Dragon.hunterStep(mode) end,
    stop = function()
        hunterSearch:reset()
        tree = nil
        Mastery.reset()
    end,
})

-- For the tab.
function Dragon.describe()
    return "Dojo: " .. (belt and (belt .. " belt, " .. kills .. " done") or "no belt task")
        .. "\nDragon Hunter: " .. tostring(hunterTask or "no task")
end

function Dragon.reset()
    belt, kills, lastTarget, restUntil, stayFor, staySince = nil, 0, nil, nil, Dragon.MIN_STAY, nil
    hunterTask, seenNotes, ignored, tree, treeSince = nil, {}, {}, nil, nil
    hunterSearch:reset()
end

Dragon.reset()

return Dragon
