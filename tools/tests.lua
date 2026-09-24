--=============================================================================
-- CORE TESTS — behaviour of the engine, outside the game
--=============================================================================
--  Run by tools/test.py: stubs, then the bundle (entry line removed), then
--  this file, so `require` resolves the real modules.
--
--  The cases are the ones where a regression would be silent in game: the
--  quest picked, the hits sent, the mobs pulled, where the character flies.
--=============================================================================

local passed, failed = 0, 0
local failures = {}

local function check(name, condition, detail)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = name .. (detail ~= nil and ("  -- " .. tostring(detail)) or "")
    end
end

local function eq(name, actual, expected)
    check(name, actual == expected,
        string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local function near(name, a, b, tolerance)
    local distance = (a - b).Magnitude
    check(name, distance <= (tolerance or 0.01),
        string.format("%s vs %s (off by %.2f)", tostring(a), tostring(b), distance))
end

-- CommF_ calls made with a given action (other calls, like Buso, ignored).
local function calls(remote, action)
    local out = {}
    for _, call in ipairs(remote.Invoked or {}) do
        if call[1] == action then out[#out + 1] = call end
    end
    return out
end

---------------------------------------------------------------------------
-- Modules load
---------------------------------------------------------------------------

local MODULES = {
    "Core.Services", "Core.Settings", "Core.Loop", "Core.Player",
    "Game.Quests", "Game.Enemies", "Game.Movement", "Game.Combat", "Game.Bring",
    "Features.LevelFarm", "Features.Farm", "Features.Fight", "Features.MobFarm",
    "Features.BossFarm", "Features.KatakuriFarm", "Features.BoneFarm",
    "Features.MaterialFarm", "Features.KillMobFarm", "Features.AuraFarm",
    "Game.Mastery", "Game.AimHook", "Game.Data",
    "Features.Travel", "Features.Stats", "Features.PlayerTweaks", "Game.World", "Game.Server",
    "Game.Router", "Game.Entrances", "Game.Hook", "Game.Regions", "Game.TeleportTag", "Game.Gateway",
    "Game.IslandLoader",
    "Features.StackFarm", "Features.Stack.Common", "Features.Stack.World", "Features.Stack.Chests",
    "Features.Stack.Bosses", "Features.Stack.Summons", "Features.Stack.EliteHunter", "Features.Stack.Events",
    "Features.ChestHunt", "Features.Other.Mode", "Features.Other.Simple", "Features.Other.Observation",
    "Features.Other.Dragon", "Features.Other.Fishing", "Features.Esp", "Features.Pvp", "Features.Screen",
    "Features.Webhook", "Features.Fruits", "Features.Raids", "Features.Dungeon",
    "Features.Items", "Features.Items.Swords", "Features.Items.Cdk", "Features.Items.Guitar",
    "Features.Items.Saber", "Features.Items.Mastery", "Features.Races.Duel", "Features.Races.Upgrade",
    "Features.Races.V4", "Game.Boat", "Features.Sea.Events", "Features.Sea.Islands", "Features.Sea.Volcano",
}
for _, name in ipairs(MODULES) do
    local ok, err = pcall(require, name)
    check("loads " .. name, ok, err)
end

local Services = require("Core.Services")
local Settings = require("Core.Settings")
local Loop = require("Core.Loop")
local Player = require("Core.Player")
local Quests = require("Game.Quests")
local Enemies = require("Game.Enemies")
local Movement = require("Game.Movement")
local Combat = require("Game.Combat")
local Bring = require("Game.Bring")
local LevelFarm = require("Features.LevelFarm")
local Farm = require("Features.Farm")
local Mastery = require("Game.Mastery")
local AimHook = require("Game.AimHook")
local Data = require("Game.Data")
local BossFarm = require("Features.BossFarm")
local KatakuriFarm = require("Features.KatakuriFarm")
local BoneFarm = require("Features.BoneFarm")
local MaterialFarm = require("Features.MaterialFarm")
local KillMobFarm = require("Features.KillMobFarm")
local AuraFarm = require("Features.AuraFarm")
local Travel = require("Features.Travel")
local World = require("Game.World")
local Stats = require("Features.Stats")
local Server = require("Game.Server")
local Router = require("Game.Router")
local Entrances = require("Game.Entrances")
local Regions = require("Game.Regions")
local TeleportTag = require("Game.TeleportTag")
local Gateway = require("Game.Gateway")
local IslandLoader = require("Game.IslandLoader")
local Hook = require("Game.Hook")

---------------------------------------------------------------------------
-- World builders
---------------------------------------------------------------------------

local rs = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

local function clear(instance)
    for _, child in ipairs(instance:GetChildren()) do child.Parent = nil end
end

local function part(name, position, parent)
    local p = newInstance("Part", name, parent)
    p.Position = position
    p.Size = Vector3.new(2, 2, 1)
    p.CanCollide = true
    return p
end

local function folder(name, parent)
    return parent:FindFirstChild(name) or newInstance("Folder", name, parent)
end

local function moduleScript(name, parent, value)
    local m = newInstance("ModuleScript", name, parent)
    m.ModuleValue = value
    return m
end

local function mob(name, position, health, parent)
    local model = newInstance("Model", name, parent or folder("Enemies", workspace))
    local humanoid = newInstance("Humanoid", "Humanoid", model)
    humanoid.Health = health or 100
    part("HumanoidRootPart", position, model)
    part("Head", position + Vector3.new(0, 1.5, 0), model)
    part("UpperTorso", position, model)
    model.WorldPivot = CFrame.new(position)
    return model
end

local world = {}

local function setup(options)
    options = options or {}
    clear(workspace)
    clear(rs)
    clear(players)
    clearTasks()
    Services.reset()
    Settings.reset()
    Enemies.reset()
    Bring.reset()
    Movement.reset()
    Quests.reset()
    Quests.SCAN_EVERY = 0
    Router.reset()
    Entrances.reset(nil)
    Regions.reset()
    TeleportTag.reset()
    IslandLoader.reset()
    require("Features.PlayerTweaks").reset()
    Loop.stopAll()
    WARNINGS = {}
    game.PlaceId = 4442272183

    folder("Enemies", workspace)
    local characters = folder("Characters", workspace)

    local player = newInstance("Player", "Tester", players)
    players.LocalPlayer = player
    local character = newInstance("Model", "Tester", characters)
    local humanoid = newInstance("Humanoid", "Humanoid", character)
    humanoid.Health = 100
    local hrp = part("HumanoidRootPart", options.position or Vector3.new(0, 0, 0), character)
    local stun = newInstance("NumberValue", "Stun", character)
    stun.Value = 0
    player.Character = character
    newInstance("Backpack", "Backpack", player)
    local data = newInstance("Folder", "Data", player)
    local level = newInstance("IntValue", "Level", data)
    level.Value = options.level or 960
    newInstance("BoolValue", "DataLoaded", player)
    local gui = newInstance("PlayerGui", "PlayerGui", player)
    local main = newInstance("ScreenGui", "Main", gui)
    local questPanel = newInstance("Frame", "Quest", main)
    questPanel.Visible = false

    -- Remotes
    local remotes = folder("Remotes", rs)
    local commF = newInstance("RemoteFunction", "CommF_", remotes)

    -- Combat modules
    local modules = folder("Modules", rs)
    moduleScript("CombatUtil", modules, {
        GetRigOfHitPart = function(_, hitPart) return hitPart.Parent end,
        IsVulnerable = function(_, rig) return not rig.Invulnerable end,
    })
    local net = moduleScript("Net", modules, nil)
    local registerAttack = newInstance("RemoteEvent", "RE/RegisterAttack", net)
    local childRegisterHit = newInstance("RemoteEvent", "RE/RegisterHit", net)
    local moduleRegisterHit = newInstance("RemoteEvent", "RegisterHitFromModule", net)
    net.ModuleValue = {
        RemoteEvent = function(_, name)
            if name == "RegisterHit" then return moduleRegisterHit end
            return net:FindFirstChild("RE/" .. name)
        end,
    }

    -- Quest data
    local guide = {
        Data = {
            QuestData = nil,
            NPCList = {
                graveyard = {
                    NPCName = "Graveyard Quest Giver",
                    InternalQuestName = "HauntedQuest1",
                    Levels = { 950, 975 },
                    Position = CFrame.new(1000, 10, 1000),
                },
                bartilo = {
                    NPCName = "Bartilo",
                    InternalQuestName = "BartiloQuest",
                    Levels = { 955 },
                    Position = Vector3.new(0, 0, 0),
                },
                bossGiver = {
                    NPCName = "Boss Giver",
                    InternalQuestName = "BossQuest",
                    Levels = { 958 },
                    Position = Vector3.new(0, 0, 0),
                },
            },
        },
    }
    moduleScript("GuideModule", rs, guide)
    moduleScript("Quests", rs, {
        HauntedQuest1 = {
            { LevelReq = 950, Task = { Zombie = 8 } },
            { LevelReq = 975, Task = { Vampire = 8 } },
        },
        BartiloQuest = { { LevelReq = 955, Task = { ["Swan Pirate"] = 50 } } },
        BossQuest = { { LevelReq = 958, Task = { ["Some Boss"] = 1 } } },
        PirateQuest = { { LevelReq = 5000, Task = { Pirate = 5 } } },
    })

    world = {
        player = player, character = character, humanoid = humanoid, hrp = hrp,
        stun = stun, level = level, questPanel = questPanel, commF = commF,
        guide = guide, registerAttack = registerAttack,
        childRegisterHit = childRegisterHit, moduleRegisterHit = moduleRegisterHit,
        characters = characters,
    }
    return world
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

setup()
eq("setting default", Settings.get("TweenSpeed"), 300)
Settings.set("TweenSpeed", 200)
eq("setting set", Settings.get("TweenSpeed"), 200)
check("unknown setting rejected", not pcall(Settings.set, "Nope", 1))

do
    local seen = {}
    local remove = Settings.onChanged(function(key, value) seen[#seen + 1] = key .. "=" .. tostring(value) end)
    Settings.set("BringCount", 4)
    Settings.set("BringCount", 4)
    eq("listener fired once per real change", #seen, 1)
    eq("listener gets key and value", seen[1], "BringCount=4")
    remove()
    Settings.set("BringCount", 5)
    eq("removed listener no longer fires", #seen, 1)
end

---------------------------------------------------------------------------
-- Loop
---------------------------------------------------------------------------

setup()
do
    local count = 0
    Loop.start("counter", 0, function() count = count + 1 end)
    eq("loop runs immediately", count, 1)
    stepTasks()
    eq("loop runs again on the next step", count, 2)
    check("loop reported running", Loop.isRunning("counter"))
    Loop.stop("counter")
    stepTasks()
    stepTasks()
    eq("stopped loop does not run", count, 2)

    local runs = 0
    Loop.start("broken", 0, function() runs = runs + 1; error("boom") end)
    stepTasks()
    stepTasks()
    eq("an error does not kill the loop", runs, 3)
    eq("errors are throttled to one warning", #WARNINGS, 1)

    local asked = 0
    Loop.start("dynamic", function() asked = asked + 1; return 0 end, function() end)
    stepTasks()
    check("function interval is re-read", asked >= 1)

    Loop.stopAll()
    check("stopAll stops everything", not Loop.isRunning("broken") and not Loop.isRunning("dynamic"))
end

---------------------------------------------------------------------------
-- Services: game modules go through the NATIVE require
---------------------------------------------------------------------------

setup()
do
    local util = Services.module("Modules.CombatUtil")
    check("game module resolved through native require", type(util) == "table" and util.GetRigOfHitPart ~= nil)
    eq("missing module is nil", Services.module("Modules.Missing"), nil)

    local broken = moduleScript("Broken", rs, nil)
    broken.ModuleError = "exploded"
    eq("erroring module is nil", Services.module("Broken"), nil)
    eq("erroring module warns", #WARNINGS, 1)
    Services.module("Broken")
    eq("erroring module is not retried", #WARNINGS, 1)

    eq("RegisterAttack via its child", Services.netRemote("RegisterAttack", false), world.registerAttack)
    eq("RegisterHit via the Net module", Services.netRemote("RegisterHit", true), world.moduleRegisterHit)

    world.commF.OnInvoke = function(action) return action .. "!" end
    eq("invoke returns the result", Services.invoke("Ping"), "Ping!")
    world.commF.Parent = nil
    eq("invoke without remote is nil", Services.invoke("Ping"), nil)
end

---------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------

setup()
do
    eq("level from Data", Player.level(), 960)
    eq("sea from PlaceId", Player.sea(), 2)
    game.PlaceId = 100117331123089
    eq("third sea place id", Player.sea(), 3)
    check("alive", Player.alive())

    local melee = newInstance("Tool", "Combat", world.player.Backpack)
    melee.ToolTip = "Melee"
    eq("finds a tool by ToolTip", Player.findTool("Melee"), melee)
    eq("no tool of that kind", Player.findTool("Sword"), nil)
    Player.equip("Melee")
    eq("equip moves the tool to the character", melee.Parent, world.character)
    eq("equipped tool", Player.equippedTool(), melee)

    check("not stunned", not Player.stunned())
    world.stun.Value = 1
    check("stunned", Player.stunned())

    world.humanoid.Health = 0
    check("dead", not Player.alive())
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------

setup()
do
    local plan = Quests.best(960)
    check("a quest is found", plan ~= nil)
    eq("best quest name", plan and plan.questName, "HauntedQuest1")
    eq("best quest id", plan and plan.id, 1)
    eq("best quest mob", plan and plan.mob, "Zombie")
    check("CFrame position converted", plan and typeof(plan.position) == "Vector3")

    local higher = Quests.best(980)
    eq("higher level picks the next quest", higher and higher.mob, "Vampire")
    eq("higher level quest id", higher and higher.id, 2)

    eq("below every quest", Quests.best(10), nil)

    check("no active quest", not Quests.active())
    eq("no quest data", Quests.target(), nil)

    -- Some clients show the panel under "Main (minimal)" instead of "Main".
    local minimal = newInstance("ScreenGui", "Main (minimal)", world.player.PlayerGui)
    local otherPanel = newInstance("Frame", "Quest", minimal)
    otherPanel.Visible = true
    check("panel under Main (minimal) counts", Quests.active())
    otherPanel.Visible = false
    check("hidden panels and no data: no quest", not Quests.active())

    world.guide.Data.QuestData = { Task = { Zombie = 8 } }
    check("GuideModule quest data alone counts", Quests.active())
    world.questPanel.Visible = true
    check("quest panel visible", Quests.active())
    local target = Quests.target()
    eq("active quest mob", target and target.mob, "Zombie")
    eq("active quest count", target and target.count, 8)

    local titleLabel = newInstance("TextLabel", "Title", world.questPanel)
    titleLabel.Text = "Defeat 8 Zombies"
    local label = newInstance("TextLabel", "Progress", world.questPanel)
    label.Text = "3/8"
    local current, required = Quests.progress()
    eq("progress current", current, 3)
    eq("progress required", required, 8)

    world.commF.OnInvoke = function() return true end
    Quests.start(plan)
    local call = world.commF.Invoked[1]
    eq("StartQuest action", call[1], "StartQuest")
    eq("StartQuest quest name", call[2], "HauntedQuest1")
    eq("StartQuest id", call[3], 1)
end

-- The in-game case: GuideModule's QuestData stays empty (frozen copy) and
-- the objective is only readable on screen, under an unexpected path.
setup()
do
    local screen = newInstance("ScreenGui", "SomethingElse", world.player.PlayerGui)
    local box = newInstance("Frame", "Box", screen)
    local titleFrame = newInstance("Frame", "QuestTitle", box)
    local title = newInstance("TextLabel", "Title", titleFrame)
    title.Text = "Defeat 8 Vampires"
    local counter = newInstance("TextLabel", "Counter", box)
    counter.Text = "0/8"

    check("objective on screen counts as a quest", Quests.active())
    local target = Quests.target()
    eq("mob read from the title", target and target.mob, "Vampire")
    eq("count read from the title", target and target.count, 8)
    eq("source is the screen", target and target.source, "screen")
    local current, required = Quests.progress()
    eq("progress next to the title", current, 0)
    eq("progress total", required, 8)

    box.Visible = false
    local panel = Quests.readPanel()
    check("hidden objective still counts while incomplete", panel ~= nil and panel.hidden)
    counter.Text = "8/8"
    check("hidden completed objective ignored", Quests.readPanel() == nil)
    check("no quest once completed and hidden", not Quests.active())

    eq("longest mob name wins", Quests.mobFromTitle("Defeat 50 Swan Pirates"), "Swan Pirate")
    check("describe mentions the objective", Quests.describe():find("objective") ~= nil)
end

setup()
do
    LevelFarm.stop()
    LevelFarm.QUEST_SETTLE = 0
    world.commF.OnInvoke = function() return true end
    local title = newInstance("TextLabel", "Title", world.questPanel)
    title.Text = "Defeat 8 Vampires"
    world.questPanel.Visible = true
    world.hrp.Position = Vector3.new(1000, 14, 1002)
    local vampire = mob("Vampire", Vector3.new(1050, 5, 1000))
    LevelFarm.tick()
    eq("screen objective: no StartQuest", #calls(world.commF, "StartQuest"), 0)
    eq("screen objective: fights the vampire", LevelFarm.target, vampire)
end

---------------------------------------------------------------------------
-- Enemies
---------------------------------------------------------------------------

setup()
do
    eq("strip level suffix", Enemies.stripLevel("Zombie [Lv. 950]"), "Zombie")
    eq("strip two-word name", Enemies.stripLevel("Desert Bandit [Lv. 60]"), "Desert Bandit")
    eq("no suffix unchanged", Enemies.stripLevel("Zombie"), "Zombie")

    local close = mob("Zombie", Vector3.new(10, 0, 0))
    mob("Zombie", Vector3.new(50, 0, 0))
    mob("Zombie", Vector3.new(5, 0, 0), 0)
    mob("Vampire", Vector3.new(1, 0, 0))
    eq("nearest alive mob of that name", Enemies.nearest("Zombie"), close)
    eq("all alive of that name", #Enemies.all("Zombie"), 2)
    eq("list of names", #Enemies.all({ "Zombie", "Vampire" }), 3)

    local spawns = folder("EnemySpawns", folder("_WorldOrigin", workspace))
    local a = part("Zombie [Lv. 950]", Vector3.new(100, 0, 0), spawns)
    part("Zombie [Lv. 950]", Vector3.new(300, 0, 0), spawns)
    part("Vampire [Lv. 975]", Vector3.new(0, 0, 0), spawns)
    eq("spawn points by stripped name", #Enemies.spawnPoints("Zombie"), 2)
    eq("nearest spawn", Enemies.nearestSpawn("Zombie", Vector3.new(90, 0, 0)), a)

    local scans = 0
    getnilinstances = function() scans = scans + 1; return {} end
    Enemies.spawnPoints("Ghost")
    Enemies.spawnPoints("Ghost")
    eq("a missing spawn is not rescanned every frame", scans, 1)
    local hidden = part("Ghost [Lv. 1]", Vector3.new(0, 0, 0), nil)
    getnilinstances = function() scans = scans + 1; return { hidden } end
    Enemies.MISS_RETRY = 0
    eq("nil-parented spawn parts are found", Enemies.spawnPoints("Ghost")[1], hidden)
    Enemies.MISS_RETRY = 5
    getnilinstances = nil
end

---------------------------------------------------------------------------
-- Combat
---------------------------------------------------------------------------

setup({ position = Vector3.new(0, 20, 0) })
do
    local a = mob("Zombie", Vector3.new(0, 0, 0))
    local b = mob("Zombie", Vector3.new(0, 0, 10))
    mob("Zombie", Vector3.new(200, 0, 0))
    local shielded = mob("Zombie", Vector3.new(5, 0, 0))
    shielded.Invulnerable = true

    local hits = Combat.gatherHits(30)
    eq("one hit per vulnerable rig in range", hits and #hits, 2)
    local rigs = {}
    for _, hit in ipairs(hits or {}) do
        rigs[hit[1]] = true
        check("hit part is a limb", Combat.LIMBS[hit[2].Name], hit[2].Name)
    end
    check("both close rigs hit", rigs[a] and rigs[b])
    check("invulnerable rig skipped", not rigs[shielded])

    check("attack sent", Combat.attack(30))
    local swing = world.registerAttack.Fired[1]
    eq("RegisterAttack argument", swing and swing[1], 0)
    local hit = world.moduleRegisterHit.Fired[1]
    check("RegisterHit first argument is a part", hit and hit[1].ClassName == "Part")
    eq("RegisterHit carries the other targets", hit and #hit[2], 1)
    eq("child RegisterHit untouched", world.childRegisterHit.Fired, nil)

    world.stun.Value = 1
    check("no attack while stunned", not Combat.attack(30))
    world.stun.Value = 0

    local far = mob("Zombie", Vector3.new(0, 0, 500))
    check("no strike on a far target", not Combat.strike(far))

    local fruit = newInstance("Tool", "Flame-Flame", world.character)
    fruit.ToolTip = "Blox Fruit"
    local leftClick = newInstance("RemoteEvent", "LeftClickRemote", fruit)
    for _ = 1, 6 do Combat.fruitClick(Vector3.new(0, 0, 0)) end
    eq("fruit M1 combo wraps after 5", leftClick.Fired[6][2], 1)
    eq("fruit M1 combo counts up", leftClick.Fired[5][2], 5)
end

---------------------------------------------------------------------------
-- Bring
---------------------------------------------------------------------------

setup({ position = Vector3.new(7, 20, 0) })
do
    Bring.INTERVAL = 0
    local spawns = folder("EnemySpawns", folder("_WorldOrigin", workspace))
    part("Zombie [Lv. 950]", Vector3.new(10, 0, 0), spawns)

    local target = mob("Zombie", Vector3.new(0, 0, 0))
    local m50 = mob("Zombie", Vector3.new(50, 0, 0))
    local m100 = mob("Zombie", Vector3.new(100, 0, 0))
    local m300 = mob("Zombie", Vector3.new(300, 0, 0))

    local anchor = Vector3.new(10, 0, 0)
    eq("select respects the count", #Bring.select(target, anchor, 2), 2)
    eq("larger count widens the radius", #Bring.select(target, anchor, 5), 4)

    local other = newInstance("Model", "Other", world.characters)
    part("HumanoidRootPart", Vector3.new(600, 0, 0), other)
    local picked = Bring.select(target, anchor, 5)
    eq("mob near another player is skipped", #picked, 3)

    Bring.run(target, 3)
    near("target pulled onto the anchor", target.HumanoidRootPart.Position, anchor, 3)
    near("pack pulled onto the anchor", m50.HumanoidRootPart.Position, anchor, 3)
    near("mob near another player left alone", m300.HumanoidRootPart.Position, Vector3.new(300, 0, 0))
    check("pulled mobs lose collision", not m100.HumanoidRootPart.CanCollide)

    -- Health moved on the target only: the others are not ours.
    target.Humanoid.Health = 50
    stepTasks()
    check("damaged mob kept", not Bring.isIgnored(target))
    check("untouched mob ignored", Bring.isIgnored(m50))
    near("ignored mob sent back to its pivot", m50.HumanoidRootPart.Position, Vector3.new(50, 0, 0))

    Bring.reset()
    world.hrp.Position = Vector3.new(0, 200, 0)
    local lonely = mob("Vampire", Vector3.new(0, 0, 0))
    mob("Vampire", Vector3.new(20, 0, 0))
    Bring.run(lonely, 3)
    near("no pull when standing far from the target", lonely.HumanoidRootPart.Position, Vector3.new(0, 0, 0))
end

---------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------

setup()
do
    Settings.set("SmartTravel", false)
    local dt = 1 / 60
    Movement.to(CFrame.new(100, 0, 0))
    Movement.step(dt)
    near("one step at TweenSpeed", world.hrp.Position, Vector3.new(5, 0, 0))
    check("float force added", world.hrp:FindFirstChild("FloatForce") ~= nil)

    -- The server pulls the character back: the cap drops to 70 %.
    world.hrp.Position = Vector3.new(-50, 0, 0)
    Movement.step(dt)
    near("slower after a pull-back", world.hrp.Position, Vector3.new(-50 + 3.5, 0, 0))

    world.hrp.Position = Vector3.new(99, 0, 0)
    Movement.step(dt)
    near("snaps onto a close goal", world.hrp.Position, Vector3.new(100, 0, 0))

    Movement.step(1)
    near("a huge dt is capped per frame", world.hrp.Position, Vector3.new(100, 0, 0))

    Movement.stop()
    check("stop clears the goal", not Movement.moving())
    check("stop removes the float force", world.hrp:FindFirstChild("FloatForce") == nil)

    Movement.reset()
    world.hrp.Position = Vector3.new(0, 0, 0)
    Movement.to(CFrame.new(1000, 0, 0))
    Movement.step(1)
    near("step never exceeds the per-frame cap", world.hrp.Position, Vector3.new(18, 0, 0))
end

---------------------------------------------------------------------------
-- Level farm
---------------------------------------------------------------------------

setup()
do
    LevelFarm.QUEST_SETTLE = 0
    LevelFarm.stop()
    world.commF.OnInvoke = function() return true end
    local melee = newInstance("Tool", "Combat", world.player.Backpack)
    melee.ToolTip = "Melee"

    LevelFarm.tick()
    local goal = Movement.goal()
    near("flies to the quest giver", goal and goal.Position or Vector3.new(), Vector3.new(1000, 14, 1002))
    eq("weapon equipped", melee.Parent, world.character)
    eq("no StartQuest from afar", world.commF.Invoked, nil)

    world.hrp.Position = Vector3.new(1000, 14, 1002)
    LevelFarm.tick()
    local call = world.commF.Invoked and world.commF.Invoked[1]
    eq("StartQuest once there", call and call[2], "HauntedQuest1")
    eq("StartQuest with the level id", call and call[3], 1)

    world.questPanel.Visible = true
    world.guide.Data.QuestData = { Task = { Zombie = 8 } }
    LevelFarm.tick()
    goal = Movement.goal()
    near("no spawn loaded: waits above the quest giver", goal.Position, Vector3.new(1000, 70, 1000))

    local zombie = mob("Zombie", Vector3.new(1100, 5, 1000))
    LevelFarm.tick()
    goal = Movement.goal()
    near("holds above the quest mob", goal.Position, Vector3.new(1107, 25, 1000))
    eq("attack target is the quest mob", LevelFarm.target, zombie)
    check("status names the mob", LevelFarm.status:find("Zombie") ~= nil, LevelFarm.status)
    check("no weapon warning when equipped", LevelFarm.status:find("inventory") == nil, LevelFarm.status)

    Settings.set("Weapon", "Sword")
    LevelFarm.tick()
    check("missing weapon reported", LevelFarm.status:find("no Sword") ~= nil, LevelFarm.status)
    Settings.set("Weapon", "Melee")

    zombie.Parent = nil
    Enemies.reset()
    local spawns = folder("EnemySpawns", folder("_WorldOrigin", workspace))
    local spawnPoint = part("Zombie [Lv. 950]", Vector3.new(1200, 5, 1000), spawns)
    part("Zombie [Lv. 950]", Vector3.new(1400, 5, 1000), spawns)
    LevelFarm.tick()
    goal = Movement.goal()
    near("searches the spawn point", goal.Position, Vector3.new(1200, 65, 1000))
    eq("no attack target while searching", LevelFarm.target, nil)

    world.hrp.Position = Vector3.new(1200, 65, 1000)
    LevelFarm.tick()
    LevelFarm.tick()
    goal = Movement.goal()
    near("moves on to the next spawn point", goal.Position, Vector3.new(1400, 65, 1000))
    near("first spawn point left alone once visited", spawnPoint.Position, Vector3.new(1200, 5, 1000))

    world.humanoid.Health = 0
    LevelFarm.tick()
    eq("waits while dead", LevelFarm.status, "Waiting for respawn")
end

-- The in-game bug: quest taken, panel not where we looked, only the
-- GuideModule knows. The farm must go fight, not re-take the quest.
setup()
do
    LevelFarm.stop()
    world.commF.OnInvoke = function() return true end
    world.questPanel.Visible = false
    world.guide.Data.QuestData = { Task = { Vampire = 8 } }
    world.hrp.Position = Vector3.new(1000, 14, 1002)
    local vampire = mob("Vampire", Vector3.new(1050, 5, 1000))
    LevelFarm.QUEST_SETTLE = 0
    LevelFarm.tick()
    eq("no StartQuest while a quest is held", #calls(world.commF, "StartQuest"), 0)
    eq("goes to fight the quest mob", LevelFarm.target, vampire)
    near("holds above the vampire", Movement.goal().Position, Vector3.new(1057, 25, 1000))
end

setup()
do
    Settings.set("AutoFarmLevel", true)
    Farm.tick()
    eq("level farm becomes the active mode", Farm.current(), LevelFarm)
    check("farm has a goal", Movement.moving())
    Settings.set("AutoFarmLevel", false)
    Farm.tick()
    eq("no active mode when disabled", Farm.current(), nil)
    check("character handed back", not Movement.moving())
    eq("idle status", Farm.status(), "Idle")
end

---------------------------------------------------------------------------
-- Farm modes
---------------------------------------------------------------------------

local function resetModes()
    for _, mode in ipairs(Farm.MODES) do mode.stop() end
end

-- Priority: Boss beats Aura beats Level.
setup()
do
    resetModes()
    Settings.set("AutoFarmLevel", true)
    Settings.set("AutoAura", true)
    Farm.tick()
    eq("aura outranks level", Farm.current(), AuraFarm)
    Settings.set("AutoBoss", true)
    Farm.tick()
    eq("boss outranks aura", Farm.current(), BossFarm)
    Farm.stop()
end

-- Boss farm
setup()
do
    resetModes()
    Settings.set("AutoBoss", true)
    BossFarm.tick()
    eq("boss farm asks for a boss", BossFarm.status, "Choose a boss")

    Settings.set("Boss", "Cyborg")
    BossFarm.tick()
    check("boss not spawned", BossFarm.status:find("Not spawned") ~= nil, BossFarm.status)

    local parked = mob("Cyborg", Vector3.new(500, 0, 0), 100, rs)
    BossFarm.tick()
    near("flies to a boss parked in ReplicatedStorage", Movement.goal().Position, Vector3.new(500, 60, 0))
    eq("no attack on a parked boss", BossFarm.target, nil)

    parked.Parent = workspace.Enemies
    BossFarm.tick()
    eq("fights the boss once in the world", BossFarm.target, parked)

    parked.Parent = nil
    Settings.set("AllBosses", true)
    local any = mob("Stone", Vector3.new(0, 0, 50))
    BossFarm.tick()
    eq("any boss", BossFarm.target, any)
end

-- Katakuri: Sea 3 only, boss first unless ignored.
setup()
do
    resetModes()
    KatakuriFarm.tick()
    eq("katakuri needs sea 3", KatakuriFarm.status, "Only in Sea 3")
    game.PlaceId = 7449423635
    local cake = mob("Cake Guard", Vector3.new(30, 0, 0))
    local prince = mob("Cake Prince", Vector3.new(90, 0, 0))
    KatakuriFarm.tick()
    eq("cake prince first", KatakuriFarm.target, prince)
    Settings.set("IgnoreKatakuri", true)
    KatakuriFarm.tick()
    eq("ignored prince: cake mobs", KatakuriFarm.target, cake)
end

-- Bones: Sea 3 mobs, spawn tour when none alive.
setup()
do
    resetModes()
    game.PlaceId = 7449423635
    local spawns = folder("EnemySpawns", folder("_WorldOrigin", workspace))
    part("Reborn Skeleton [Lv. 1975]", Vector3.new(300, 0, 0), spawns)
    BoneFarm.tick()
    near("bone farm tours the spawn points", Movement.goal().Position, Vector3.new(300, 60, 0))
    local skeleton = mob("Reborn Skeleton", Vector3.new(310, 0, 0))
    BoneFarm.tick()
    eq("bone farm fights a bone mob", BoneFarm.target, skeleton)
end

-- Material: wrong sea travels, right sea farms.
setup()
do
    resetModes()
    world.commF.OnInvoke = function() return true end
    MaterialFarm.tick()
    eq("material asks for a choice", MaterialFarm.status, "Choose a material")
    Settings.set("Material", "Leather")
    MaterialFarm.tick()
    eq("wrong sea: travel action", world.commF.Invoked and world.commF.Invoked[1][1], "TravelZou")
    MaterialFarm.tick()
    eq("travel not spammed", #world.commF.Invoked, 1)
    Settings.set("Material", "Vampire Fang")
    local vampire = mob("Vampire", Vector3.new(20, 0, 0))
    MaterialFarm.tick()
    eq("right sea: farms the material's mob", MaterialFarm.target, vampire)
end

-- Kill mob and aura.
setup()
do
    resetModes()
    KillMobFarm.tick()
    eq("kill mob asks for a choice", KillMobFarm.status, "Choose a mob")
    Settings.set("Mob", "Zombie")
    local zombie = mob("Zombie", Vector3.new(40, 0, 0))
    KillMobFarm.tick()
    eq("kill mob fights the chosen mob", KillMobFarm.target, zombie)

    local spawns = folder("EnemySpawns", folder("_WorldOrigin", workspace))
    part("Vampire [Lv. 975]", Vector3.new(0, 0, 0), spawns)
    local names = Enemies.knownNames()
    check("known names from spawns and live mobs",
        table.find(names, "Vampire") ~= nil and table.find(names, "Zombie") ~= nil)

    Settings.set("AuraRadius", 30)
    AuraFarm.tick()
    check("aura: nothing in range", AuraFarm.target == nil and AuraFarm.status:find("30") ~= nil)
    Settings.set("AuraRadius", 100)
    AuraFarm.tick()
    eq("aura: nearest mob in range", AuraFarm.target, zombie)
end

---------------------------------------------------------------------------
-- Mastery and aim
---------------------------------------------------------------------------

setup()
do
    Mastery.reset()
    Mastery.HOLD = 0
    local pressed = {}
    local vim = game:GetService("VirtualInputManager")
    function vim:SendKeyEvent(down, key) if down then pressed[#pressed + 1] = key end end

    local melee = newInstance("Tool", "Combat", world.player.Backpack)
    melee.ToolTip = "Melee"
    local fruit = newInstance("Tool", "Flame-Flame", world.player.Backpack)
    fruit.ToolTip = "Blox Fruit"

    local skills = newInstance("Frame", "Skills", world.player.PlayerGui.Main)
    local bar = newInstance("Frame", "Flame-Flame", skills)
    local function skill(key, readyNow)
        local frame = newInstance("Frame", key, bar)
        local title = newInstance("TextLabel", "Title", frame)
        title.TextColor3 = Color3.new(1, 1, 1)
        local cooldown = newInstance("Frame", "Cooldown", frame)
        cooldown.Size = readyNow and UDim2.new(0, 0, 1, -1) or UDim2.new(0.5, 0, 1, -1)
    end
    skill("Z", false)
    skill("X", true)

    local target = mob("Zombie", Vector3.new(0, 0, 0))
    target.Humanoid.MaxHealth = 100

    local Fight = require("Features.Fight")
    Settings.set("MasteryFarm", true)
    local mode = {}
    Fight.engage(mode, target)
    eq("healthy mob: normal weapon", melee.Parent, world.character)
    eq("no aim while healthy", AimHook.target, nil)

    target.Humanoid.Health = 30
    Fight.engage(mode, target)
    eq("low mob: mastery weapon", fruit.Parent, world.character)
    eq("first ready selected skill pressed", pressed[1], "X")
    check("skills aimed at the mob", AimHook.target ~= nil)

    Settings.set("MasterySkills", { Z = true })
    eq("unselected skill ignored", Mastery.readySkill(fruit), nil)

    Settings.set("MasteryFarm", false)
    Fight.engage(mode, target)
    eq("mastery off: back to the normal weapon", AimHook.target, nil)

    -- The aim rewrite itself.
    local remote = newInstance("RemoteEvent", "RemoteEvent")
    AimHook.target = CFrame.new(1, 2, 3)
    AimHook.enabled = true
    local swapped = AimHook.rewrite(remote, "FireServer", Vector3.new(9, 9, 9))
    near("Vector3 aim replaced", swapped, Vector3.new(1, 2, 3))
    local cf = AimHook.rewrite(remote, "FireServer", CFrame.new(9, 9, 9))
    near("CFrame aim replaced", cf.Position, Vector3.new(1, 2, 3))
    local a, b = AimHook.rewrite(remote, "FireServer", 1, 2)
    check("multi-argument calls untouched", a == 1 and b == 2)
    local other = newInstance("RemoteEvent", "RE/RegisterHit")
    near("other remotes untouched", AimHook.rewrite(other, "FireServer", Vector3.new(9, 9, 9)), Vector3.new(9, 9, 9))
    AimHook.disable()
    near("disabled hook passes through", AimHook.rewrite(remote, "FireServer", Vector3.new(9, 9, 9)), Vector3.new(9, 9, 9))
    AimHook.enabled = true
end

---------------------------------------------------------------------------
-- Travel, world, stats, server
---------------------------------------------------------------------------

setup()
do
    resetModes()
    Travel.cancel()
    Settings.set("AutoFarmLevel", true)
    Farm.tick()
    eq("level farm running", Farm.current(), LevelFarm)

    local arrived = 0
    Travel.go("Somewhere", Vector3.new(100, 0, 0), function() arrived = arrived + 1 end)
    Farm.tick()
    eq("travel pauses the farm", Farm.current(), Travel)
    near("travel flies to the place", Movement.goal().Position, Vector3.new(100, 4, 2))
    check("travel status shows the distance", Travel.status:find("Somewhere") ~= nil, Travel.status)

    world.hrp.Position = Vector3.new(100, 4, 2)
    Farm.tick()
    eq("arrival runs the callback", arrived, 1)
    Farm.tick()
    eq("farm resumes after arrival", Farm.current(), LevelFarm)
    eq("callback runs once", arrived, 1)

    Travel.go("Nowhere", function() return nil end)
    Travel.tick()
    check("unloaded destination cancels", Travel.pending() == nil and Travel.status:find("not loaded") ~= nil)
    Farm.stop()
end

setup()
do
    local locations = folder("Locations", folder("_WorldOrigin", workspace))
    part("Kingdom of Rose", Vector3.new(5, 6, 7), locations)
    local islands = World.islands()
    near("live location marker", islands["Kingdom of Rose"], Vector3.new(5, 6, 7))
    check("known islands of this sea", islands["Cafe"] ~= nil and islands["Port Town"] == nil)
    check("island names sorted", World.islandNames()[1] <= World.islandNames()[2])

    local npcs = folder("NPCs", workspace)
    local stored = folder("NPCs", rs)
    local near1 = newInstance("Model", "Ancient Monk", npcs)
    part("HumanoidRootPart", Vector3.new(10, 0, 0), near1)
    local far1 = newInstance("Model", "Ancient Monk", stored)
    part("HumanoidRootPart", Vector3.new(900, 0, 0), far1)
    newInstance("Model", "Boat Dealer", npcs)
    near("nearest NPC of that name", World.npcPosition("Ancient Monk"), Vector3.new(10, 0, 0))
    local names = World.npcNames()
    check("NPC names without boats", table.find(names, "Ancient Monk") ~= nil and table.find(names, "Boat Dealer") == nil)
    eq("NPC names unique", #names, 1)

    local lighting = game:GetService("Lighting")
    local sky = newInstance("Sky", "FantasySky", lighting)
    sky.MoonTextureId = Data.MOON_FULL
    eq("full moon", World.moon(), "Full Moon")
    sky.MoonTextureId = Data.MOON_NEXT
    eq("full moon next night", World.moon(), "Next Night")
    lighting.ClockTime = 18.5
    eq("game clock", World.clock(), "18:30")

    eq("no elite hunter", World.eliteHunter(), nil)
    mob("Urban", Vector3.new(0, 0, 0))
    eq("elite hunter alive", World.eliteHunter(), "Urban")
end

do
    local plan = Stats.plan(10, { Melee = 0, Defense = 0 }, { Melee = true, Defense = true })
    eq("points split in two", plan[1].points + plan[2].points, 10)
    eq("even split", plan[1].points, 5)
    local capped = Stats.plan(100, { Melee = 2795, Defense = 0 }, { Melee = true, Defense = true })
    eq("capped stat gets only what fits", capped[1].points, 5)
    local maxed = Stats.plan(10, { Melee = 2800, Defense = 0 }, { Melee = true, Defense = true })
    eq("maxed stat skipped", #maxed, 1)
    eq("remaining stat gets everything", maxed[1].points, 10)
    eq("no points, no plan", #Stats.plan(0, {}, { Melee = true }), 0)
    local odd = Stats.plan(3, {}, { Melee = true, Sword = true })
    eq("odd points: first stat gets the extra", odd[1].points, 2)
end

setup()
do
    Server.reset()
    Settings.set("AutoStats", true)
    Settings.set("StatTargets", { Sword = true })
    local points = newInstance("IntValue", "Points", world.player.Data)
    points.Value = 6
    world.commF.OnInvoke = function() return true end
    Stats.tick()
    local call = world.commF.Invoked and world.commF.Invoked[1]
    eq("AddPoint action", call and call[1], "AddPoint")
    eq("AddPoint stat", call and call[2], "Sword")
    eq("AddPoint amount", call and call[3], 6)

    local browser = newInstance("RemoteFunction", "__ServerBrowser", rs)
    browser.OnInvoke = function() return true end
    local pages = {
        { data = {
            { id = game.JobId, playing = 3, maxPlayers = 12 },
            { id = "job-full", playing = 12, maxPlayers = 12 },
            { id = "job-a", playing = 8, maxPlayers = 12 },
        } },
    }
    local fetched = {}
    game.HttpGet = function(_, url)
        fetched[#fetched + 1] = url
        return pages[1]
    end
    local http = game:GetService("HttpService")
    function http:JSONDecode(value) return value end

    local queued
    queue_on_teleport = function(code) queued = code end
    check("hop sends a teleport", Server.hop())
    check("server list read from the public API", fetched[1] and fetched[1]:find("games.roblox.com", 1, true) ~= nil)
    local last = browser.Invoked[#browser.Invoked]
    eq("hop teleports through the game server", last[1], "teleport")
    eq("hop skips current and full servers", last[2], "job-a")
    check("loader queued for the next server", queued and queued:find("StrawberryHub.lua", 1, true) ~= nil)
    check("tried server remembered", Server.isVisited("job-a"))
    check("no server left to try", not Server.hop())

    pages[1].data[#pages[1].data + 1] = { id = "job-low", playing = 2, maxPlayers = 12 }
    pages[1].data[#pages[1].data + 1] = { id = "job-busy", playing = 9, maxPlayers = 12 }
    eq("low player pick", Server.pickLow(), "job-low")

    local teleportService = game:GetService("TeleportService")
    local clientTeleports = 0
    function teleportService:TeleportToPlaceInstance() clientTeleports = clientTeleports + 1 end
    function teleportService:Teleport() clientTeleports = clientTeleports + 1 end
    check("rejoin sent", Server.rejoin())
    last = browser.Invoked[#browser.Invoked]
    check("rejoin goes through the game server", last[1] == "teleport" and last[2] == game.JobId)
    eq("no client-side teleport (restricted place)", clientTeleports, 0)

    queued = nil
    Settings.set("AutoExecute", false)
    Server.join("job-b")
    eq("no reload queued when disabled", queued, nil)
    check("empty JobId refused", not Server.join("  "))
    queue_on_teleport = nil
    game.HttpGet = nil
end

setup()
do
    resetModes()
    Server.reset()
    local browser = newInstance("RemoteFunction", "__ServerBrowser", rs)
    browser.OnInvoke = function() return true end
    game.HttpGet = function() return { data = { { id = "job-z", playing = 1, maxPlayers = 12 } } } end
    local http = game:GetService("HttpService")
    function http:JSONDecode(value) return value end
    Settings.set("AutoBoss", true)
    Settings.set("Boss", "Cyborg")
    Settings.set("HopForBoss", true)
    local BossFarmModule = require("Features.BossFarm")
    BossFarmModule.HOP_AFTER = 0
    BossFarmModule.tick()
    local last = browser.Invoked and browser.Invoked[#browser.Invoked]
    eq("missing boss makes the farm hop", last and last[2], "job-z")
    BossFarmModule.HOP_AFTER = 15
    game.HttpGet = nil
end

---------------------------------------------------------------------------
-- Smart travel (the reference's rules)
---------------------------------------------------------------------------

local CASTLE = Vector3.new(-4967.6826171875, 314.88238525390625, -3157.098388671875)
local SEA3 = 7449423635

-- A far goal near an unlocked portal: requestEntrance to its point.
setup()
do
    game.PlaceId = SEA3
    Entrances.reset({ DefeatedIndraTrueForm = true })
    local goal = CASTLE + Vector3.new(500, 0, 500)
    local plan = Router.plan(Vector3.new(0, 0, 0), goal)
    eq("far goal: entrance", plan.kind, "entrance")
    eq("the portal nearest the goal", plan.name, "Castle on the Sea")

    Entrances.reset({})
    local locked = Router.plan(Vector3.new(0, 0, 0), goal)
    eq("portal not unlocked: fly", locked.kind, "direct")
    check("reason given", locked.reason and locked.reason:find("no portal near the goal", 1, true) ~= nil, locked.reason)

    Entrances.reset(nil)
    eq("unlocks unknown: only the open points", #Entrances.available(), 1)
    Entrances.reset({ DefeatedIndraTrueForm = true })
    eq("unlocked: every point", #Entrances.available(), 4)

    eq("goal under 3000 studs: fly", Router.plan(goal + Vector3.new(0, 0, 2000), goal).kind, "direct")
    local here = CASTLE + Vector3.new(0, 0, 500)
    local beside = Router.plan(here, CASTLE + Vector3.new(0, 0, -2600))
    eq("standing at the portal: still called, as in the reference", beside.kind, "entrance")

    Movement.reset()
    world.hrp.Position = Vector3.new(0, 0, 0)
    Movement.to(CFrame.new(100, 0, 0))
    Movement.step(1 / 60)
    near("short trip set in one go", world.hrp.Position, Vector3.new(100, 0, 0))
end

-- The entrance: calls repeated until the player moves, then "works".
setup()
do
    game.PlaceId = SEA3
    Entrances.reset({ DefeatedIndraTrueForm = true })
    local goal = CASTLE + Vector3.new(500, 0, 500)
    local tries = 0
    world.commF.OnInvoke = function(action)
        if action == "requestEntrance" then
            tries = tries + 1
            if tries == 3 then world.hrp.Position = CASTLE end
        end
        return nil
    end
    check("shortcut started", Router.update(Vector3.new(0, 0, 0), goal))
    check("holds still while busy", Router.update(Vector3.new(0, 0, 0), goal))
    check("status names the portal", (Router.note() or ""):find("Castle on the Sea", 1, true) ~= nil, Router.note())
    for _ = 1, 20 do stepTasks() end
    check("done", not Router.busy())
    eq("called again until the move", tries, 3)
    local call = calls(world.commF, "requestEntrance")[1]
    check("with the exact point", call and call[2] == CASTLE, call and tostring(call[2]))
    check("reported working", Router.describe():find("Castle on the Sea: works", 1, true) ~= nil, Router.describe())
    check("player tagged Teleporting", game:GetService("CollectionService"):HasTag(world.player, "Teleporting"))
end

-- No move: failure; two misses in a row pause the portal and the Router flies.
setup()
do
    game.PlaceId = SEA3
    Entrances.reset({ DefeatedIndraTrueForm = true })
    Router.COOLDOWN = 0
    Router.EXACT_TIME = 1
    world.commF.OnInvoke = function() return nil end
    local goal = CASTLE + Vector3.new(500, 0, 500)
    local function attempt()
        Router.update(Vector3.new(0, 0, 0), goal)
        for _ = 1, 40 do stepTasks() end
        Router.update(Vector3.new(0, 0, 0), goal)   -- the flying frame after a try
    end
    attempt()
    eq("a call every 0.1 s for the whole time", #calls(world.commF, "requestEntrance"), 10)
    check("miss explained", Router.describe():find("no move after 1 s (10 calls)", 1, true) ~= nil, Router.describe())
    eq("one miss: tried again", Router.plan(Vector3.new(0, 0, 0), goal).kind, "entrance")
    attempt()
    local paused = Router.plan(Vector3.new(0, 0, 0), goal)
    eq("two misses: fly", paused.kind, "direct")
    check("reason: paused", paused.reason and paused.reason:find("paused", 1, true) ~= nil, paused.reason)
    Router.LOCK_TIME = 0
    eq("pause ends", Router.plan(Vector3.new(0, 0, 0), goal).kind, "entrance")
    Router.LOCK_TIME = 120
    Router.COOLDOWN = 4
    Router.EXACT_TIME = 15
end

-- The Banana portal test: the reference's loop to the portal nearest an island.
setup()
do
    game.PlaceId = SEA3
    Entrances.reset({ DefeatedIndraTrueForm = true })
    world.commF.OnInvoke = function(action, point)
        if action == "requestEntrance" and point == CASTLE then world.hrp.Position = CASTLE end
    end
    local result
    local started, name = Router.bananaTest(CASTLE + Vector3.new(200, 0, 0), function(text) result = text end)
    check("test started", started)
    eq("portal nearest the island", name, "Castle on the Sea")
    check("nothing else while it runs", not Router.bananaTest(CASTLE))
    for _ = 1, 5 do stepTasks() end
    check("result reported", result and result:find("Castle on the Sea: moved", 1, true) ~= nil, result)
    local refused, why = Router.bananaTest(Vector3.new(90000, 0, 90000))
    check("no portal near: refused", not refused and why:find("no unlocked portal", 1, true) ~= nil, why)
end

-- The Temple of Time point borrows the temple map first.
setup()
do
    game.PlaceId = SEA3
    Entrances.reset({})
    local temple = newInstance("Model", "Temple of Time", folder("MapStash", rs))
    local map = folder("Map", workspace)
    local goal = Entrances.TEMPLE + Vector3.new(100, 0, 0)
    eq("far from the temple: its point", Router.plan(Vector3.new(0, 0, 0), goal).name, "Temple of Time")
    world.commF.OnInvoke = function(action)
        if action == "requestEntrance" then world.hrp.Position = Entrances.TEMPLE end
    end
    Router.update(Vector3.new(0, 0, 0), goal)
    eq("temple borrowed into the map", temple.Parent, map)
    eq("marked borrowed", temple:GetAttribute("ClientBorrowed"), true)
    for _ = 1, 10 do stepTasks() end
    eq("reached: the temple stays", temple.Parent, map)
    check("no longer marked", temple:GetAttribute("ClientBorrowed") == nil)
end

-- Seated: stand up before flying; the Teleporting tag while flying.
setup()
do
    local seat = part("Seat", Vector3.new(0, 0, 0), workspace)
    world.humanoid.SeatPart = seat
    world.humanoid.Sit = true
    TeleportTag.HOLD = 0
    Movement.to(CFrame.new(50, 0, 0))
    Movement.step(1 / 60)
    eq("stood up", world.humanoid.Sit, false)
    check("jumped", world.humanoid.Jump == true)
    near("lifted off the seat", world.hrp.Position, Vector3.new(0, 10, 0))
    world.humanoid.SeatPart = nil
    Movement.step(1 / 60)
    near("then flies", world.hrp.Position, Vector3.new(50, 0, 0))
    local collection = game:GetService("CollectionService")
    check("tagged while flying", collection:HasTag(world.player, "Teleporting"))

    -- Boarding: the goal is the seat itself, so the character stays on it.
    local boatSeat = part("VehicleSeat", Vector3.new(80, 0, 0), workspace)
    world.hrp.Position = boatSeat.Position
    world.humanoid.SeatPart = boatSeat
    world.humanoid.Sit = true
    Movement.to(boatSeat.CFrame)
    Movement.step(1 / 60)
    eq("stays seated on the goal seat", world.humanoid.Sit, true)
    near("not moved off the seat", world.hrp.Position, boatSeat.Position)
    world.humanoid.SeatPart = nil
    world.humanoid.Sit = false
    Movement.stop()
    stepTasks()
    check("tag removed after the flight", not collection:HasTag(world.player, "Teleporting"))
    TeleportTag.HOLD = 1.5
end

-- Portal fruit: the Gateway to the island nearest the goal.
setup()
do
    game.PlaceId = SEA3
    Entrances.reset({})
    Settings.set("PortalFruit", true)
    newInstance("StringValue", "DevilFruit", world.player.Data).Value = "Portal-Portal"
    local fruit = newInstance("Tool", "Portal-Portal", world.player.Backpack)
    newInstance("IntValue", "Level", fruit).Value = 250
    local skills = newInstance("Frame", "Skills", world.player.PlayerGui.Main)
    local skill = newInstance("Frame", "C", newInstance("Frame", "Portal-Portal", skills))
    newInstance("TextLabel", "Title", skill).TextColor3 = Color3.new(1, 1, 1)
    newInstance("Frame", "Cooldown", skill).Size = UDim2.new(0, 0, 1, -1)
    local gateway = newInstance("Frame", "Gateway", world.player.PlayerGui.Main)
    gateway.Visible = false
    local list = newInstance("ScrollingFrame", "ScrollingFrame", newInstance("Frame", "MainContent", gateway))
    newInstance("TextButton", "Hydra Town", list).MouseButton1Click = "hydra click"
    local clicked
    getconnections = function(signal) return { { Function = function() clicked = signal end } } end
    local keys = {}
    game:GetService("VirtualInputManager").SendKeyEvent = function(_, down, key)
        if down then
            keys[#keys + 1] = key
            gateway.Visible = true
        end
    end
    local goal = Gateway.ISLANDS[3]["Hydra Town"] + Vector3.new(50, 0, 0)
    local plan = Router.plan(Vector3.new(0, 0, 0), goal)
    eq("portal fruit first", plan.kind, "gateway")
    eq("island nearest the goal", plan.island and plan.island.name, "Hydra Town")
    check("gateway started", Router.update(Vector3.new(0, 0, 0), goal))
    for _ = 1, 3 do stepTasks() end
    eq("C pressed", keys[1], "C")
    eq("island button clicked", clicked, "hydra click")
    getconnections = nil
    game:GetService("VirtualInputManager").SendKeyEvent = nil
end

-- Celestial Domain: through its NPC.
setup()
do
    game.PlaceId = SEA3
    Entrances.reset({})
    local locations = folder("Locations", folder("_WorldOrigin", workspace))
    local domain = part("Celestial Domain", Vector3.new(20000, 5000, 0), locations)
    newInstance("SpecialMesh", "Mesh", domain).Scale = Vector3.new(2000, 1, 1)
    part("Port Town", Vector3.new(0, 0, 0), locations)
    local member = newInstance("Model", "Celestial", folder("NPCs", workspace))
    member:SetAttribute("NPCLoaded", true)
    member:SetAttribute("NPCReady", true)
    member:SetAttribute("DisplayName", "Celestial Member")
    part("HumanoidRootPart", Vector3.new(100, 0, 0), member)
    local goal = domain.Position + Vector3.new(10, 0, 0)
    local plan = Router.plan(Vector3.new(0, 0, 0), goal)
    eq("into the Domain: its transport", plan.kind, "celestial")
    near("by its NPC", plan.dock, Vector3.new(100, 0, 20))
    local transport = newInstance("RemoteFunction", "RF/CelestialDomainTransportation", rs.Modules.Net)
    check("near the NPC: transport taken", Router.update(Vector3.new(0, 0, 0), goal))
    eq("to the temple", transport.Invoked and transport.Invoked[1][1], "InitiateTeleportToTemple")
end

-- The Cake Loaf mirror leads to the place in the sky behind it.
setup()
do
    game.PlaceId = SEA3
    Entrances.reset({})
    local mirror = part("Main", Vector3.new(-2000, 100, -12000),
        folder("BigMirror", folder("CakeLoaf", folder("Map", workspace))))
    local plan = Router.plan(Vector3.new(-1800, 60, -11900), Router.MIRROR_INSIDE + Vector3.new(10, 0, 0))
    eq("behind the mirror: through it", plan.kind, "mirror")
    near("flies onto the mirror", plan.dock, mirror.Position)
end

-- Reset teleport: the spawn point moves to the goal's island, then a reset.
setup()
do
    game.PlaceId = SEA3
    Entrances.reset({})
    local origin = folder("_WorldOrigin", workspace)
    local locations = folder("Locations", origin)
    part("Far Island", Vector3.new(20000, 0, 0), locations).Size = Vector3.new(2000, 10, 2000)
    part("Home", Vector3.new(0, 0, 0), locations).Size = Vector3.new(2000, 10, 2000)
    local group = folder("Pirates", folder("PlayerSpawns", origin))
    newInstance("Model", "FarSpawn", group).WorldPivot = CFrame.new(20100, 0, 0)
    newInstance("Model", "HomeSpawn", group).WorldPivot = CFrame.new(50, 0, 0)
    local goal = Vector3.new(20200, 0, 0)
    eq("off by default", Router.plan(Vector3.new(0, 0, 0), goal).kind, "direct")
    Settings.set("RespawnShortcut", true)
    local plan = Router.plan(Vector3.new(0, 0, 0), goal)
    eq("reset teleport when on", plan.kind, "respawn")
    eq("the spawn of the goal's island", plan.spawn and plan.spawn.name, "FarSpawn")
    eq("same island: fly", Router.plan(Vector3.new(19000, 0, 0), goal).kind, "direct")

    local script = newInstance("LocalScript", "LastSpawnPoint", world.character)
    local offDuring
    world.commF.OnInvoke = function(action, name)
        if action == "SetLastSpawnPoint" then
            offDuring = script.Disabled
            newInstance("StringValue", "LastSpawnPoint", world.player.Data).Value = name
        end
    end
    check("respawn started", Router.update(Vector3.new(0, 0, 0), goal))
    check("spawn script off during the change", offDuring == true)
    eq("spawn point moved", calls(world.commF, "SetLastSpawnPoint")[1][2], "FarSpawn")
    eq("character reset", world.humanoid.Health, 0)
end

-- Every island kept loaded, like the reference.
setup()
do
    workspace.CurrentCamera = newInstance("Camera", "Camera")
    newInstance("Model", "Jungle", folder("Map", workspace)).WorldPivot = CFrame.new(10, 0, 0)
    local far = newInstance("Model", "Far", workspace)
    far:SetAttribute("LevelOfDetailDiameter", 500)
    far.WorldPivot = CFrame.new(99, 0, 0)
    newInstance("Model", "Fake", folder("FakeIslands", rs)).WorldPivot = CFrame.new(5, 5, 5)
    eq("a point per island", IslandLoader.load(), 3)
    local point = workspace.CurrentCamera:GetChildren()[1]
    check("tagged for the level of detail", game:GetService("CollectionService"):HasTag(point, "LoDPosition"))
    IslandLoader.start()
    Settings.set("LoadIslands", false)
    eq("turned off: points removed", IslandLoader.count(), 0)
    eq("camera cleaned", #workspace.CurrentCamera:GetChildren(), 0)
    Settings.set("LoadIslands", true)
    eq("turned on: points back", IslandLoader.count(), 3)
    IslandLoader.destroy()
    eq("destroy removes them", IslandLoader.count(), 0)
    workspace.CurrentCamera = nil
end

-- Sea 3 submarine, both ways.
setup()
do
    game.PlaceId = SEA3
    Entrances.reset({})
    local island = Router.ISLAND + Vector3.new(100, 0, 0)
    local handled, aim = Router.update(Vector3.new(0, 0, 0), island)
    check("submarine: fly to the worker first", not handled and aim ~= nil and (aim - Router.WORKER).Magnitude < 1)
    local worker = newInstance("RemoteFunction", "RF/SubmarineWorkerSpeak", rs.Modules.Net)
    check("at the worker: submarine taken", Router.update(Router.WORKER, island))
    eq("worker asked to travel", worker.Invoked and worker.Invoked[1][1], "TravelToSubmergedIsland")
    stepTasks()

    Router.reset()
    local plan = Router.plan(Router.ISLAND, Vector3.new(0, 0, 0))
    eq("leaving the island: submarine", plan.kind, "submarine")
    near("leaves from the dock", plan.dock, Router.DOCK)
end

-- The server only answers the exact positions: every point must match the
-- reference literal digit for digit.
do
    local expected = {
        [1] = { { -7894.6201171875, 5545.49169921875, -380.2467346191406 },
                { -4607.82275390625, 872.5422973632812, -1667.556884765625 },
                { 61163.8515625, 11.759522438049316, 1819.7841796875 },
                { 3876.280517578125, 35.10614013671875, -1939.3201904296875 } },
        [2] = { { 923.21252441406, 126.9760055542, 32852.83203125 },
                { -6508.5581054688, 89.034996032715, -132.83953857422 },
                { -288.46246337890625, 306.130615234375, 597.9988403320312 },
                { 2284.912109375, 15.152046203613281, 905.48291015625 } },
        [3] = { { 28282.5703125, 14896.8505859375, 105.1042709350586 },
                { -4967.6826171875, 314.88238525390625, -3157.098388671875 },
                { 5661.5302734375, 1013.4113159179688, -334.9619140625 },
                { -12463.8740234375, 374.9144592285156, -7523.77392578125 } },
    }
    for sea, list in pairs(expected) do
        for index, xyz in ipairs(list) do
            local point = Entrances.POINTS[sea][index]
            check("exact coordinates: " .. point.name,
                point.position == Vector3.new(xyz[1], xyz[2], xyz[3]), tostring(point.position))
        end
    end
end

-- Test portals: a portal next to the player is not requested.
setup()
do
    game.PlaceId = SEA3
    Entrances.reset({ DefeatedIndraTrueForm = true })
    world.hrp.Position = CASTLE + Vector3.new(100, 0, 0)
    world.commF.OnInvoke = function() return nil end
    Router.EXACT_TIME = 0.5
    Router.testAll()
    for _ = 1, 60 do stepTasks() end
    Router.EXACT_TIME = 15
    local text = Router.describe()
    check("portal next to the player reported too close",
        text:find("Castle on the Sea: untested (too close", 1, true) ~= nil, text)
    for _, call in ipairs(calls(world.commF, "requestEntrance")) do
        check("too-close portal not requested", call[2] ~= CASTLE)
    end
    check("no false 'works' without moving", text:find("works", 1, true) == nil, text)
end

-- Test portals: each unlocked point tried, each result recorded.
setup()
do
    game.PlaceId = 4442272183
    Entrances.reset({})
    local cursed = Entrances.POINTS[2][1].position
    world.commF.OnInvoke = function(action, point)
        if action == "requestEntrance" and point == cursed then world.hrp.Position = cursed end
        return nil
    end
    local done = false
    Router.EXACT_TIME = 0.5
    check("test started", Router.testAll(function() done = true end))
    check("second test refused while running", not Router.testAll())
    for _ = 1, 40 do stepTasks() end
    check("test finished", done)
    local text = Router.describe()
    check("working portal reported", text:find("Cursed Ship: works", 1, true) ~= nil, text)
    check("failed portal reported", text:find("no move after", 1, true) ~= nil, text)
    check("locked portal shown", text:find("Doflamingo Mansion: not unlocked", 1, true) ~= nil, text)
    Router.EXACT_TIME = 15
end

-- Leaving the Temple of Time uses the game's way back.
setup()
do
    game.PlaceId = SEA3
    Entrances.reset({})
    world.commF.OnInvoke = function() return true end
    local handled, aim = Router.update(Router.TEMPLE + Vector3.new(500, 0, 0), Vector3.new(0, 0, 0))
    check("temple exit: fly to the exit point first", not handled and aim ~= nil and (aim - Router.TEMPLE).Magnitude < 1)
    Router.reset()
    check("at the exit point: teleport back", Router.update(Router.TEMPLE, Vector3.new(0, 0, 0)))
    local check1 = calls(world.commF, "RaceV4Progress")
    eq("RaceV4Progress Check then TeleportBack", check1[1] and check1[2] and (check1[1][2] .. "," .. check1[2][2]), "Check,TeleportBack")
    stepTasks()
end

-- Sea read from the game when the PlaceId is unknown.
setup()
do
    game.PlaceId = 123456789
    Player.resetSea()
    workspace:SetAttribute("MAP", "Sea3")
    eq("sea from the MAP attribute", Player.sea(), 3)
    workspace:SetAttribute("MAP", nil)
    local util = folder("Util", rs)
    moduleScript("Realm", util, { safeGetCurrentSeaAsync = function() return "Sea2" end })
    Player.resetSea()
    Player.sea()
    eq("sea from the Realm module", Player.sea(), 2)
    Player.resetSea()
    local unknown = Router.plan(Vector3.new(0, 0, 0), Vector3.new(9000, 0, 0))
    check("no sea: fly", unknown.kind == "direct")
end

-- One hook for every feature: an observer and the aim rewriter together.
do
    Hook.reset()
    local seen = {}
    Hook.observe(function(_, method, args, fromGame) seen[#seen + 1] = { method, args[1], fromGame } end)
    AimHook.target = CFrame.new(1, 1, 1)
    AimHook.enabled = true
    Hook.rewrite(AimHook.rewrite)
    local remote = newInstance("RemoteEvent", "RemoteEvent")
    local out = Hook.dispatch(remote, "FireServer", true, Vector3.new(5, 5, 5))
    near("rewriter applied through the shared hook", out, Vector3.new(1, 1, 1))
    eq("observers wait until the call has gone", #seen, 0)
    stepTasks()
    eq("observer saw the call", seen[1] and seen[1][1], "FireServer")
    local a, b, c = Hook.dispatch(remote, "InvokeServer", false, "x", nil, "z")
    check("nil in the middle kept", a == "x" and b == nil and c == "z")
    AimHook.target = nil
    Hook.reset()
end

---------------------------------------------------------------------------
-- Stack farming
---------------------------------------------------------------------------

local StackFarm = require("Features.StackFarm")
local StackCommon = require("Features.Stack.Common")
local Chests = require("Features.Stack.Chests")
local Summons = require("Features.Stack.Summons")
local StackEvents = require("Features.Stack.Events")
local StackWorld = require("Features.Stack.World")
local ServerModule = require("Game.Server")

local function stackSetup(place, level)
    setup({ level = level })
    StackFarm.reset()
    Farm.stop()
    game.PlaceId = place or 7449423635
    world.commF.OnInvoke = function() return nil end
end

local function questTitle(text)
    local container = newInstance("Frame", "Container", world.questPanel)
    local titleFrame = newInstance("Frame", "QuestTitle", container)
    local label = newInstance("TextLabel", "Title", titleFrame)
    label.Text = text
    world.questPanel.Visible = true
    return label
end

local function tool(name, parent)
    local item = newInstance("Tool", name, parent or world.player.Backpack)
    part("Handle", Vector3.new(0, 0, 0), item)
    return item
end

-- Nothing on, or nothing to do: the stack stays out of the way.
stackSetup()
check("stack idle when nothing is on", not StackFarm.enabled())
Settings.set("StackEliteHunter", true)
check("elite toggle alone, no elite: idle", not StackFarm.enabled())

-- An elite takes the character from the level farm, quest first.
do
    Settings.set("AutoFarmLevel", true)
    local elite = mob("Diablo", Vector3.new(100, 0, 0))
    Farm.tick()
    eq("stack beats the level farm", Farm.current(), StackFarm)
    eq("quest asked: abandon", #calls(world.commF, "AbandonQuest"), 1)
    eq("quest asked: elite hunter", #calls(world.commF, "EliteHunter"), 1)
    eq("no target before the quest", Farm.target(), nil)
    check("status names the task", Farm.status():find("Stack: Elite Hunter", 1, true) ~= nil, Farm.status())

    questTitle("Defeat Diablo (0/1)")
    Farm.tick()
    eq("with the quest: fights the elite", Farm.target(), elite)
    eq("quest not asked again", #calls(world.commF, "EliteHunter"), 1)

    -- rip_indra True Form comes first in the reference's order.
    Settings.set("StackRipIndra", true)
    local indra = mob("rip_indra True Form", Vector3.new(200, 0, 0))
    Farm.tick()
    eq("rip indra beats the elite", Farm.target(), indra)

    indra.Humanoid.Health = 0
    elite.Humanoid.Health = 0
    Farm.tick()
    eq("nothing left: back to the level farm", Farm.current(), LevelFarm)
    Farm.stop()
end

-- Haki pads: the pad's colour picks the haki colour worn.
stackSetup()
do
    Settings.set("StackHakiPads", true)
    local summoner = folder("Summoner", folder("Boat Castle", folder("Map", workspace)))
    local circle = folder("Circle", summoner)
    local lit = part("PadA", Vector3.new(10, 0, 0), circle)
    lit.BrickColor = { Name = "Hot pink" }
    local litLight = part("Part", Vector3.new(10, 0, 0), lit)
    litLight.BrickColor = { Name = "Lime green" }
    local pad = part("PadB", Vector3.new(20, 0, 0), circle)
    pad.BrickColor = { Name = "Really red" }
    local light = part("Part", Vector3.new(20, 0, 0), pad)
    light.BrickColor = { Name = "Really red" }
    local customizer = newInstance("RemoteFunction", "RF/FruitCustomizerRF", rs.Modules.Net)

    eq("pending pad found", Summons.pendingPad(), pad)
    eq("red pad wants Pure Red", Summons.colourFor(pad), "Pure Red")
    check("pads to light: stack on", StackFarm.enabled())
    StackFarm.tick()
    local worn = customizer.Invoked and customizer.Invoked[1] and customizer.Invoked[1][1]
    eq("aura equipped", worn and worn.StorageName, "Pure Red")
    eq("colour activated", #calls(world.commF, "activateColor"), 1)
    check("status says pad", StackFarm.status:find("Haki pad (Pure Red)", 1, true) ~= nil, StackFarm.status)

    light.BrickColor = { Name = "Lime green" }
    check("all pads lit: stack off", not StackFarm.enabled())

    world.commF.OnInvoke = function(action)
        if action == "getColors" then
            return { { HiddenName = "Winter Sky", Unlocked = true }, { HiddenName = "Snow White", Unlocked = false } }
        end
    end
    eq("locked haki colours listed", table.concat(Summons.missingColours(), ","), "Snow White")
end

-- Chests: the window opens at the spawn time and closes after the item.
stackSetup()
do
    Settings.set("StackChests", true)
    local locations = folder("Locations", folder("_WorldOrigin", workspace))
    local location = part("Island", Vector3.new(0, 0, 0), locations)
    location:SetAttribute("TimeIn", 1000)
    local clock = Chests.now
    Chests.now = function() return 1000 + Chests.CYCLE - 60 end
    check("a minute before the spawn: nothing", not StackFarm.enabled())
    check("countdown shown", Chests.describe():find("0:01:00", 1, true) ~= nil, Chests.describe())
    Chests.now = function() return 1000 + Chests.CYCLE - 3 end

    local chest = part("Chest1", Vector3.new(30, 0, 0), workspace)
    local collection = game:GetService("CollectionService")
    collection.GetTagged = function() return { chest } end
    check("at spawn time: collecting", StackFarm.enabled())
    StackFarm.tick()
    check("heading for the chest", StackFarm.status:find("Collecting chest 1/10", 1, true) ~= nil, StackFarm.status)

    tool("God's Chalice")
    check("item obtained: done", not StackFarm.enabled())
    Chests.now = clock
end

-- A fruit on the ground is picked up; none and hop on: a paced hop.
stackSetup()
do
    Settings.set("StackFruit", true)
    local fruit = tool("Kilo Fruit", workspace)
    fruit.Handle.Position = Vector3.new(3, 0, 0)
    local touched = {}
    firetouchinterest = function(_, target, state) touched[#touched + 1] = { target, state } end
    check("fruit on the ground: stack on", StackFarm.enabled())
    StackFarm.tick()
    eq("fruit handle touched", touched[1] and touched[1][1], fruit.Handle)
    firetouchinterest = nil

    fruit.Parent = nil
    Settings.set("StackHopFruit", true)
    local hops = 0
    local realHop = ServerModule.hop
    ServerModule.hop = function() hops = hops + 1 return true end
    StackCommon.HOP_AFTER = 0
    check("no fruit: stack off", not StackFarm.enabled())
    eq("hop asked", hops, 1)
    StackFarm.enabled()
    eq("hops are paced", hops, 1)
    ServerModule.hop = realHop
    StackCommon.HOP_AFTER = 15
end

-- Pirate raid: raiders near the castle, not the excluded ones.
stackSetup()
do
    Settings.set("StackPirateRaid", true)
    local friend = mob("Friendly Pirate", StackEvents.CASTLE + Vector3.new(10, 0, 0))
    check("friends are not raiders", not StackEvents.isRaider(friend))
    local far = mob("Pirate", StackEvents.CASTLE + Vector3.new(5000, 0, 0))
    check("far pirates are not raiders", not StackEvents.isRaider(far))
    check("no raider: idle", not StackFarm.enabled())
    local raider = mob("Pirate", StackEvents.CASTLE + Vector3.new(50, 0, 0))
    check("raider: stack on", StackFarm.enabled())
    StackFarm.tick()
    eq("fights the raider", StackFarm.target, raider)
    raider.Humanoid.Health = 0
    check("waits for the next wave", StackFarm.enabled())
end

-- Server answers are cached, not asked every frame.
stackSetup(2753915549, 800)   -- Sea 1, level 800
do
    Settings.set("StackNewWorld", true)
    world.commF.OnInvoke = function(action) if action == "DressrosaQuestProgress" then return 1 end end
    for _ = 1, 10 do StackFarm.enabled() end
    eq("quest progress asked once", #calls(world.commF, "DressrosaQuestProgress"), 1)
    StackFarm.tick()
    check("no ice door loaded: waits for the admiral", StackFarm.status:find("Ice Admiral", 1, true) ~= nil, StackFarm.status)

    local door = part("Door", Vector3.new(500, 0, 0), folder("Ice", folder("Map", workspace)))
    door.CanCollide = true
    StackFarm.tick()
    check("door shut, no key: detective", StackFarm.status:find("detective", 1, true) ~= nil, StackFarm.status)
end

-- Third sea: the valuable fruit is taken out of the inventory for Trevor.
stackSetup(4442272183, 1600)   -- Sea 2
do
    Settings.set("StackThirdWorld", true)
    world.commF.OnInvoke = function(action)
        if action == "BartiloQuestProgress" then return 3 end
        if action == "TalkTrevor" then return 1 end
        if action == "GetFruits" then
            return { { Name = "Kilo-Kilo", Price = 5000 }, { Name = "Leopard-Leopard", Price = 5000000 },
                { Name = "Dough-Dough", Price = 2800000 } }
        end
        if action == "getInventory" then
            return { { Name = "Leopard-Leopard", Type = "Blox Fruit", Count = 1 },
                { Name = "Dough-Dough", Type = "Blox Fruit", Count = 1 } }
        end
    end
    check("Trevor with a stored fruit: stack on", StackFarm.enabled())
    StackFarm.tick()
    local loaded = calls(world.commF, "LoadFruit")
    eq("cheapest valuable fruit loaded", loaded[1] and loaded[1][2], "Dough-Dough")

    tool("Dough Fruit")
    world.hrp.Position = StackWorld.TREVOR
    StackCommon.forget()
    StackFarm.tick()
    eq("Trevor talked to", #calls(world.commF, "TalkTrevor") >= 3, true)
end

-- Dough King summon: cocoa first, then an elite's chalice.
stackSetup()
do
    Settings.set("StackDoughKing", true)
    Settings.set("StackSummonDoughKing", true)
    local cocoa = 3
    world.commF.OnInvoke = function(action)
        if action == "SweetChaliceNpc" then return "Where are the items?" end
        if action == "getInventory" then return { { Name = "Conjured Cocoa", Type = "Material", Count = cocoa } } end
    end
    local warrior = mob("Cocoa Warrior", Vector3.new(40, 0, 0))
    check("missing cocoa: stack on", StackFarm.enabled())
    StackFarm.tick()
    eq("farms cocoa", StackFarm.target, warrior)

    cocoa = 10
    StackCommon.forget()
    check("cocoa done, no elite: idle", not StackFarm.enabled())
    local elite = mob("Urban", Vector3.new(60, 0, 0))
    check("elite for the chalice: stack on", StackFarm.enabled())
    StackFarm.tick()
    check("status says chalice", StackFarm.status:find("God's Chalice", 1, true) ~= nil, StackFarm.status)
end

---------------------------------------------------------------------------
-- Farming Other
---------------------------------------------------------------------------

local Simple = require("Features.Other.Simple")
local ObservationModes = require("Features.Other.Observation")
local Dragon = require("Features.Other.Dragon")
local Fishing = require("Features.Other.Fishing")
local Esp = require("Features.Esp")
local Pvp = require("Features.Pvp")
local Screen = require("Features.Screen")
local Webhook = require("Features.Webhook")

local function otherSetup(place, level)
    stackSetup(place, level)
    Simple.reset()
    Dragon.reset()
    Fishing.reset()
    Webhook.reset()
end

-- Auto Chest: hops after the chosen number of chests.
otherSetup()
do
    Settings.set("OtherChest", true)
    Settings.set("OtherChestHop", true)
    Settings.set("OtherChestHopAfter", 1)
    local chest = part("Chest", Vector3.new(20, 0, 0), workspace)
    game:GetService("CollectionService").GetTagged = function() return { chest } end
    local hops = 0
    local realHop = ServerModule.hop
    ServerModule.hop = function() hops = hops + 1 return true end
    Simple.chest.tick()
    check("heading for the chest", Simple.chest.status:find("Collecting chests", 1, true) ~= nil, Simple.chest.status)
    Simple.chest.tick()
    eq("hop after one chest", hops, 1)
    eq("chest count restarts after the hop", Simple.chestHunt.collected, 0)
    ServerModule.hop = realHop
end

-- Berries: the berry's prompt is fired once there.
otherSetup()
do
    Settings.set("OtherBerry", true)
    local bushModel = newInstance("Model", "Bush", workspace)
    local bush = part("BerryBush", Vector3.new(4, 0, 0), bushModel)
    bush:SetAttribute("Berry1", "Blue Berry")
    local berry = part("Berry", Vector3.new(3, 0, 0), bush)
    local prompt = newInstance("ProximityPrompt", "ProximityPrompt", berry)
    game:GetService("CollectionService").GetTagged = function(_, tag)
        if tag == "BerryBush" then return { bush } end
        return {}
    end
    local fired
    fireproximityprompt = function(target) fired = target end
    check("a berry: berries mode on", Simple.berry.enabled())
    Simple.berry.tick()
    eq("berry prompt fired", fired, prompt)
    bush:SetAttribute("Berry1", nil)
    check("no berry: mode off", not Simple.berry.enabled())
    fireproximityprompt = nil
end

-- Raid Law: buy a chip with fragments, then press the summon button.
otherSetup(4442272183)
do
    Settings.set("OtherLaw", true)
    local fragments = newInstance("IntValue", "Fragments", world.player.Data)
    fragments.Value = 500
    check("not enough fragments: off", not Simple.law.enabled())
    fragments.Value = 1500
    check("enough fragments: on", Simple.law.enabled())
    Simple.law.tick()
    eq("microchip bought", #calls(world.commF, "BlackbeardReward"), 1)

    tool("Microchip")
    local button = folder("Main", folder("Button", folder("RaidSummon", folder("CircleIsland", folder("Map", workspace)))))
    newInstance("ClickDetector", "ClickDetector", button)
    local clicked
    fireclickdetector = function(detector) clicked = detector end
    Simple.law.tick()
    eq("summon button clicked", clicked, button.ClickDetector)
    fireclickdetector = nil
end

-- Observation: Ken is turned on next to a Marine Commodore.
otherSetup()
do
    Settings.set("OtherObservation", true)
    mob("Marine Commodore", Vector3.new(100, 0, 0))
    local blur = newInstance("BlurEffect", "Blur", game:GetService("Lighting"))
    blur.Enabled = false
    local pressed = {}
    local input = game:GetService("VirtualInputManager")
    input.SendKeyEvent = function(_, down, key) if down then pressed[#pressed + 1] = key end end
    ObservationModes.farm.tick()
    eq("E pressed for Ken", pressed[1], "E")
    blur.Enabled = true
    ObservationModes.farm.tick()
    check("Ken on: dodging", ObservationModes.farm.status:find("Dodging", 1, true) ~= nil, ObservationModes.farm.status)
end

-- Observation V2: stage 0 takes the citizen quest at the citizen.
otherSetup(7449423635)
do
    Settings.set("OtherObservationV2", true)
    world.commF.OnInvoke = function(action) if action == "CitizenQuestProgress" then return 0 end end
    check("stage 0: mode on", ObservationModes.v2.enabled())
    world.hrp.Position = ObservationModes.CITIZEN
    ObservationModes.v2.tick()
    local started = calls(world.commF, "StartQuest")
    eq("citizen quest asked", started[1] and started[1][2], "CitizenQuest")
end

-- Dojo Trainer: a White belt task, claimed once done.
otherSetup(7449423635)
do
    Settings.set("OtherDojo", true)
    local dojo = newInstance("RemoteFunction", "RF/InteractDragonQuest", rs.Modules.Net)
    local progress = 0
    dojo.OnInvoke = function(request)
        if request.Command == "RequestQuest" then
            return { Quest = { Progress = progress, Goal = 20, BeltName = "White" } }
        end
    end
    world.hrp.Position = Dragon.TRAINER
    Dragon.dojo.tick()
    check("white belt started", Dragon.describe():find("White belt", 1, true) ~= nil, Dragon.describe())
    Dragon.dojo.tick()
    check("white belt farms the level quest", Dragon.dojo.status:find("White belt 0/20", 1, true) == 1, Dragon.dojo.status)

    Dragon.reset()
    StackCommon.reset()
    progress = 20
    world.hrp.Position = Dragon.TRAINER
    Dragon.dojo.tick()
    local claimed = false
    for _, call in ipairs(dojo.Invoked or {}) do
        if call[1].Command == "ClaimQuest" then claimed = true end
    end
    check("finished task claimed", claimed)
end

-- Dragon Hunter: the task text picks the mobs.
otherSetup(7449423635)
do
    Settings.set("OtherDragonHunter", true)
    local hunter = newInstance("RemoteFunction", "RF/DragonHunter", rs.Modules.Net)
    hunter.OnInvoke = function(request)
        if request.Context == "Check" then return { Text = "Defeat 5 Hydra Enforcers" } end
    end
    local npc = newInstance("Model", "Dragon Hunter", folder("NPCs", workspace))
    part("HumanoidRootPart", Vector3.new(2, 0, 0), npc)
    Dragon.hunter.tick()
    local enforcer = mob("Hydra Enforcer", Vector3.new(90, 0, 0))
    Dragon.hunter.tick()
    eq("dragon hunter fights the enforcer", Dragon.hunter.target, enforcer)
end

-- Fishing: cast at the saved spot, catch when a fish bites.
otherSetup()
do
    Settings.set("OtherFishing", true)
    local rod = newInstance("Tool", "Fishing Rod", world.character)
    newInstance("Configuration", "FishingRodData", rod)
    local fishingData = newInstance("Folder", "FishingData", world.player.Data)
    fishingData:SetAttribute("SelectedBait", "Basic Bait")
    local fish = folder("FishReplicated", rs)
    local fishingRequest = newInstance("RemoteFunction", "FishingRequest", fish)
    fishingRequest.OnInvoke = function() return true end
    Fishing.saveSpot()
    Fishing.CAST_DELAY = 0
    Fishing.castPoint = function() return Vector3.new(0, -5, 20), true end

    Fishing.mode.tick()
    eq("start casting", fishingRequest.Invoked and fishingRequest.Invoked[1][1], "StartCasting")
    Fishing.mode.tick()
    local cast = fishingRequest.Invoked[2]
    eq("line cast at the point", cast and cast[1], "CastLineAtLocation")
    check("with power 98 on water", cast and cast[3] == 98 and cast[4] == true)

    Fishing.onFishingEvent(world.player, "SpawnFishOnBob")
    for _ = 1, 5 do stepTasks() end
    local actions = {}
    for _, call in ipairs(fishingRequest.Invoked) do actions[#actions + 1] = call[1] end
    check("fish caught", table.concat(actions, ","):find("Catching,Catch,Catch", 1, true) ~= nil, table.concat(actions, ","))
    Fishing.CAST_DELAY = 0.7
end

-- ESP: a label per fruit, removed with it.
otherSetup()
do
    Settings.set("EspFruit", true)
    local fruit = tool("Kilo Fruit", workspace)
    Esp.refresh()
    eq("one label for the fruit", Esp.count(), 1)
    fruit.Parent = nil
    Esp.refresh()
    eq("label removed with the fruit", Esp.count(), 0)
    Esp.destroy()
end

-- PVP: skill aim and gun aim at the nearest enemy.
otherSetup()
do
    local enemyPlayer = newInstance("Player", "Enemy", players)
    local enemyCharacter = newInstance("Model", "Enemy", world.characters)
    local enemyHumanoid = newInstance("Humanoid", "Humanoid", enemyCharacter)
    enemyHumanoid.Health = 100
    part("HumanoidRootPart", Vector3.new(50, 0, 0), enemyCharacter)
    enemyPlayer.Character = enemyCharacter
    eq("nearest enemy targeted", Pvp.target(), enemyCharacter)

    Settings.set("PvpAimbot", true)
    Pvp.aimStep()
    check("skills aimed at the enemy", AimHook.target ~= nil and AimHook.target.Position == Vector3.new(50, 0, 0))
    Settings.set("PvpAimbot", false)
    Pvp.aimStep()
    eq("aim released", AimHook.target, nil)

    local combat = rs.Modules.CombatUtil.ModuleValue
    local original = function() return "mouse" end
    combat.GetTargetPosition = original
    check("gun aim installed", Pvp.installGunAim())
    eq("gun aim off: the game's own answer", combat.GetTargetPosition(), "mouse")
    Settings.set("PvpGunAimbot", true)
    eq("gun aim on: the enemy", combat.GetTargetPosition(), Vector3.new(50, 0, 0))
    Pvp.destroy()
    eq("gun aim restored", combat.GetTargetPosition, original)

    Settings.set("PvpWaterWalk", true)
    world.hrp.Position = Vector3.new(10, -50, 10)
    Pvp.waterStep()
    check("platform under the sea surface", Pvp.platform() and Pvp.platform().CanCollide == true
        and Pvp.platform().Position.Y == -5)
    Settings.set("PvpWaterWalk", false)
    Pvp.waterStep()
    eq("platform removed", Pvp.platform(), nil)
end

-- Screen: notifications silenced and restored, rejoin on disconnect.
otherSetup()
do
    local shown = 0
    local original = function() shown = shown + 1 return true end
    moduleScript("Notification", rs, { Display = original, Dead = function() return false end })
    Settings.set("ScreenNoNotifications", true)
    check("notifications wrapped", Screen.wrapNotifications())
    local module = rs.Notification.ModuleValue
    module.Display({})
    eq("silenced notification not shown", shown, 0)
    Settings.set("ScreenNoNotifications", false)
    module.Display({})
    eq("shown again when off", shown, 1)
    Screen.destroy()
    eq("original restored", module.Display, original)

    local teleported
    local teleport = game:GetService("TeleportService")
    teleport.Teleport = function(_, placeId) teleported = placeId end
    Settings.set("ScreenAutoRejoin", true)
    local prompt = newInstance("Frame", "ErrorPrompt")
    local label = folder("ErrorMessage", folder("ErrorFrame", folder("MessageArea", prompt)))
    label.Text = "You were kicked: lost connection"
    Screen.onPrompt(prompt)
    stepTasks()
    eq("rejoined after a disconnect", teleported, game.PlaceId)
    Screen.reset()
end

-- Webhook: the ping and the embed are sent to the URL.
otherSetup()
do
    local sent
    request = function(options) sent = options end
    local http = game:GetService("HttpService")
    local body
    http.JSONEncode = function(_, value) body = value return "json" end
    check("no URL: nothing sent", not Webhook.send("Test", "x"))
    Settings.set("WebhookUrl", "https://discord.test/hook")
    Settings.set("WebhookPing", true)
    Settings.set("WebhookPingId", "123")
    check("sent", Webhook.send("Test", "hello"))
    eq("posted to the URL", sent and sent.Url, "https://discord.test/hook")
    eq("user pinged", body and body.content, "<@123>")
    eq("event in the embed", body and body.embeds[1].fields[1].value, "`Test`")
    request = nil
end

---------------------------------------------------------------------------
-- Devil fruits, raids, dungeon
---------------------------------------------------------------------------

local Fruits = require("Features.Fruits")
local Raids = require("Features.Raids")
local DungeonModes = require("Features.Dungeon")

local function batchBSetup(place, level)
    otherSetup(place, level)
    Fruits.reset()
    Raids.reset()
end

-- Random fruit: rolled only when the Cousin allows it.
batchBSetup()
do
    local level = 40
    world.commF.OnInvoke = function(action, what)
        if action == "Cousin" and what == "Check" then return 5000000, level, 1000000 end
        if action == "Cousin" and what == "CheckTime" then return true end
        if action == "Cousin" then return 1 end
    end
    check("below level 50: no roll", not Fruits.roll())
    level = 60
    check("allowed: rolled", Fruits.roll())
    local rolls = 0
    for _, call in ipairs(world.commF.Invoked) do
        if call[1] == "Cousin" and call[2] == "DLCBoxData" then rolls = rolls + 1 end
    end
    eq("one roll with the default box", rolls, 1)
end

-- Store fruit: once per tool, reported when the rarity is wanted.
batchBSetup()
do
    local fruit = tool("Kilo Fruit")
    fruit:SetAttribute("OriginalName", "Kilo-Kilo")
    moduleScript("FruitInfo", rs, { List = { ["Kilo-Kilo"] = { Rarity = { Name = "Mythical" } } } })
    local posted
    request = function(options) posted = options end
    Settings.set("WebhookUrl", "https://discord.test/hook")
    Settings.set("WebhookStoreFruit", true)
    Settings.set("WebhookFruitRarities", { Mythical = true })
    eq("fruit stored", Fruits.storeNext(), fruit)
    local store = calls(world.commF, "StoreFruit")
    eq("stored under its storage name", store[1] and store[1][2], "Kilo-Kilo")
    check("mythical store reported", posted ~= nil)
    eq("not stored twice", Fruits.storeNext(), nil)
    request = nil
end

-- Sniper: a wanted fruit on sale, unless one is already eaten.
batchBSetup()
do
    local fruitValue = newInstance("StringValue", "DevilFruit", world.player.Data)
    fruitValue.Value = "Kilo-Kilo"
    world.commF.OnInvoke = function(action)
        if action == "GetFruits" then
            return { { Name = "Dough-Dough", OnSale = true }, { Name = "Leopard-Leopard", OnSale = false } }
        end
    end
    Settings.set("FruitSniperList", { ["Dough-Dough"] = true, ["Leopard-Leopard"] = true })
    eq("wanted fruit on sale", Fruits.snipeTarget(), "Dough-Dough")
    fruitValue.Value = "Dough-Dough"
    eq("already eating a wanted fruit: no buy", Fruits.snipeTarget(), nil)
end

-- Raid: buy the chip, press the button with it, fight inside.
batchBSetup(7449423635, 1200)
do
    Settings.set("RaidAuto", true)
    check("level 1200: raid mode on", Raids.solo.enabled())
    Raids.solo.tick()
    local select = calls(world.commF, "RaidsNpc")
    eq("chip bought for the chosen raid", select[2] and select[2][3], "Flame")

    tool("Special Microchip")
    local main = folder("Main", folder("Button", folder("RaidSummon2", folder("Boat Castle", folder("Map", workspace)))))
    newInstance("ClickDetector", "ClickDetector", main)
    local pressed
    fireclickdetector = function(detector) pressed = detector end
    Raids.solo.tick()
    eq("summon pressed with the chip", pressed, main.ClickDetector)
    fireclickdetector = nil

    local hud = folder("TopHUDList", world.questPanel.Parent)
    newInstance("Frame", "RaidTimer", hud).Visible = true
    part("Island 1", Vector3.new(100, 0, 0), folder("Locations", folder("_WorldOrigin", workspace)))
    local raider = mob("Raid Mob", Vector3.new(50, 0, 0))
    check("in the raid", Raids.inRaid())
    Raids.solo.tick()
    eq("fights the raid mob", Raids.solo.target, raider)
end

-- Multi raid: the buyer starts only when every account is on a slot.
batchBSetup(7449423635, 1200)
do
    Settings.set("MultiRaid", true)
    Settings.set("MultiRaidBuyer", true)
    Settings.set("MultiRaidAccounts", { Friend = true })
    tool("Special Microchip")
    local summoner = folder("RaidSummon2", folder("Boat Castle", folder("Map", workspace)))
    local main = folder("Main", folder("Button", summoner))
    newInstance("ClickDetector", "ClickDetector", main)
    local slot = newInstance("Model", "Slot1", summoner)
    local hitbox = part("Hitbox", Vector3.new(200, 0, 0), slot)
    part("Color", Vector3.new(200, 0, 0), slot).BrickColor = { Name = "Really red" }
    local friend = newInstance("Player", "Friend", players)
    local friendCharacter = newInstance("Model", "Friend", world.characters)
    local friendRoot = part("HumanoidRootPart", Vector3.new(900, 0, 0), friendCharacter)
    friend.Character = friendCharacter

    local pressed
    fireclickdetector = function(detector) pressed = detector end
    Raids.multi.tick()
    eq("account off its slot: not started", pressed, nil)
    friendRoot.Position = hitbox.Position
    Raids.multi.tick()
    eq("everyone on a slot: started", pressed, main.ClickDetector)
    fireclickdetector = nil

    -- A slot taker goes to the free slot.
    Settings.set("MultiRaidBuyer", false)
    Settings.set("MultiRaidSlot", true)
    Raids.multi.tick()
    check("slot taker heads for the slot", Raids.multi.status:find("Taking a raid slot", 1, true) ~= nil, Raids.multi.status)
end

-- Dungeon join: the leader sets the difficulty and starts at the count.
batchBSetup()
do
    Settings.set("DungeonJoin", true)
    Settings.set("DungeonLeader", true)
    Settings.set("DungeonDifficulty", "Hard")
    world.player.UserId = 42
    local padsFolder = folder("Pads", folder("Simulation Hub", folder("Map", workspace)))
    local pad = newInstance("Model", "Pad1", padsFolder)
    pad.PrimaryPart = part("Base", Vector3.new(30, 0, 0), pad)
    pad:SetAttribute("NumPlayersOnPad", 0)
    local remote = newInstance("RemoteEvent", "DungeonSettingsChanged", pad)
    DungeonModes.join.tick()
    check("leader goes to a free pad", DungeonModes.join.status:find("Going to a dungeon pad", 1, true) ~= nil)

    local menu = newInstance("ScreenGui", "DungeonQueueSettingsMenu", world.player.PlayerGui)
    menu.Enabled = true
    pad:SetAttribute("Initiator", 42)
    pad:SetAttribute("NumPlayersOnPad", 2)
    pad:SetAttribute("Difficulty", "Normal")
    DungeonModes.join.tick()
    local fired = {}
    for _, call in ipairs(remote.Fired or {}) do fired[#fired + 1] = call[1] .. (call[2] and ("=" .. call[2]) or "") end
    eq("difficulty set then started", table.concat(fired, ","), "Difficulty=Hard,Start")
end

-- Dungeon attack: exit teleporter when behind, placeholder first.
batchBSetup()
do
    Settings.set("DungeonAttack", true)
    local objects = folder("DungeonReplicationObjects", rs)
    local run = newInstance("Folder", "Run", objects)
    run:SetAttribute("CurrentExploredLevel", 2)
    local explorers = newInstance("Folder", "Explorers", run)
    local info = newInstance("Configuration", "guid-1", explorers)
    info:SetAttribute("FloorId", 1)
    world.player:SetAttribute("ExplorerGUID", "guid-1")
    local floors = folder("Dungeon", folder("Map", workspace))
    local floor1 = newInstance("Model", "1", floors)
    local exit = newInstance("Model", "ExitTeleporter", floor1)
    part("Root", Vector3.new(0, 0, 40), exit)
    check("in a dungeon: attack on", DungeonModes.attack.enabled())
    DungeonModes.attack.tick()
    check("behind: heading for the exit", DungeonModes.attack.status:find("Going to floor 2", 1, true) ~= nil,
        DungeonModes.attack.status)

    info:SetAttribute("FloorId", 2)
    local floor2 = newInstance("Model", "2", floors)
    floor2.WorldPivot = CFrame.new(0, 0, 0)
    mob("Floor Mob", Vector3.new(10, 0, 0))
    local prop = mob("PropHitboxPlaceholder", Vector3.new(80, 0, 0))
    DungeonModes.attack.tick()
    eq("placeholder fought first", DungeonModes.attack.target, prop)
end

-- Dungeon cards: the priority wins over the other offers.
batchBSetup()
do
    moduleScript("ExplorerBuffs", folder("DungeonShared", rs), { ExplorerBuffs = {
        Lifesteal = { DisplayName = "<font color='red'>Lifesteal</font>" },
        Armor = { DisplayName = "Armor" },
    } })
    local picked
    local function offer(name)
        local screen = newInstance("ScreenGui", "Card" .. name, world.player.PlayerGui)
        local label = newInstance("TextLabel", "DisplayName", screen)
        label.Text = name == "Lifesteal" and "<font color='red'>Lifesteal</font>" or name
        newInstance("TextLabel", "BuffDescription", screen)
        local button = newInstance("TextButton", "Pick", screen)
        button.Name = "Pick"
        return button
    end
    offer("Lifesteal")
    local armorButton = offer("Armor")
    getconnections = function(signal)
        return { { Function = function() picked = signal end } }
    end
    Settings.set("DungeonCard1", "Armor")
    local chosen = DungeonModes.pickCard()
    eq("priority card picked", chosen and chosen.name, "Armor")
    eq("its button pressed", picked, armorButton.Activated)
    getconnections = nil
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

local Items = require("Features.Items")
local Swords = require("Features.Items.Swords")
local Cdk = require("Features.Items.Cdk")
local Guitar = require("Features.Items.Guitar")
local ItemMastery = require("Features.Items.Mastery")

local function itemsSetup(place, level, inventory, answers)
    batchBSetup(place, level)
    Items.reset()
    Swords.reset()
    Cdk.reset()
    Guitar.reset()
    ItemMastery.reset()
    world.commF.OnInvoke = function(action, ...)
        if action == "getInventory" then return inventory or {} end
        local answer = answers and answers[action]
        if type(answer) == "function" then return answer(...) end
        return answer
    end
end

-- Rainbow Haki: ask the Horned Man, then kill the quest's boss.
itemsSetup(7449423635, 2000, {}, { HornedMan = 0 })
do
    Settings.set("ItemRainbowHaki", true)
    local npc = newInstance("Model", "Horned Man", folder("NPCs", workspace))
    part("HumanoidRootPart", Vector3.new(2, 0, 0), npc)
    check("rainbow on", Swords.rainbow.enabled())
    Swords.rainbow.tick()
    local bets = 0
    for _, call in ipairs(world.commF.Invoked) do if call[1] == "HornedMan" and call[2] == "Bet" then bets = bets + 1 end end
    eq("quest asked", bets, 1)
    questTitle("Defeat Stone")
    local stone = mob("Stone", Vector3.new(60, 0, 0))
    Swords.rainbow.tick()
    eq("quest boss fought", Swords.rainbow.target, stone)
end

-- Yama: elites under 30, then the sealed katana.
do
    local progress = 10
    itemsSetup(7449423635, 2000, {}, { EliteHunter = function(what) if what == "Progress" then return progress end end })
    Settings.set("ItemYama", true)
    mob("Diablo", Vector3.new(50, 0, 0))
    Swords.yama.tick()
    check("under 30: elite quest asked", #calls(world.commF, "EliteHunter") >= 2)
    progress = 30
    StackCommon.forget()
    local katana = newInstance("Model", "SealedKatana", folder("Waterfall", folder("Map", workspace)))
    katana.WorldPivot = CFrame.new(10, 0, 0)
    local hitbox = part("Hitbox", Vector3.new(10, 0, 0), katana)
    newInstance("ClickDetector", "ClickDetector", hitbox)
    local clicked
    fireclickdetector = function(detector) clicked = detector end
    Swords.yama.tick()
    eq("katana clicked", clicked, hitbox.ClickDetector)
    fireclickdetector = nil
end

-- Tushita: waits without rip_indra, lights the torches with the Holy Torch.
itemsSetup(7449423635, 2000, {}, { TushitaProgress = function(what) if what == nil then return { OpenedDoor = false } end end })
do
    Settings.set("ItemTushita", true)
    local island = folder("IslandModel", folder("Waterfall", folder("Map", workspace)))
    part("Hitbox", Vector3.new(30, 0, 0), island)
    check("no rip_indra: tushita waits", not Swords.tushita.enabled())
    tool("Holy Torch")
    check("holy torch: tushita on", Swords.tushita.enabled())
    Swords.tushita.tick()
    local torches = 0
    for _, call in ipairs(world.commF.Invoked) do if call[1] == "TushitaProgress" and call[2] == "Torch" then torches = torches + 1 end end
    eq("five torches lit", torches, 5)
end

-- CDK: the right pedestal, the right trial.
do
    local progress = { Good = 4, Evil = 3 }
    itemsSetup(7449423635, 2200,
        { { Name = "Tushita", Type = "Sword", Mastery = 400 }, { Name = "Yama", Type = "Sword", Mastery = 400 } },
        { CDKQuest = function(what) if what == "Progress" then return progress end end })
    Settings.set("ItemCDK", true)
    tool("Tushita")
    check("cdk requirements met", Cdk.requirements() == nil, Cdk.requirements())
    local cursed = folder("Cursed", folder("Turtle", folder("Map", workspace)))
    local pedestal = part("Pedestal2", Vector3.new(3, 0, 0), cursed)
    local prompt = newInstance("ProximityPrompt", "ProximityPrompt", pedestal)
    local fired
    fireproximityprompt = function(target) fired = target end
    Cdk.mode.tick()
    eq("good 4 / evil 3: pedestal 2", fired, prompt)
    fireproximityprompt = nil
    progress = { Good = 1, Evil = 0 }
    StackCommon.forget()
    Cdk.mode.tick()
    local started
    for _, call in ipairs(world.commF.Invoked) do if call[1] == "CDKQuest" and call[2] == "StartTrial" then started = call[3] end end
    eq("good trial started", started, "Good")
end

-- Soul Guitar: the missing material, in its sea.
itemsSetup(7449423635, 2200, { { Name = "Dark Fragment", Type = "Material", Count = 1 },
    { Name = "Ectoplasm", Type = "Material", Count = 10 } })
do
    Settings.set("ItemSoulGuitar", true)
    newInstance("IntValue", "Fragments", world.player.Data).Value = 6000
    eq("ectoplasm missing", Guitar.missing(), "Ectoplasm")
    Guitar.mode.tick()
    eq("travels to Sea 2 for it", #calls(world.commF, "TravelDressrosa"), 1)
end

-- TTK: the sword under 300 mastery is taken out.
itemsSetup(7449423635, 2200, { { Name = "Oroshi", Type = "Sword", Mastery = 350 },
    { Name = "Saishi", Type = "Sword", Mastery = 100 }, { Name = "Shizu", Type = "Sword", Mastery = 0 } })
do
    Settings.set("ItemTTK", true)
    eq("next TTK sword", Swords.ttkNext(), "Saishi")
    Swords.ttk.tick()
    local loaded = calls(world.commF, "LoadItem")
    eq("sword taken out", loaded[1] and loaded[1][2], "Saishi")
end

-- Melee mastery: buys the missing melee, moves on at 600.
itemsSetup()
do
    Settings.set("ItemMeleeMastery", true)
    ItemMastery.melee.tick()
    eq("missing melee bought", #calls(world.commF, "BuySuperhuman"), 1)
    local superhuman = tool("Superhuman")
    newInstance("IntValue", "Level", superhuman).Value = 600
    eq("600 reached: next melee", ItemMastery.nextMelee(), "Death Step")
end

-- Shark Anchor: the first craft possible.
itemsSetup(nil, nil, { { Name = "Mutant Tooth", Type = "Material", Count = 1 }, { Name = "Shark Tooth", Type = "Material", Count = 5 } })
do
    eq("tooth necklace first", Items.nextSharkCraft(), "ToothNecklace")
    Settings.set("ItemTradeBones", true)
    Items.step()
    eq("bones traded", #calls(world.commF, "Bones"), 1)
end

-- Upgrade: the Blacksmith's list, then the missing material farmed.
itemsSetup(7449423635, 2200, { { Name = "Katana", Type = "Sword", Rarity = 1, Upgrades = 0 } }, {
    UpgradeItem = function() return { Required = { { Name = "Scrap Metal", Required = 5 } }, Result = {} } end,
})
do
    Settings.set("ItemUpgradeSword", true)
    local katana = tool("Katana")
    katana.ToolTip = "Sword"
    local smith = newInstance("Model", "Blacksmith", folder("NPCs", workspace))
    part("Head", Vector3.new(0, 2, -2), smith)
    ItemMastery.upgradeSword.tick()
    ItemMastery.upgradeSword.tick()
    check("farms the missing material", ItemMastery.upgradeSword.status:find("Scrap Metal 0/5", 1, true) ~= nil,
        ItemMastery.upgradeSword.status)
end


---------------------------------------------------------------------------
-- Races
---------------------------------------------------------------------------

local RaceUpgrade = require("Features.Races.Upgrade")
local RaceV4 = require("Features.Races.V4")
local Duel = require("Features.Races.Duel")

local function raceSetup(place, race, answers)
    itemsSetup(place, 2000, {}, answers)
    RaceUpgrade.reset()
    RaceV4.reset()
    Duel.reset()
    newInstance("StringValue", "Race", world.player.Data).Value = race
end

-- V2: the Alchemist's quest is taken with enough Beli.
raceSetup(4442272183, "Human", { Alchemist = 0, Wenlocktoad = 0 })
do
    newInstance("IntValue", "Beli", world.player.Data).Value = 600000
    Settings.set("RaceV2V3", true)
    check("v2v3 on", RaceUpgrade.v2v3.enabled())
    RaceUpgrade.v2v3.tick()
    local asked = false
    for _, call in ipairs(calls(world.commF, "Alchemist")) do
        if call[2] == "2" then asked = true end
    end
    check("Alchemist quest taken", asked, RaceUpgrade.v2v3.status)
end

-- V3 done: the mode lets the next farm run.
raceSetup(4442272183, "Human", { Alchemist = -2, Wenlocktoad = -2 })
do
    Settings.set("RaceV2V3", true)
    check("already V3: v2v3 off", not RaceUpgrade.v2v3.enabled())
end

-- Human V3: the listed bosses are fought.
raceSetup(4442272183, "Human", { Alchemist = -2, Wenlocktoad = 1 })
do
    Settings.set("RaceV2V3", true)
    local jeremy = mob("Jeremy", Vector3.new(0, 0, 10))
    RaceUpgrade.v2v3.tick()
    eq("Jeremy fought", RaceUpgrade.v2v3.target, jeremy)
end

-- Cyborg: bought once the trainer allows it.
raceSetup(4442272183, "Human", { CyborgTrainer = true })
do
    Settings.set("RaceCyborg", true)
    RaceUpgrade.cyborg.tick()
    local bought = false
    for _, call in ipairs(calls(world.commF, "CyborgTrainer")) do
        if call[2] == "Buy" then bought = true end
    end
    check("Cyborg bought", bought, RaceUpgrade.cyborg.status)
end

-- Gear selection follows the temple's rules.
do
    eq("no level: gear 1", RaceV4.selectableGear({ HadPoint = false, RaceLevel = 1,
        RaceDetails = { A = 0, B = 0, C = 0, Gears = {} } }), "Gear1")
    eq("first point: gear 2", RaceV4.selectableGear({ HadPoint = true, RaceLevel = 2,
        RaceDetails = { A = 0, B = 0, C = 0, Gears = {} } }), "Gear2")
    eq("second point: gear 3", RaceV4.selectableGear({ HadPoint = true, RaceLevel = 2,
        RaceDetails = { A = 1, B = 0, C = 0, Gears = { "A" } } }), "Gear3")
    eq("no point: nothing", RaceV4.selectableGear({ HadPoint = false, RaceLevel = 3,
        RaceDetails = { A = 1, B = 0, C = 0, Gears = { "A" } } }), nil)
end

-- Buy gear: the Ancient One's offer is taken.
raceSetup(7449423635, "Mink", { UpgradeRace = function(what) if what == "Check" then return 2, 0, 1000 end end })
do
    newInstance("BoolValue", "RaceTransformed", world.character)
    check("gear offered", RaceV4.status():find("Can Buy Gear", 1, true) ~= nil, RaceV4.status())
    check("gear bought", RaceV4.buyGear())
    local bought = false
    for _, call in ipairs(calls(world.commF, "UpgradeRace")) do
        if call[2] == "Buy" then bought = true end
    end
    check("Buy sent", bought)
end

-- Trial: without the temple, fly to it.
raceSetup(7449423635, "Mink", {})
do
    Settings.set("RaceTrial", true)
    check("trial on", RaceV4.trial.enabled())
    RaceV4.trial.tick()
    eq("goes to the temple", RaceV4.trial.status, "Going to the Temple of Time")
end


---------------------------------------------------------------------------
-- Sea events, islands, volcano
---------------------------------------------------------------------------

local Boat = require("Game.Boat")
local SeaEvents = require("Features.Sea.Events")
local SeaIslands = require("Features.Sea.Islands")
local Volcano = require("Features.Sea.Volcano")

local function seaSetup(place, inventory, answers)
    itemsSetup(place or 7449423635, 2500, inventory, answers)
    Boat.reset()
    SeaEvents.reset()
    SeaIslands.reset()
    Volcano.reset()
end

local function makeBoat(position, owner)
    local boats = workspace:FindFirstChild("Boats") or folder("Boats", workspace)
    local model = newInstance("Model", "Guardian", boats)
    newInstance("ObjectValue", "Owner", model).Value = owner or world.player.Name
    newInstance("IntValue", "Humanoid", model).Value = 100
    local seat = part("VehicleSeat", position, model)
    return model, seat
end

local function hud(name, visible)
    local main = world.player.PlayerGui.Main
    local list = main:FindFirstChild("TopHUDList") or newInstance("Frame", "TopHUDList", main)
    local timer = newInstance("Frame", name, list)
    timer.Visible = visible
    return timer
end

local function seaBeast(position, label)
    local beasts = workspace:FindFirstChild("SeaBeasts") or folder("SeaBeasts", workspace)
    local beast = newInstance("Model", "SeaBeast1", beasts)
    part("HumanoidRootPart", position, beast)
    newInstance("IntValue", "Health", beast).Value = 100
    local bbg = newInstance("BillboardGui", "HealthBBG", beast)
    local frame = newInstance("Frame", "Frame", bbg)
    newInstance("TextLabel", "TextLabel", frame).Text = label
    return beast
end

local function ship(position, name)
    local model = newInstance("Model", name or "PirateBrigade", folder("Enemies", workspace))
    part("Engine", position, model)
    newInstance("IntValue", "Health", model).Value = 500
    return model
end

-- Boat: bought at the dealer, boarded, then driven.
seaSetup()
do
    local status = select(2, Boat.get())
    eq("no boat: to the dealer", status, "Going to the boat dealer")
    near("flying to the Sea 3 dealer", Movement.goal().Position, Boat.DEALERS[3])
    world.hrp.Position = Boat.DEALERS[3]
    eq("at the dealer: buying", select(2, Boat.get()), "Buying a boat")
    local bought = calls(world.commF, "BuyBoat")
    eq("BuyBoat sent once", #bought, 1)
    eq("the chosen boat", bought[1] and bought[1][2], "Guardian")
    eq("brigades get their prefix", Boat.buyName("GrandBrigade"), "PirateGrandBrigade")

    local model, seat = makeBoat(Boat.DEALERS[3] + Vector3.new(20, 0, 0))
    eq("boat there: boarding", select(2, Boat.get()), "Getting on the boat")
    near("flying to the seat", Movement.goal().Position, seat.Position)
    world.humanoid.SeatPart = seat
    eq("seated: the boat", Boat.get(), model)
    check("movement handed over", Movement.goal() == nil)

    seat.Position = Vector3.new(0, 10, 0)
    Boat.to(Vector3.new(1000, 10, 0))
    Boat.step(0.1)
    near("one step at SeaBoatSpeed", seat.Position, Vector3.new(35, 10, 0))
    seat.Position = Vector3.new(-100, 10, 0)
    Boat.step(0.1)
    near("slower after a pull-back", seat.Position, Vector3.new(-100 + 24.5, 10, 0))
    world.humanoid.SeatPart = nil
    Boat.step(0.1)
    check("leaving the seat stops the driver", Boat.goal() == nil)
end

-- Sea events: found in the reference's order, within range.
seaSetup()
do
    local weak = seaBeast(Vector3.new(100, 0, 0), "40,000/60,000")
    check("sea beast under 90k ignored", SeaEvents.find(SeaEvents.ALL) == nil)
    check("any sea beast for the Fishman quest", SeaEvents.anySeaBeast() == weak)
    local beast = seaBeast(Vector3.new(150, 0, 0), "90,000/120,000")
    local brigade = ship(Vector3.new(50, 0, 0))
    local shark = mob("Shark", Vector3.new(10, 0, 0))
    eq("sea beast first", SeaEvents.find(SeaEvents.ALL), beast)
    eq("ship next", SeaEvents.find({ Ship = true, Shark = true }), brigade)
    eq("shark when chosen alone", SeaEvents.find({ Shark = true }), shark)
    ship(Vector3.new(30, 0, 0), "PirateBasic")
    eq("brigades only", SeaEvents.find({ Ship = true }, 2000, true), brigade)
    check("out of range", SeaEvents.find({ Shark = true }, 5) == nil)
end

-- Auto Sea Event: sails to the zone, then fights what shows up.
seaSetup()
do
    Settings.set("SeaAuto", true)
    Settings.set("SeaEventKinds", { Ship = true })
    local _, seat = makeBoat(Vector3.new(0, 0, 0))
    world.humanoid.SeatPart = seat
    SeaEvents.auto.tick()
    eq("sails to the zone", SeaEvents.auto.status, "Sailing to Zone 1")
    near("boat heads for Zone 1", Boat.goal().Position, Vector3.new(Boat.ZONES["Zone 1"].X, 0, Boat.ZONES["Zone 1"].Z))
    local target = ship(Vector3.new(0, 0, 300))
    SeaEvents.auto.tick()
    eq("sinks the ship", SeaEvents.auto.status, "Sinking PirateBrigade")
    near("under its engine", Movement.goal().Position, target.Engine.Position + Vector3.new(0, -15, 0))
    check("boat driver stopped", Boat.goal() == nil)
end

-- Leviathan: tail, then head, then segments.
seaSetup()
do
    local beasts = folder("SeaBeasts", workspace)
    local function piece(name, attributes)
        local model = newInstance("Model", name, beasts)
        part("HumanoidRootPart", Vector3.new(0, 0, 0), model)
        part("Hitbox11", Vector3.new(0, 0, 0), model)
        newInstance("IntValue", "Health", model).Value = 1000
        for key, value in pairs(attributes) do model:SetAttribute(key, value) end
        return model
    end
    local segment = piece("Leviathan Segment", { SegmentId = 3 })
    local head = piece("Leviathan", { Armored = true })
    local tail = piece("Leviathan Tail", { HealthEnabled = true })
    eq("exposed tail first", SeaIslands.leviathanTarget(), tail)
    tail:SetAttribute("HealthEnabled", false)
    eq("armored head skipped", SeaIslands.leviathanTarget(), segment)
    head:SetAttribute("Armored", false)
    eq("head when exposed", SeaIslands.leviathanTarget(), head)
end

-- Kitsune: embers are traded only during the event, once there are enough.
seaSetup(nil, { { Name = "Azure Ember", Type = "Material", Count = 12 } })
do
    local pray = newInstance("RemoteFunction", "RF/KitsuneStatuePray", rs.Modules.Net)
    check("no trade outside the event", not SeaIslands.tradeEmbers())
    hud("RaidTimer", true)
    check("trade during the event", SeaIslands.tradeEmbers())
    eq("prayed once", #(pray.Invoked or {}), 1)
    Settings.set("SeaAzureEmbers", 20)
    check("not enough embers", not SeaIslands.tradeEmbers())
end

-- Spawn reports: once per appearance.
seaSetup()
do
    Settings.set("WebhookMirage", true)
    Settings.set("WebhookUrl", "https://example.invalid/hook")
    local sent = {}
    local realSend = Webhook.send
    Webhook.send = function(event) sent[#sent + 1] = event return true end
    local map = folder("Map", workspace)
    local island = folder("MysticIsland", map)
    SeaIslands.step()
    SeaIslands.step()
    eq("reported once", #sent, 1)
    eq("report name", sent[1], "Mirage Island")
    island.Parent = nil
    SeaIslands.step()
    island.Parent = map
    SeaIslands.step()
    eq("reported again after it left", #sent, 2)
    Webhook.send = realSend
end

-- Volcano: start the event, golems before rocks, rocks from their offset.
seaSetup()
do
    Settings.set("VolcanoEvent", true)
    world.player:SetAttribute("CurrentLocation", "Prehistoric Island")
    local map = folder("Map", workspace)
    local island = folder("PrehistoricIsland", map)
    local center = folder("Core", island)
    local prompt = part("ActivationPrompt", Vector3.new(50, 0, 0), center)
    newInstance("ProximityPrompt", "ProximityPrompt", prompt)
    local lava = part("Lava", Vector3.new(0, 0, 0), island)
    local burn = newInstance("TouchTransmitter", "TouchInterest", lava)
    local teleport = part("TrialTeleport", Vector3.new(0, 0, 0), island)
    local keep = newInstance("TouchTransmitter", "TouchInterest", teleport)
    check("event mode on with the island", Volcano.event.enabled())
    Volcano.event.tick()
    eq("starts the volcano", Volcano.event.status, "Starting the volcano")
    near("to the activation prompt", Movement.goal().Position, prompt.Position)
    check("lava touch removed", burn.Parent == nil)
    check("trial teleport kept", keep.Parent == teleport)

    hud("PrehistoricRaidTimer", true)
    local rocks = folder("VolcanoRocks", center)
    local rock = newInstance("Model", "Rock", rocks)
    rock.WorldPivot = CFrame.new(100, 273.5, 0)
    local layer = newInstance("Folder", "VFXLayer", rock)
    newInstance("ParticleEmitter", "Specs", layer).Enabled = true
    local golem = mob("Lava Golem", Vector3.new(20, 0, 0))
    Volcano.event.tick()
    eq("golem first", Volcano.event.target, golem)
    golem.Humanoid.Health = 0
    Volcano.event.tick()
    eq("then the rock", Volcano.event.status, "Plugging an erupting rock")
    near("rock offset for its height", Movement.goal().Position, Vector3.new(140, 273.5, 0))
end

-- Volcanic Magnet: Scrap Metal first, crafted with everything.
seaSetup(nil, {})
do
    Settings.set("VolcanoMagnet", true)
    check("magnet wanted", Volcano.magnet.enabled())
    Volcano.magnet.tick()
    check("scrap metal first", Volcano.magnet.status:find("Scrap Metal 0/10", 1, true) ~= nil, Volcano.magnet.status)
end
seaSetup(nil, {
    { Name = "Scrap Metal", Type = "Material", Count = 10 },
    { Name = "Blaze Ember", Type = "Material", Count = 15 },
})
do
    Settings.set("VolcanoMagnet", true)
    local craft = newInstance("RemoteFunction", "RF/Craft", rs.Modules.Net)
    Volcano.magnet.tick()
    eq("crafting", Volcano.magnet.status, "Crafting the Volcanic Magnet")
    eq("craft sent", craft.Invoked and craft.Invoked[1][2], "Volcanic Magnet")
end

-- Dojo Red belt: a Terrorshark at sea, counted once it is down.
seaSetup()
do
    Settings.set("OtherDojo", true)
    local quest = newInstance("RemoteFunction", "RF/InteractDragonQuest", rs.Modules.Net)
    quest.OnInvoke = function() return { Quest = { BeltName = "Red", Progress = 0, Goal = 1 } } end
    world.hrp.Position = Dragon.TRAINER
    Dragon.dojo.tick()
    eq("red belt started", Dragon.dojo.status, "Red belt started")
    local shark = mob("Terrorshark", Dragon.TRAINER + Vector3.new(0, 0, 50))
    Dragon.dojo.tick()
    eq("fights the Terrorshark", Dragon.dojo.target, shark)
    shark.Humanoid.Health = 0
    Dragon.dojo.tick()
    check("counted", Dragon.describe():find("Red belt, 1 done", 1, true) ~= nil, Dragon.describe())
end

-- Drive to Tiki: moves on to the next waypoint once reached.
seaSetup()
do
    Settings.set("SeaDriveTiki", true)
    local _, seat = makeBoat(SeaEvents.TIKI_ROUTE[1])
    world.hrp.Position = SeaEvents.TIKI_ROUTE[1]
    world.humanoid.SeatPart = seat
    SeaEvents.driveTiki.tick()
    eq("next waypoint", SeaEvents.driveTiki.status, "Driving (2/5)")
end

-- Fishman V3: by boat to the sea beasts.
raceSetup(4442272183, "Fishman", { Alchemist = -2, Wenlocktoad = 1 })
do
    Settings.set("RaceV2V3", true)
    Boat.reset()
    RaceUpgrade.v2v3.tick()
    eq("Fishman V3 goes for a boat", RaceUpgrade.v2v3.status, "Fishman V3: Going to the boat dealer")
end

---------------------------------------------------------------------------
-- Auto Buso
---------------------------------------------------------------------------

setup()
do
    local PlayerTweaks = require("Features.PlayerTweaks")
    world.commF.OnInvoke = function() return true end
    check("buso requested when off", PlayerTweaks.ensureBuso())
    eq("Buso action sent", #calls(world.commF, "Buso"), 1)
    check("no second request during the cooldown", not PlayerTweaks.ensureBuso())

    PlayerTweaks.reset()
    newInstance("Part", "_BusoLayer1Arm", world.character)
    check("aura present: nothing to do", not PlayerTweaks.ensureBuso())

    PlayerTweaks.reset()
    world.character._BusoLayer1Arm.Parent = nil
    newInstance("BoolValue", "HasBuso", world.character)
    check("HasBuso present: nothing to do", not PlayerTweaks.ensureBuso())
    eq("still one request in total", #calls(world.commF, "Buso"), 1)

    PlayerTweaks.reset()
    world.character.HasBuso.Parent = nil
    local target = mob("Zombie", Vector3.new(0, 0, 0))
    require("Features.Fight").engage({}, target)
    eq("fight turns buso on", #calls(world.commF, "Buso"), 2)
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------

Loop.stopAll()
clearTasks()

print(string.format("core: %d passed, %d failed", passed, failed))
for _, failure in ipairs(failures) do print("  FAIL " .. failure) end
if failed > 0 then os.exit(1) end
