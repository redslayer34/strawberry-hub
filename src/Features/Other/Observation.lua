--=============================================================================
-- FARMING OTHER: OBSERVATION (KEN) TRAINING AND OBSERVATION V2
--=============================================================================
--  Observation levels up by dodging hits with Ken on. The game blurs the
--  screen (Lighting.Blur) while Ken is active, which is how the reference
--  tells it apart: blur off -> press E next to a strong mob; blur on -> stand
--  right beside it and let it miss.
--
--  Observation V2 is the Sea 3 citizen questline (CitizenQuestProgress):
--    0  take the quest, kill 50 Forest Pirates
--    1  kill Captain Elephant
--    2  go to the Ken master's island
--    3  with 5000 Ken points: KenTalk2 Start, then buy the upgrade with 5M
--       Beli and an Apple, a Banana and a Pineapple (or a Fruit Bowl)
--=============================================================================

local Common = require("Features.Stack.Common")
local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Observation = {}

Observation.CITIZEN = Vector3.new(-12441.5908203125, 331.4884948730469, -7676.197265625)
Observation.KEN_ISLAND = Vector3.new(-12513.8, 336.167, -9872.91)
Observation.KEN_POINTS = 5000
Observation.UPGRADE_BELI = 5000000
Observation.FRUITS = { "Apple", "Banana", "Pineapple" }
Observation.SPAWNERS = { "AppleSpawner", "BananaSpawner", "PineappleSpawner" }
Observation.KEN_RETRY = 3   -- seconds after pressing E before judging it failed

local kenPressedAt
local forestSearch = Fight.newSearch()

local function kenOn()
    local blur = Services.get("Lighting"):FindFirstChild("Blur")
    return blur ~= nil and blur.Enabled == true
end

local function trainingMob()
    return Player.sea() == 2 and "Marine Captain" or "Marine Commodore"
end

-- One step of Ken training on `name`. Returns the status.
function Observation.train(name, hop)
    local mob = Enemies.nearest(name)
    local anchor = mob and mob.HumanoidRootPart or Enemies.spawnPoints(name)[1]
    if not anchor then
        Movement.stop()
        return "Waiting for " .. name
    end

    if kenOn() then
        kenPressedAt = nil
        -- Right beside the mob: it attacks and misses, which trains Ken.
        Common.goTo(mob and anchor.CFrame * CFrame.new(0, 0, 3) or anchor.CFrame * CFrame.new(0, 60, 0))
        return mob and "Dodging " .. name or "Looking for " .. name
    end

    Common.goTo(mob and anchor.CFrame * CFrame.new(0, 0, 50) or anchor.CFrame * CFrame.new(0, 60, 0))
    local now = os.clock()
    if not kenPressedAt then
        kenPressedAt = now
        Common.press("E")
    elseif now - kenPressedAt >= Observation.KEN_RETRY then
        kenPressedAt = nil
        if hop then
            Common.hop("Ken not coming back", true)
            return "Ken is down: hopping"
        end
    end
    return "Turning Ken on"
end

Observation.farm = Mode({
    name = "Observation",
    key = "OtherObservation",
    tick = function()
        return Observation.train(trainingMob(), Settings.get("OtherObservationHop") == true)
    end,
    stop = function() kenPressedAt = nil end,
})

---------------------------------------------------------------------------
-- Observation V2 (Sea 3 citizen questline)
---------------------------------------------------------------------------

local function progress()
    return Common.invoke("CitizenQuestProgress", "Citizen")
end

local function takeQuest()
    Common.goTo(Observation.CITIZEN)
    if Common.near(Observation.CITIZEN, 10) and Common.every("CitizenQuest", 3) then
        Services.invoke("StartQuest", "CitizenQuest", 1)
        Common.forget()
    end
    return "Taking the citizen quest"
end

local function hasAll(names)
    for _, name in ipairs(names) do
        if not Common.has(name) then return false end
    end
    return true
end

local function fruitOnSpawner()
    for _, name in ipairs(Observation.SPAWNERS) do
        local spawner = workspace:FindFirstChild(name)
        local tool = spawner and spawner:FindFirstChildOfClass("Tool")
        local handle = tool and tool:FindFirstChild("Handle")
        if handle then return tool, handle end
    end
    return nil
end

local function kenPoints()
    local text = Common.invoke("KenTalk", "Status")
    return tonumber((tostring(text or ""):gsub("%D", ""))) or 0
end

local function stage3(mode)
    if kenPoints() < Observation.KEN_POINTS then
        return "Training Ken: " .. Observation.train("Marine Commodore", false)
    end
    mode.target = nil
    if Common.every("KenTalk2Start", 5) then Services.invoke("KenTalk2", "Start") end
    local rich = (Player.data("Beli") or 0) >= Observation.UPGRADE_BELI
    if (rich and hasAll(Observation.FRUITS)) or Common.has("Fruit Bowl") then
        Movement.stop()
        if Common.every("KenTalk2Buy", 5) then
            Services.invoke("CitizenQuestProgress", "Citizen")
            Services.invoke("KenTalk2", "Buy")
            Common.forget()
        end
        return "Buying Observation V2"
    end
    local tool, handle = fruitOnSpawner()
    if tool then
        Common.goTo(handle.CFrame)
        if Common.near(handle.Position, 5) then Common.touch(handle) end
        return "Picking up " .. tool.Name
    end
    Movement.stop()
    return rich and "Waiting for Apple / Banana / Pineapple to spawn" or "Needs 5M Beli"
end

Observation.v2 = Mode({
    name = "Observation V2",
    key = "OtherObservationV2",
    sea = 3,
    want = function()
        local step = progress()
        return type(step) == "number" and step >= 0 and step <= 3
    end,
    idleStatus = "Done (or quest not available)",
    tick = function(mode)
        local step = progress()
        local title = Common.questTitle()
        if step == 0 then
            if title:find("Forest Pirate", 1, true) and title:find("50", 1, true) then
                return Common.farm(mode, { "Forest Pirate" }, forestSearch)
            end
            return takeQuest()
        end
        if step == 1 then
            if title:find("Captain Elephant", 1, true) then
                local boss, inWorld = Enemies.findBoss("Captain Elephant")
                if boss then return Common.fight(mode, boss, inWorld) end
                Movement.stop()
                return "Waiting for Captain Elephant"
            end
            return takeQuest()
        end
        if step == 2 then
            Common.goTo(Observation.KEN_ISLAND)
            return "Going to the Ken master"
        end
        return stage3(mode)
    end,
    stop = function()
        kenPressedAt = nil
        forestSearch:reset()
    end,
})

return Observation
