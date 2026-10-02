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

-- The real purchases: the calls with `true` only ask.
local function buys(remote, action)
    local out = {}
    for _, call in ipairs(calls(remote, action)) do
        if call[2] ~= true then out[#out + 1] = call end
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
    "Game.Router", "Game.Entrances", "Game.Pads", "Game.Hook", "Game.Regions", "Game.TeleportTag", "Game.Gateway",
    "Game.IslandLoader",
    "Features.StackFarm", "Features.Stack.Common", "Features.Stack.World", "Features.Stack.Chests",
    "Features.Stack.Bosses", "Features.Stack.Summons", "Features.Stack.EliteHunter", "Features.Stack.Events",
    "Features.ChestHunt", "Features.Other.Mode", "Features.Other.Simple", "Features.Other.Observation",
    "Features.Other.Dragon", "Features.Other.Fishing", "Features.Esp", "Features.Pvp", "Features.Screen",
    "Features.Webhook", "Features.Fruits", "Features.Raids", "Features.Dungeon",
    "Features.Items", "Features.Items.Swords", "Features.Items.Cdk", "Features.Items.Guitar",
    "Features.Items.Saber", "Features.Items.Mastery", "Features.Races.Duel", "Features.Races.Upgrade",
    "Features.Races.V4", "Game.Boat", "Features.Sea.Events", "Features.Sea.Islands", "Features.Sea.Volcano",
    "Features.TyrantFarm", "Features.Helpers", "Features.SafeSpot", "Features.Scout",
    "Kaitun.Config", "Kaitun.Tasks", "Kaitun.Engine", "Kaitun.Screen",
    "Features.Items.Melee", "Features.Items.Electric", "Features.SkipLevel", "Features.Codes", "UI.Logo",
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
local Pads = require("Game.Pads")
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
    Pads.reset()
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
    world.hrp.Position = Vector3.new(0, 30, 0)
    Movement.to(CFrame.new(100, 30, 0))
    Movement.step(dt)
    near("one step at TweenSpeed", world.hrp.Position, Vector3.new(5, 30, 0))
    check("float force added", world.hrp:FindFirstChild("FloatForce") ~= nil)

    -- The server pulls the character back: the cap drops to 70 %.
    world.hrp.Position = Vector3.new(-50, 30, 0)
    Movement.step(dt)
    near("slower after a pull-back", world.hrp.Position, Vector3.new(-50 + 3.5, 30, 0))

    world.hrp.Position = Vector3.new(99, 30, 0)
    Movement.step(dt)
    near("snaps onto a close goal", world.hrp.Position, Vector3.new(100, 30, 0))

    Movement.step(1)
    near("a huge dt is capped per frame", world.hrp.Position, Vector3.new(100, 30, 0))

    Movement.stop()
    check("stop clears the goal", not Movement.moving())
    check("stop removes the float force", world.hrp:FindFirstChild("FloatForce") == nil)

    Movement.reset()
    world.hrp.Position = Vector3.new(0, 30, 0)
    Movement.to(CFrame.new(1000, 30, 0))
    Movement.step(1)
    near("step never exceeds the per-frame cap", world.hrp.Position, Vector3.new(18, 30, 0))
end

-- Never through the water while the goal is far; free over the goal.
setup()
do
    Settings.set("SmartTravel", false)
    Movement.reset()
    world.hrp.Position = Vector3.new(0, 0, 0)
    Movement.to(CFrame.new(2000, 0, 0))
    for _ = 1, 10 do Movement.step(1 / 60) end
    check("far goal at sea level: climbs above the water", world.hrp.Position.Y > 0, tostring(world.hrp.Position))
    for _ = 1, 30 do Movement.step(1 / 60) end
    check("then stays above it", world.hrp.Position.Y >= 20, tostring(world.hrp.Position))
    world.hrp.Position = Vector3.new(1950, 25, 0)
    Movement.to(CFrame.new(2000, 5, 0))
    Movement.step(1 / 60)
    check("over the goal: comes down", world.hrp.Position.Y < 25, tostring(world.hrp.Position))
    world.hrp.Position = Vector3.new(60000, 0, 1800)
    Movement.to(CFrame.new(61163, -10, 1819))
    Movement.step(1 / 60)
    check("underwater city: no floor", world.hrp.Position.Y <= 0, tostring(world.hrp.Position))
    Movement.stop()
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

-- Double quest: the giver's two quests; the other one while the best
-- one's mobs are not up.
setup({ level = 980 })
do
    local pair = Quests.pair(980)
    eq("pair: both quests of the giver", #pair, 2)
    eq("pair: best first", pair[1].mob, "Vampire")
    eq("pair: then the other", pair[2].mob, "Zombie")
    eq("pair at 960: only one", #Quests.pair(960), 1)

    LevelFarm.stop()
    world.commF.OnInvoke = function() return true end
    world.hrp.Position = Vector3.new(1000, 14, 1002)
    local function startedId()
        local calls = world.commF.Invoked or {}
        local last = calls[#calls]
        return last and last[3]
    end

    -- Vampires all dead, Zombies up: the Zombie quest.
    mob("Zombie", Vector3.new(1050, 5, 1000))
    mob("Zombie", Vector3.new(1060, 5, 1000))
    LevelFarm.tick()
    eq("best mobs down: the other quest", startedId(), 1)
    check("status says double quest", LevelFarm.status:find("double quest", 1, true) ~= nil, LevelFarm.status)

    -- Vampires up as well: the best quest again.
    for index = 1, 3 do mob("Vampire", Vector3.new(1000 + index * 10, 5, 1050)) end
    LevelFarm.stop()
    world.commF.Invoked = nil
    LevelFarm.tick()
    eq("best mobs up: the best quest", startedId(), 2)

    -- Off: always the best.
    Settings.set("DoubleQuest", false)
    for _, model in ipairs(Enemies.all("Vampire")) do model.Parent = nil end
    LevelFarm.stop()
    world.commF.Invoked = nil
    LevelFarm.tick()
    eq("double quest off: the best quest", startedId(), 2)
    Settings.set("DoubleQuest", true)

    -- StartQuest from 30 studs, while still flying in.
    LevelFarm.stop()
    world.commF.Invoked = nil
    world.hrp.Position = Vector3.new(1000, 14, 1025)
    LevelFarm.tick()
    check("StartQuest from 25 studs away", startedId() ~= nil)
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

    Settings.set("SkillsFruit", { Z = true })
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
    lighting:SetAttribute("MoonPhase", 5)
    sky.MoonTextureId = ""
    eq("MoonPhase attribute first: full", World.moon(), "Full Moon")
    lighting:SetAttribute("MoonPhase", 4)
    eq("MoonPhase 4: next night", World.moon(), "Next Night")
    lighting:SetAttribute("MoonPhase", 2)
    eq("MoonPhase 2: normal", World.moon(), "Normal")
    lighting:SetAttribute("MoonPhase", nil)
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

-- Teddy's stat order, by level.
do
    local function plan(points, level, levels)
        local out = {}
        for _, step in ipairs(Stats.teddyPlan(points, level, levels or {})) do out[#out + 1] = step.stat .. "=" .. step.points end
        return table.concat(out, ",")
    end
    eq("teddy: under 55 all into Melee", plan(30, 30), "Melee=30")
    eq("teddy: from 55 Defense to 15 first", plan(30, 100), "Defense=15,Melee=15")
    eq("teddy: from 300 Defense to 100", plan(300, 350, { Defense = 15 }), "Defense=85,Melee=215")
    eq("teddy: Melee to the cap, then Defense", plan(20, 350, { Defense = 100, Melee = 2790 }), "Melee=10,Defense=10")
    eq("teddy: from 400 Sword 600 then Demon Fruit 1950",
        plan(700, 500, { Defense = 2800, Melee = 2800, Sword = 500 }), "Sword=100,Demon Fruit=600")
    eq("teddy: all done", plan(50, 2800, { Defense = 2800, Melee = 2800, Sword = 600, ["Demon Fruit"] = 1950 }), "")
    eq("teddy: no points", plan(0, 500), "")
end

setup()
do
    Server.reset()
    Settings.set("AutoStats", true)
    Settings.set("StatMode", "Even")
    Settings.set("StatTargets", { Sword = true })
    local points = newInstance("IntValue", "Points", world.player.Data)
    points.Value = 6
    world.commF.OnInvoke = function() return true end
    Stats.tick()
    local call = world.commF.Invoked and world.commF.Invoked[1]
    eq("AddPoint action", call and call[1], "AddPoint")
    eq("AddPoint stat", call and call[2], "Sword")
    eq("AddPoint amount", call and call[3], 6)
    Settings.set("StatMode", "Teddy")

    -- Teddy's order (level 960 here): Defense to 100 first, then Melee.
    world.commF.Invoked = nil
    points.Value = 150
    Stats.tick()
    local sent = world.commF.Invoked or {}
    eq("teddy: Defense first", sent[1] and sent[1][2], "Defense")
    eq("teddy: to 100", sent[1] and sent[1][3], 100)
    eq("teddy: then Melee", sent[2] and sent[2][2], "Melee")
    eq("teddy: with the rest", sent[2] and sent[2][3], 50)

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
-- Smart travel: portal doors (Vxeze's), temple, reset teleport
---------------------------------------------------------------------------

local SEA3 = 7449423635
local CASTLE = Vector3.new(-5000, 318, -3100)
local function door(name)
    for _, pad in ipairs(Pads.LIST[3]) do
        if pad.name == name then return pad end
    end
end
local function wear(item)
    return newInstance("Accessory", item, world.character)
end

-- Short trips are set in one go.
setup()
do
    Movement.reset()
    world.hrp.Position = Vector3.new(0, 0, 0)
    Movement.to(CFrame.new(100, 0, 0))
    Movement.step(1 / 60)
    near("short trip set in one go", world.hrp.Position, Vector3.new(100, 0, 0))
end

-- Choosing a route through the doors.
setup()
do
    game.PlaceId = SEA3
    local toHydra = door("Castle to Hydra")
    local goal = toHydra.dest + Vector3.new(300, 0, 0)
    local locked = Router.plan(CASTLE, goal)
    eq("no Valkyrie Helm: fly", locked.kind, "direct")
    check("reason: the helm", locked.reason and locked.reason:find("needs Valkyrie Helm", 1, true) ~= nil, locked.reason)

    wear("Valkyrie Helm")
    Pads.reset()
    local plan = Router.plan(CASTLE, goal, 300)
    eq("with the helm: through the door", plan.kind, "pad")
    eq("the Castle to Hydra door", plan.name, "Castle to Hydra")
    near("fly to where the door is", plan.dock, toHydra.stand)
    check("faster than flying", plan.eta < plan.flyTime)

    eq("closer than the teleport distance: fly", Router.plan(goal + Vector3.new(0, 0, 1500), goal).kind, "direct")
    local saves = Router.plan(goal + Vector3.new(0, 0, -4000), goal)
    eq("a door that saves too little: fly", saves.kind, "direct")

    local fromMansion = door("Mansion to Castle").stand + Vector3.new(50, 0, 0)
    local chained = Router.plan(fromMansion, goal, 300)
    eq("two doors in a row", chained.chain and #chained.chain, 2)
    eq("first the Mansion door", chained.chain and chained.chain[1].name, "Mansion to Castle")
    eq("then the Hydra door", chained.chain and chained.chain[2].name, "Castle to Hydra")

    world.hrp.Position = CASTLE
    local text = Router.routeText(goal)
    check("show route", text:find("pad via Castle to Hydra", 1, true) ~= nil and text:find("then fly", 1, true) ~= nil, text)
end

-- Using a door: fly to it, stand on it, call it until it sends you on.
setup()
do
    game.PlaceId = SEA3
    wear("Valkyrie Helm")
    local toHydra = door("Castle to Hydra")
    local goal = toHydra.dest + Vector3.new(300, 0, 0)
    local seen = {}
    world.commF.OnInvoke = function(action, where)
        if action == "requestEntrance" then
            seen[#seen + 1] = { where = where, at = world.hrp.Position }
            if #seen == 3 then world.hrp.Position = toHydra.dest end
        end
    end
    local handled, aim = Router.update(CASTLE, goal, 300)
    check("first fly to the door", not handled and aim ~= nil and (aim - toHydra.stand).Magnitude < 1)
    world.hrp.Position = toHydra.stand + Vector3.new(2, 0, 0)
    check("at the door: the door is used", Router.update(world.hrp.Position, goal, 300))
    world.hrp.Position = toHydra.stand + Vector3.new(10, 0, 0)
    for _ = 1, 30 do stepTasks() end
    check("done", not Router.busy())
    eq("called until it sent us on", #seen, 3)
    check("asked for the door's destination", seen[1].where == toHydra.dest)
    near("held on the door while calling", seen[2].at, toHydra.stand)
    check("door works", Router.describe():find("Castle to Hydra: works", 1, true) ~= nil, Router.describe())
    check("travel log", Router.logText():find("Castle to Hydra: sent on after 3 calls", 1, true) ~= nil, Router.logText())
end

-- A door that does not open is paused; so is one used twice in a row, and
-- one that cannot be reached.
setup()
do
    game.PlaceId = SEA3
    wear("Valkyrie Helm")
    Router.COOLDOWN = 0
    local toHydra = door("Castle to Hydra")
    local goal = toHydra.dest + Vector3.new(300, 0, 0)
    world.commF.OnInvoke = function() return nil end
    Router.PAD_TIME = 0.5
    world.hrp.Position = toHydra.stand
    check("door used", Router.update(toHydra.stand, goal, 300))
    for _ = 1, 20 do stepTasks() end
    check("not opened: paused", Router.describe():find("Castle to Hydra: paused", 1, true) ~= nil, Router.describe())
    check("why", Router.describe():find("did not open after 2 calls", 1, true) ~= nil, Router.describe())
    eq("paused: no route through it", Router.plan(CASTLE, goal).kind, "direct")
    Router.clearPauses()
    eq("cleared: the door again", Router.plan(CASTLE, goal).kind, "pad")
    Router.PAD_TIME = 8

    -- Used twice in a row (each time it worked).
    world.commF.OnInvoke = function(action)
        if action == "requestEntrance" then world.hrp.Position = toHydra.dest end
    end
    for _ = 1, 2 do
        Router.update(CASTLE, goal, 300)   -- a flying frame (also the one after a jump)
        world.hrp.Position = toHydra.stand
        check("door used again", Router.update(toHydra.stand, goal, 300))
        for _ = 1, 30 do stepTasks() end
    end
    local again = Router.plan(CASTLE, goal)
    eq("twice in a row: flying instead", again.kind, "direct")
    check("logged", Router.logText():find("used twice in a row", 1, true) ~= nil, Router.logText())

    -- Cannot be reached.
    Router.clearPauses()
    Router.PAD_STUCK = 0
    Router.update(CASTLE, goal, 300)   -- the flying frame after the last jump
    Router.update(CASTLE, goal, 300)   -- heading for the door
    Router.update(CASTLE, goal, 300)   -- no closer
    check("no progress toward the door: paused", Router.describe():find("could not reach the door", 1, true) ~= nil,
        Router.describe())
    Router.PAD_STUCK = 10
    Router.COOLDOWN = 4
end

-- The Castle <-> Tiki door works by touching its tagged hitbox.
setup()
do
    game.PlaceId = SEA3
    wear("Feathered Visage")
    local fromTiki = door("Tiki to Castle")
    local teleporter = newInstance("Model", "MapTeleportC", folder("TikiOutpost", folder("Map", workspace)))
    local hitbox = part("Hitbox", fromTiki.stand, teleporter)
    local goal = CASTLE + Vector3.new(0, 0, -200)
    eq("door not open (untagged): no route", Router.plan(fromTiki.stand + Vector3.new(30, 0, 0), goal).kind, "direct")
    game:GetService("CollectionService"):AddTag(teleporter, "BoatCastleTeleporter")
    Pads.reset()
    local plan = Router.plan(fromTiki.stand + Vector3.new(30, 0, 0), goal, 300)
    eq("tagged: through the Tiki door", plan.name, "Tiki to Castle")
    local touched = {}
    firetouchinterest = function(_, target, state)
        touched[#touched + 1] = target
        if state == 1 then world.hrp.Position = fromTiki.dest end
    end
    world.hrp.Position = fromTiki.stand
    Router.update(fromTiki.stand, goal, 300)
    for _ = 1, 30 do stepTasks() end
    eq("the hitbox touched", touched[1], hitbox)
    eq("no requestEntrance for a touch door", #calls(world.commF, "requestEntrance"), 0)
    check("sent on", Router.describe():find("Tiki to Castle: works", 1, true) ~= nil, Router.describe())
    firetouchinterest = nil
end

-- Into the Temple of Time through the Mysterious Force.
setup()
do
    game.PlaceId = SEA3
    local npc = newInstance("Model", "Mysterious Force", folder("NPCs", workspace))
    part("HumanoidRootPart", Vector3.new(100, 0, 0), npc)
    local temple = newInstance("Model", "Temple of Time", folder("MapStash", rs))
    local map = folder("Map", workspace)
    local progress = 0
    world.commF.OnInvoke = function(action, step)
        if action == "RaceV4Progress" and step == "Check" then return progress end
        if action == "RaceV4Progress" and step == "Teleport" then world.hrp.Position = Router.TEMPLE end
    end
    local goal = Router.TEMPLE + Vector3.new(100, 0, 0)
    local locked = Router.plan(Vector3.new(0, 0, 0), goal)
    check("locked temple explained", locked.reason and locked.reason:find("Temple of Time locked", 1, true) ~= nil,
        locked.reason)
    progress = 1
    Router.reset()
    local plan = Router.plan(Vector3.new(0, 0, 0), goal)
    eq("through the Mysterious Force", plan.kind, "templeIn")
    near("by the NPC", plan.dock, Vector3.new(100, 0, 4))
    world.hrp.Position = plan.dock
    check("at the NPC: entrance taken", Router.update(plan.dock, goal, 300))
    for _ = 1, 10 do stepTasks() end
    local steps = {}
    for _, call in ipairs(calls(world.commF, "RaceV4Progress")) do steps[#steps + 1] = call[2] end
    check("Begin, then Teleport", table.concat(steps, ","):find("Begin,Teleport", 1, true) ~= nil, table.concat(steps, ","))
    eq("temple borrowed into the map", temple.Parent, map)
end

-- The travel log keeps the last LOG_SIZE events.
setup()
do
    for index = 1, Router.LOG_SIZE + 5 do Router.log("event " .. index) end
    local text = Router.logText()
    check("oldest dropped", text:find("event 5\n", 1, true) == nil and text:find("event 6", 1, true) ~= nil, text)
    check("newest kept", text:find("event " .. (Router.LOG_SIZE + 5), 1, true) ~= nil)
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
    local origin = folder("_WorldOrigin", workspace)
    local locations = folder("Locations", origin)
    part("Far Island", Vector3.new(20000, 0, 0), locations).Size = Vector3.new(2000, 10, 2000)
    part("Home", Vector3.new(0, 0, 0), locations).Size = Vector3.new(2000, 10, 2000)
    local group = folder("Pirates", folder("PlayerSpawns", origin))
    newInstance("Model", "FarSpawn", group).WorldPivot = CFrame.new(20100, 0, 0)
    newInstance("Model", "HomeSpawn", group).WorldPivot = CFrame.new(50, 0, 0)
    local goal = Vector3.new(20200, 0, 0)
    Settings.set("ResetTeleport", false)
    local off = Router.plan(Vector3.new(0, 0, 0), goal)
    eq("off: fly", off.kind, "direct")
    check("reason: off", off.reason and off.reason:find("reset teleport off", 1, true) ~= nil, off.reason)
    Settings.set("ResetTeleport", true)
    local plan = Router.plan(Vector3.new(0, 0, 0), goal)
    eq("reset teleport on by default", plan.kind, "respawn")
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

-- Reset teleport never while holding what death would lose, nor in a raid.
setup()
do
    game.PlaceId = SEA3
    local origin = folder("_WorldOrigin", workspace)
    local locations = folder("Locations", origin)
    part("Far Island", Vector3.new(20000, 0, 0), locations).Size = Vector3.new(2000, 10, 2000)
    part("Home", Vector3.new(0, 0, 0), locations).Size = Vector3.new(2000, 10, 2000)
    local group = folder("Pirates", folder("PlayerSpawns", origin))
    newInstance("Model", "FarSpawn", group).WorldPivot = CFrame.new(20100, 0, 0)
    local goal = Vector3.new(20200, 0, 0)
    eq("nothing held: reset", Router.plan(Vector3.new(0, 0, 0), goal).kind, "respawn")
    local chalice = newInstance("Tool", "God's Chalice", world.player.Backpack)
    local held = Router.plan(Vector3.new(0, 0, 0), goal)
    eq("holding a Chalice: fly", held.kind, "direct")
    check("reason names it", held.reason and held.reason:find("holding God's Chalice", 1, true) ~= nil, held.reason)
    check("panel names it", Router.describe():find("skipped now: holding God's Chalice", 1, true) ~= nil)
    chalice.Parent = nil
    local fruit = newInstance("Tool", "Kilo Fruit", world.character)
    check("unstored fruit protected", (Router.resetBlocked() or ""):find("Kilo Fruit", 1, true) ~= nil)
    fruit.Parent = nil
    newInstance("Tool", "Red Key", world.player.Backpack)
    eq("Red Key protected in Sea 3", Router.resetBlocked(), "holding Red Key")
    world.player.Backpack:FindFirstChild("Red Key").Parent = nil
    world.hrp.Position = Router.ISLAND
    eq("not on the Submerged Island", Router.resetBlocked(), "on the Submerged Island")
    world.hrp.Position = Vector3.new(0, 0, 0)
    eq("free again", Router.resetBlocked(), nil)
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

-- The light way: only the place a farm looks in, paced.
setup()
do
    workspace.CurrentCamera = newInstance("Camera", "Camera")
    local remotes = rs:FindFirstChild("Remotes") or newInstance("Folder", "Remotes", rs)
    local stream = newInstance("RemoteEvent", "RequestStreamAroundAsync", remotes)
    local island = newInstance("Model", "Skylands", workspace)
    island:SetAttribute("LevelOfDetailDiameter", 1000)
    part("Base", Vector3.new(-4200, 1000, -500), island)
    island.WorldPivot = CFrame.new(-4200, 1000, -500)
    check("focus: asked", IslandLoader.focus(Vector3.new(-4227, 1088, -567)))
    local fired = stream.Fired and stream.Fired[1]
    local request = fired and fired[1] and fired[1][1]
    check("focus: the server streams the place", request ~= nil and (request.cf.Position - Vector3.new(-4227, 1088, -567)).Magnitude < 1)
    local point = workspace.CurrentCamera:FindFirstChild("StrawberryFocusPoint")
    check("focus: one LoD point on that island", point ~= nil and (point.Position - Vector3.new(-4200, 1000, -500)).Magnitude < 1)
    eq("focus: not again right away", IslandLoader.focus(Vector3.new(-4230, 1090, -560)), false)
    IslandLoader.destroy()
    eq("focus: point removed on unload", workspace.CurrentCamera:FindFirstChild("StrawberryFocusPoint"), nil)
end

-- Sea 3 submarine, both ways.
setup()
do
    game.PlaceId = SEA3
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

-- Sea 1 entrances, Teddy's way: called from anywhere, no door to reach.
setup()
do
    game.PlaceId = 2753915549
    local town = Vector3.new(-655, 7, 1436)
    local city = Vector3.new(61100, 12, 1800)
    eq("to the Underwater City: entrance", Router.plan(town, city).name, "Underwater City entrance")
    eq("out of the Underwater City: exit", Router.plan(city, town).name, "Underwater City exit")
    eq("inside the city: fly", Router.plan(city, city + Vector3.new(0, 0, 1000)).kind, "direct")
    check("to the Upper Sky: no entrance (flies)", Router.plan(town, Vector3.new(-7894, 5545, -380)).kind ~= "entrance")
    eq("to the Sky: entrance", Router.plan(town, Vector3.new(-4607, 872, -1667)).name, "Sky entrance")
    eq("on the ground: no entrance", Router.plan(town, Vector3.new(-1100, 10, 3800)).kind ~= "entrance", true)
    eq("already in the Sky: fly", Router.plan(Vector3.new(-4970, 717, -2622), Vector3.new(-4607, 872, -1667)).kind,
        "direct")

    local asked
    world.commF.OnInvoke = function(name, dest)
        if name == "requestEntrance" then
            asked = dest
            world.hrp.Position = dest   -- the server moves the character
        end
        return true
    end
    check("entrance taken at once", Router.update(town, city))
    stepTasks()
    check("requestEntrance called with the city", asked ~= nil and (asked - Router.ENTRANCES[1].dest).Magnitude < 1)
    for _ = 1, 8 do stepTasks() end
    eq("moved by the server and kept there: arrived", Router.lastTrip(), "Underwater City entrance")

    -- The server does not move the character: paused, fly instead.
    world.commF.OnInvoke = function() return nil end
    Router.reset()
    world.hrp.Position = town
    Router.update(town, Vector3.new(-4607, 872, -1667))
    for _ = 1, 8 do
        stepTasks()
        world.hrp.Position = town
    end
    eq("put back: says so", Router.lastTrip(), "Sky entrance put back")
    check("put back: not tried again", Router.plan(town, Vector3.new(-4607, 872, -1667)).kind ~= "entrance")
    eq("already on the Upper Skylands: fly", Router.plan(Vector3.new(-7800, 5550, -300), Vector3.new(-7894, 5545, -380)).kind,
        "direct")
end

-- Leaving the Temple of Time uses the game's way back.
setup()
do
    game.PlaceId = SEA3
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

-- Teleporting to chests: a reset every N chests, not while holding a Chalice.
setup()
do
    local ChestHunt = require("Features.ChestHunt")
    local hunt = ChestHunt.new()
    local chests = {}
    for index = 1, 3 do chests[index] = part("Chest" .. index, Vector3.new(index * 50, 0, 0), workspace) end
    local collection = game:GetService("CollectionService")
    local getTagged = collection.GetTagged
    collection.GetTagged = function() return chests end
    Settings.set("ChestResetEvery", 2)
    hunt:step(true)
    eq("first chest: no reset", world.humanoid.Health > 0, true)
    hunt.current:SetAttribute("IsDisabled", true)
    local chalice = newInstance("Tool", "God's Chalice", world.player.Backpack)
    hunt:step(true)
    check("two chests but holding a Chalice: no reset", world.humanoid.Health > 0)
    chalice.Parent = nil
    hunt:step(true)
    eq("two chests: reset", world.humanoid.Health, 0)
    eq("count starts again", hunt.sinceReset, 0)
    collection.GetTagged = getTagged
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

-- Bartilo's quest held: read from the game's quest data (the panel's
-- title path is not always there), the Swan Pirates are farmed.
stackSetup(4442272183, 1500)
do
    world.guide.Data.QuestData = { Task = { ["Swan Pirate"] = 50 } }
    local Common = require("Features.Stack.Common")
    check("questHas: from the quest data", Common.questHas("Swan Pirate", 50))
    check("questHas: not another count", not Common.questHas("Swan Pirate", 8))
    world.commF.OnInvoke = function(action, arg)
        if action == "BartiloQuestProgress" then return 0 end
    end
    local World = require("Features.Stack.World")
    local mode = {}
    local status = World.bartilo(mode, 0)
    check("bartilo: farms the Swan Pirates", status:find("taking the quest", 1, true) == nil, status)
    eq("bartilo: no StartQuest", #calls(world.commF, "StartQuest"), 0)
end

-- Server answers are cached, not asked every frame.
stackSetup(2753915549, 800)   -- Sea 1, level 800
do
    Settings.set("StackNewWorld", true)
    local progress = {}
    world.commF.OnInvoke = function(action, arg)
        if action == "DressrosaQuestProgress" and arg == nil then return progress end
    end
    for _ = 1, 10 do StackFarm.enabled() end
    eq("quest progress asked once", #calls(world.commF, "DressrosaQuestProgress"), 1)
    StackFarm.tick()
    check("no key yet: detective", StackFarm.status:find("detective", 1, true) ~= nil, StackFarm.status)

    local door = part("Door", Vector3.new(500, 0, 0), folder("Ice", folder("Map", workspace)))
    door.CanCollide = false
    require("Features.Stack.Common").forget()
    StackFarm.tick()
    check("door open: to the admiral's room", StackFarm.status:find("Ice Admiral", 1, true) ~= nil, StackFarm.status)

    -- At the room, no admiral: the farm goes on, the room is not revisited at once.
    local World = require("Features.Stack.World")
    world.hrp.Position = World.ADMIRAL_ROOM
    require("Features.Stack.Common").forget()
    check("empty room: New World waits", not World.newWorld.want())
    world.hrp.Position = Vector3.new(0, 0, 0)
    check("empty room: still waits away from it", not World.newWorld.want())
    World.resetNewWorld()

    progress = { KilledIceBoss = true }
    require("Features.Stack.Common").forget()
    StackFarm.tick()
    eq("admiral dead: travels to Sea 2", StackFarm.status, "New World: Travelling to Sea 2")
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

-- Server scout: each event once per server, to the user's own URL only.
otherSetup()
do
    local Scout = require("Features.Scout")
    Scout.reset()
    local posts = {}
    request = function(options) posts[#posts + 1] = options end
    local http = game:GetService("HttpService")
    local bodies = {}
    http.JSONEncode = function(_, value) bodies[#bodies + 1] = value return "json" end
    game.JobId = "job-scout"
    game.PlaceId = 7449423635
    Settings.set("WebhookScout", true)
    mob("Dough King", Vector3.new(0, 0, 0))
    newInstance("Tool", "Kilo Fruit", workspace)
    world.commF.OnInvoke = function(action)
        if action == "ColorsDealer" then return "Snow White 2500000" end
        if action == "LegendarySwordDealer" then return "Katana 1000" end
    end
    eq("no URL: nothing", Scout.step(), 0)
    Settings.set("WebhookUrl", "https://discord.test/hook")
    local count = Scout.step()
    local events = {}
    for _, body in ipairs(bodies) do events[#events + 1] = body.embeds[1].description end
    local text = table.concat(events, " / ")
    eq("three events found", count, 3)
    check("rare boss reported", text:find("Rare Bosses: Dough King", 1, true) ~= nil, text)
    check("fruit reported", text:find("Fruit Spawn: Kilo Fruit", 1, true) ~= nil, text)
    check("legendary haki read without its price", text:find("Legendary Haki: Snow White", 1, true) ~= nil, text)
    check("ordinary sword ignored", text:find("Katana", 1, true) == nil, text)
    eq("sent to the user's URL", posts[1] and posts[1].Url, "https://discord.test/hook")
    local join = bodies[1].embeds[1].fields[5].value
    check("join line with the JobId", join:find("job-scout", 1, true) ~= nil, join)
    eq("once per server", Scout.step(), 0)
    game.JobId = "job-other"
    eq("again in another server", Scout.step(), 3)
    Settings.set("WebhookScoutEvents", { ["Fruit Spawn"] = true })
    game.JobId = "job-third"
    eq("only the chosen events", Scout.step(), 1)

    local enemies = workspace:FindFirstChild("Enemies") or folder("Enemies", workspace)
    local pirate = newInstance("Model", "Pirate", enemies)
    pirate:SetAttribute("Level", 1200)
    pirate.WorldPivot = CFrame.new(Scout.CASTLE + Vector3.new(100, 0, 0))
    check("castle raid seen", Scout.castleRaid())
    request = nil
    game.JobId = ""
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

    -- Pressed: the next ticks wait for the raid, nothing else.
    Raids.multi.tick()
    eq("pressed: waits for the raid to start", Raids.multi.status, "Waiting for the raid to start")
    check("pressed: the raid counts as active", Raids.active())
    Raids.reset()

    -- A slot taker goes to the free slot.
    Settings.set("MultiRaidBuyer", false)
    Settings.set("MultiRaidSlot", true)
    Raids.multi.tick()
    check("slot taker heads for the slot", Raids.multi.status:find("Taking a raid slot", 1, true) ~= nil, Raids.multi.status)
end

-- In a raid: the timer alone is enough (the islands load later); the
-- nearest island not cleared, then the next one.
batchBSetup()
do
    Raids.reset()
    local hud = folder("TopHUDList", world.player.PlayerGui.Main)
    local timer = newInstance("Frame", "RaidTimer", hud)
    timer.Visible = true
    check("raid: timer only -> in a raid", Raids.inRaid())
    local mode = {}
    Raids.fight(mode)
    eq("raid: no island yet -> waits", mode.status or Raids.fight(mode), "Raid: waiting for the next island")
    local locations = folder("Locations", folder("_WorldOrigin", workspace))
    local one = part("Island 1", Vector3.new(0, 0, 100), locations)
    part("Island 2", Vector3.new(0, 0, 900), locations)
    eq("raid: nearest island first", Raids.fight(mode), "Raid: going to island 1")
    world.hrp.Position = one.Position + Vector3.new(0, 60, 0)
    local empty = Raids.ISLAND_EMPTY
    Raids.ISLAND_EMPTY = -1
    Raids.fight(mode)
    Raids.ISLAND_EMPTY = empty
    eq("raid: cleared island -> the next one", Raids.fight(mode), "Raid: going to island 2")

    -- Kill aura on the last island only.
    local function killable(at)
        local enemy = mob("Raid Mob", at)
        enemy.Humanoid.ChangeState = function(self, state) self.Killed = state end
        return enemy
    end
    local three = part("Island 3", Vector3.new(5000, 0, 0), locations)
    world.hrp.Position = three.Position
    local early = killable(three.Position + Vector3.new(0, 0, 20))
    Raids.fight(mode)
    eq("kill aura: not on island 3", early.Humanoid.Killed, nil)
    early.Parent = nil
    local five = part("Island 5", Vector3.new(9000, 0, 0), locations)
    world.hrp.Position = five.Position
    check("last island seen", Raids.lastIsland())
    local late = killable(five.Position + Vector3.new(0, 0, 20))
    Raids.reset()
    check("kill aura: status says so", Raids.fight(mode):find("kill aura", 1, true) ~= nil)
    check("kill aura: killed on island 5", late.Humanoid.Killed ~= nil)
    timer.Visible = false
    Raids.reset()
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
    check("goes to the Alchemist first", RaceUpgrade.v2v3.status:find("Alchemist's quest", 1, true) ~= nil,
        RaceUpgrade.v2v3.status)
    world.hrp.Position = RaceUpgrade.ALCHEMIST_TURN_IN
    RaceUpgrade.v2v3.tick()
    local asked = false
    for _, call in ipairs(calls(world.commF, "Alchemist")) do
        if call[2] == "2" then asked = true end
    end
    check("Alchemist quest taken", asked, RaceUpgrade.v2v3.status)
end

-- V3 done: the mode lets the next farm run.
-- The Colosseum Quest (Bartilo) comes before the Alchemist.
raceSetup(4442272183, "Human", { Wenlocktoad = 0, BartiloQuestProgress = 0 })
do
    newInstance("IntValue", "Beli", world.player.Data).Value = 600000
    Settings.set("RaceV2V3", true)
    RaceUpgrade.v2v3.tick()
    check("colosseum first", RaceUpgrade.v2v3.status:find("Colosseum quest first", 1, true) ~= nil,
        RaceUpgrade.v2v3.status)
end

-- The Alchemist answering nothing at all (v30): V2 is left alone a while.
raceSetup(4442272183, "Human", { Wenlocktoad = 0, BartiloQuestProgress = 3 })
do
    newInstance("IntValue", "Beli", world.player.Data).Value = 600000
    Settings.set("RaceV2V3", true)
    world.hrp.Position = RaceUpgrade.ALCHEMIST_TURN_IN
    local ask = require("Features.Stack.Common")
    for _ = 1, RaceUpgrade.NIL_TRIES do
        ask.reset()
        RaceUpgrade.v2v3.tick()
    end
    check("nil answers: V2 paused", RaceUpgrade.v2Paused(), RaceUpgrade.v2v3.status)
    check("nil answers: mode off", not RaceUpgrade.v2v3.enabled())
    RaceUpgrade.v2PausedUntil = nil
end

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
-- Batch F: the remaining Banana features
---------------------------------------------------------------------------

local TyrantFarm = require("Features.TyrantFarm")
local BoneFarmModule = require("Features.BoneFarm")
local KatakuriFarmModule = require("Features.KatakuriFarm")
local Helpers = require("Features.Helpers")
local SafeSpot = require("Features.SafeSpot")

local function batchFSetup(place, level)
    itemsSetup(place or 7449423635, level or 2500, {}, {})
    Helpers.reset()
    Boat.reset()
    SeaEvents.reset()
end

-- Tyrant of the Skies: the arena trees once the eyes are lit, then the boss.
batchFSetup()
do
    Settings.set("AutoTyrant", true)
    local island = folder("IslandModel", folder("TikiOutpost", folder("Map", workspace)))
    for index = 1, 4 do part("Eye" .. index, Vector3.new(index, 0, 0), island).Transparency = 0 end
    local tree = newInstance("Model", "Tree", folder("EagleBossArena", island))
    tree.WorldPivot = CFrame.new(300, 20, 0)
    TyrantFarm.tick()
    eq("eyes lit: breaking the trees", TyrantFarm.status, "Breaking the arena trees")
    near("to the tree", Movement.goal().Position, Vector3.new(300, 20, 0))
    island.Eye2.Transparency = 1
    TyrantFarm.tick()
    check("an eye out: back to the mobs", TyrantFarm.status ~= "Breaking the arena trees", TyrantFarm.status)
    local boss = mob("Tyrant of the Skies", Vector3.new(50, 0, 0))
    TyrantFarm.tick()
    eq("the Tyrant first", TyrantFarm.target, boss)
end

-- The special farms take their quest first.
batchFSetup(nil, 2100)
do
    Settings.set("AutoBone", true)
    Settings.set("FarmSpecialQuest", true)
    world.guide.Data.NPCList.haunted = {
        NPCName = "Haunted Giver", InternalQuestName = "HauntedQuest2",
        Levels = { 2000, 2050 }, Position = CFrame.new(3000, 10, 0),
    }
    BoneFarmModule.tick()
    check("goes for the quest", BoneFarmModule.status:find("Taking the quest", 1, true) ~= nil, BoneFarmModule.status)
    near("to its giver", Movement.goal().Position, Vector3.new(3000, 14, 2))
    world.hrp.Position = Vector3.new(3000, 14, 2)
    BoneFarmModule.tick()
    local started = calls(world.commF, "StartQuest")[1]
    eq("quest asked", started and (started[2] .. "#" .. started[3]), "HauntedQuest2#2")
    world.questPanel.Visible = true
    BoneFarmModule.tick()
    check("quest shown: farming", BoneFarmModule.status:find("Taking the quest", 1, true) == nil, BoneFarmModule.status)
end

-- Hop to find Cake Prince.
batchFSetup()
do
    Settings.set("AutoKatakuri", true)
    Settings.set("HopKatakuri", true)
    StackCommon.HOP_AFTER = 0
    local hops = 0
    local realHop = ServerModule.hop
    ServerModule.hop = function() hops = hops + 1 return true end
    KatakuriFarmModule.tick()
    eq("no Cake Prince: hop", hops, 1)
    ServerModule.hop = realHop
    StackCommon.HOP_AFTER = 15
end

-- Movement lifts the goal: low HP escape, mob skill dodge.
batchFSetup()
do
    Movement.liftProvider = Helpers.lift
    Settings.set("LowHpEscape", true)
    Settings.set("LowHpHeight", 100)
    world.humanoid.MaxHealth = 100
    world.humanoid.Health = 30
    Helpers.updateHealth()
    eq("low HP: lifted", Helpers.lift(), 100)
    Movement.to(CFrame.new(0, 0, 20))
    Movement.step(1 / 60)
    near("goal lifted", world.hrp.Position, Vector3.new(0, 100, 20))
    world.humanoid.Health = 60
    Helpers.updateHealth()
    eq("between the two limits: still lifted", Helpers.lift(), 100)
    world.humanoid.Health = 90
    Helpers.updateHealth()
    eq("recovered: back down", Helpers.lift(), 0)

    -- Against a boss the escape stays close (it reset when left far).
    Settings.set("LowHpHeight", 800)
    local admiral = mob("Ice Admiral", Vector3.new(0, 0, 500))
    local realBossTarget = Farm.target
    Farm.target = function() return admiral end
    world.humanoid.Health = 30
    Helpers.updateHealth()
    eq("boss: low HP escape capped", Helpers.lift(), Helpers.BOSS_ESCAPE)
    Farm.target = function() return nil end
    eq("no boss: the full height", Helpers.lift(), 800)
    Farm.target = realBossTarget
    world.humanoid.Health = 90
    Helpers.updateHealth()
    Settings.set("LowHpHeight", 100)
    admiral.Parent = nil

    local target = mob("Magma Admiral", Vector3.new(0, 0, 30))
    local realTarget = Farm.target
    Farm.target = function() return target end
    local cast = newInstance("BodyGyro", "BodyGyro", target.HumanoidRootPart)
    Helpers.onEnemyDescendant(cast)
    eq("dodge off: no lift", Helpers.lift(), 0)
    Settings.set("DodgeSkills", true)
    Helpers.onEnemyDescendant(cast)
    eq("mob casting: 200 studs up", Helpers.lift(), 200)

    -- Raids only: off outside a raid, on inside one.
    Settings.set("DodgeSkills", false)
    Helpers.reset()
    Helpers.onEnemyDescendant(cast)
    eq("raid dodge: not outside a raid", Helpers.lift(), 0)
    local raidTimer = newInstance("Frame", "RaidTimer", folder("TopHUDList", world.player.PlayerGui.Main))
    raidTimer.Visible = true
    Helpers.onEnemyDescendant(cast)
    eq("raid dodge: in a raid", Helpers.lift(), 200)
    raidTimer.Visible = false
    Farm.target = realTarget
    Movement.liftProvider = nil
    Movement.stop()
end

-- Dark Step's Overheat (V) is used as soon as it is ready, next to the mob.
setup()
do
    local pressed = {}
    local vim = game:GetService("VirtualInputManager")
    function vim:SendKeyEvent(down, key) if down then pressed[#pressed + 1] = key end end
    local tool = newInstance("Tool", "Dark Step", world.player.Backpack)
    tool.ToolTip = "Melee"
    local skills = newInstance("Frame", "Skills", world.player.PlayerGui.Main)
    local bar = newInstance("Frame", "Dark Step", skills)
    local frame = newInstance("Frame", "V", bar)
    newInstance("TextLabel", "Title", frame).TextColor3 = Color3.new(1, 1, 1)
    local cooldown = newInstance("Frame", "Cooldown", frame)
    cooldown.Size = UDim2.new(0.5, 0, 1, -1)
    local target = mob("Zombie", Vector3.new(0, 0, 0))
    local Fight = require("Features.Fight")
    Mastery.reset()
    Fight.engage({}, target)
    eq("overheat on cooldown: not pressed", #pressed, 0)
    cooldown.Size = UDim2.new(0, 0, 1, -1)
    Mastery.reset()
    Fight.engage({}, target)
    eq("overheat ready: V pressed", pressed[1], "V")
    Settings.set("MeleeBuff", false)
    Mastery.reset()
    pressed = {}
    Fight.engage({}, target)
    eq("buffs off: not pressed", #pressed, 0)
    Settings.set("MeleeBuff", true)
end

-- Skills per weapon type.
batchFSetup()
do
    local melee = newInstance("Tool", "Godhuman", world.player.Backpack)
    melee.ToolTip = "Melee"
    local bar = newInstance("Frame", "Godhuman", newInstance("Frame", "Skills", world.player.PlayerGui.Main))
    for _, key in ipairs({ "Z", "X", "C", "V" }) do
        local frame = newInstance("Frame", key, bar)
        newInstance("TextLabel", "Title", frame).TextColor3 = Color3.new(1, 1, 1)
        newInstance("Frame", "Cooldown", frame).Size = UDim2.new(0, 0, 1, -1)
    end
    Settings.set("SkillsMelee", { X = true })
    eq("only the chosen melee key", Mastery.readySkill(melee), "X")
    Settings.set("SkillsMelee", { V = true })
    eq("V is not a melee key by default, but can be chosen", Mastery.readySkill(melee), "V")
    Settings.set("SkillHoldMelee", 1.5)
    eq("melee hold time", Mastery.holdFor(melee), 1.5)
    Settings.set("SkillFast", true)
    eq("fast: a tap", Mastery.holdFor(melee), Mastery.FAST_HOLD)
end

-- Safe spot while holding a Chalice, unless a feature needs it.
batchFSetup()
do
    Settings.set("SafeWithItems", true)
    check("nothing held: idle", not SafeSpot.mode.enabled())
    newInstance("Tool", "God's Chalice", world.player.Backpack)
    check("chalice held: on", SafeSpot.mode.enabled())
    SafeSpot.mode.tick()
    near("to the Mansion", Movement.goal().Position, SafeSpot.SPOTS[3])
    Settings.set("StackSummonRipIndra", true)
    check("rip_indra summon on: the chalice is left to it", not SafeSpot.mode.enabled())
end

-- Sea: with a friend, boat speed, rough seas, reset for the boat.
batchFSetup()
do
    Settings.set("SeaAuto", true)
    Settings.set("SeaFriend", true)
    Settings.set("SeaFriendName", "Buddy")
    SeaEvents.auto.tick()
    check("friend missing", SeaEvents.auto.status:find("not in this server", 1, true) ~= nil, SeaEvents.auto.status)
    local buddy = newInstance("Player", "Buddy", players)
    local body = newInstance("Model", "Buddy", workspace)
    part("HumanoidRootPart", Vector3.new(500, 0, 500), body)
    buddy.Character = body
    SeaEvents.auto.tick()
    eq("with the friend", SeaEvents.auto.status, "With Buddy")
    near("flies to the friend", Movement.goal().Position, Vector3.new(500, 0, 500))

    Settings.set("SeaBoatMaxSpeed", true)
    local _, seat = makeBoat(Vector3.new(0, 0, 0))
    seat.MaxSpeed = 150
    Helpers.step()
    eq("boat max speed raised", seat.MaxSpeed, 200)

    Settings.set("SeaRoughSea", true)
    local origin = folder("_WorldOrigin", workspace)
    part("RainEmitterPart", Vector3.new(0, 0, 0), origin).Size = Vector3.new(50, 50, 50)
    part("Rough Sea", Vector3.new(100, 0, 0), folder("Locations", origin))
    local zone = Boat.ZONES["Zone 1"]
    near("rough sea near in the rain: zone moved", SeaEvents.spot(), zone + Vector3.new(0, 0, 7000))
    near("the same rough sea counts once", SeaEvents.spot(), zone + Vector3.new(0, 0, 7000))
end
batchFSetup()
do
    Settings.set("SeaResetForBoat", true)
    newInstance("StringValue", "LastSpawnPoint", world.player.Data).Value = "Tiki"
    local status = select(2, Boat.get())
    eq("spawn at Tiki: reset instead of flying", status, "Respawning at Tiki Outpost for the boat")
    eq("character reset", world.humanoid.Health, 0)
end

-- Races: training before the trial, skills on players.
raceSetup(7449423635, "Mink", { UpgradeRace = function(what) if what == "Check" then return 1, 0, 0 end end })
do
    newInstance("BoolValue", "RaceTransformed", world.character)
    Settings.set("RaceTrial", true)
    check("trial on", RaceV4.trial.enabled())
    Settings.set("RaceTrain", true)
    Settings.set("RaceTrainFirst", true)
    check("training asked: the trial waits", not RaceV4.trial.enabled())
    eq("status says why", RaceV4.trial.status, "Training first")

    local enemy = newInstance("Player", "Enemy", players)
    local body = newInstance("Model", "Enemy", workspace)
    newInstance("Humanoid", "Humanoid", body).Health = 100
    part("HumanoidRootPart", Vector3.new(10, 0, 0), body)
    enemy.Character = body
    AimHook.target = nil
    Duel.fight({}, enemy, "Melee", false)
    eq("no skills when off", AimHook.target, nil)
    Duel.fight({}, enemy, "Melee", true)
    check("skills when on", AimHook.target ~= nil)
    AimHook.target = nil
end

-- Spam join: the join again every half second while it is on.
batchFSetup()
do
    local browser = newInstance("RemoteFunction", "__ServerBrowser", rs)
    browser.OnInvoke = function() return true end
    check("off: no repeat", not ServerModule.spamJoin("job-1"))
    Settings.set("JoinSpam", true)
    check("on: repeating", ServerModule.spamJoin("job-1"))
    for _ = 1, 3 do stepTasks() end
    eq("asked again and again", #(browser.Invoked or {}), 3)
    Settings.set("JoinSpam", false)
    stepTasks()
    stepTasks()
    eq("stops when turned off", #(browser.Invoked or {}), 3)
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
-- Kaitun: config, layers, task choice, watchdog
---------------------------------------------------------------------------

local KConfig = require("Kaitun.Config")
local KEngine = require("Kaitun.Engine")
local KTasks = require("Kaitun.Tasks")

local function kaitunSetup(place, level, inventory, answers)
    itemsSetup(place, level, inventory, answers)
    KConfig.reset()
    KEngine.reset()
end

do
    local merged = KConfig.merge({ Team = "Marines", Speed = "fast", Skip = { CDK = true }, Extra = 1 })
    eq("config: string kept", merged.Team, "Marines")
    eq("config: wrong type falls back", merged.Speed, 300)
    eq("config: skip merged key by key", merged.Skip.CDK, true)
    eq("config: other skips kept", merged.Skip.Yama, false)
    eq("config: unknown key kept", merged.Extra, 1)
    eq("config: defaults untouched", KConfig.DEFAULTS.Skip.CDK, false)
    eq("config: nil gives the defaults", KConfig.merge(nil).Team, "Pirates")
end

kaitunSetup(2753915549, 100)
do
    eq("sea 1 below 700: no New World", KEngine.background(1, 500).StackNewWorld, false)
    eq("sea 1 at 700: New World", KEngine.background(1, 700).StackNewWorld, true)
    local sea2 = KEngine.background(2, 1600)
    eq("sea 2 at 1500: Third World", sea2.StackThirdWorld, true)
    eq("sea 2: factory", sea2.StackFactory, true)
    eq("sea 2: no elite hunter", sea2.StackEliteHunter, nil)
    local sea3 = KEngine.background(3, 2000)
    eq("sea 3: elite hunter", sea3.StackEliteHunter, true)
    eq("sea 3 before the late game: no Dough King", sea3.StackDoughKing, false)
    eq("sea 3 before the late game: no rip_indra", sea3.StackRipIndra, false)
    eq("sea 3 late: Dough King", KEngine.background(3, 2500).StackDoughKing, true)
    eq("sea 3: no New World", sea3.StackNewWorld, nil)
    eq("helpers on", sea3.AutoStats, true)
    eq("no webhook without a url", sea3.WebhookUrl, nil)
    KConfig.load({ WebhookUrl = "https://example.invalid/hook" })
    eq("own webhook used", KEngine.background(3, 2000).WebhookUrl, "https://example.invalid/hook")
    KConfig.reset()

    local keys, name = KEngine.idle(2, 1000)
    eq("idle: level farm below max", keys.AutoFarmLevel, true)
    eq("idle name", name, "Level farm")
    keys, name = KEngine.idle(3, 2800)
    eq("idle: bones while Dragon Talon is locked", keys.AutoBone, true)
    eq("idle: bones name", name, "Bones (Fire Essence)")
    KConfig.load({ Skip = { Godhuman = true } })
    keys, name = KEngine.idle(3, 2800)
    eq("idle: Katakuri at max in sea 3", keys.AutoKatakuri, true)
    eq("idle: Katakuri name", name, "Katakuri")
    KConfig.reset()
    keys = KEngine.idle(2, 2800)
    eq("idle: still level farm in sea 2 at max", keys.AutoFarmLevel, true)
    eq("wanted sea by level", KEngine.wantedSea(1600), 3)
end

kaitunSetup(7449423635, 2000)
do
    local doneB = false
    local list = {
        { name = "A", priority = 5, seas = { 3 }, keys = { ItemYama = true } },
        { name = "B", priority = 1, seas = { 3 }, keys = { ItemTushita = true }, done = function() return doneB end },
        { name = "C", priority = 1, seas = { 1 }, keys = { ItemSaber = true } },
        { name = "D", priority = 0, seas = { 3 }, minLevel = 2500, keys = { ItemCDK = true } },
    }
    eq("lowest priority number in this sea wins", KEngine.pick(3, 2000, list).name, "B")
    eq("level gate", KEngine.blocked(list[4], 3, 2000), "level 2500")
    eq("sea gate", KEngine.blocked(list[3], 3, 2000), "other sea")
    local wanted, task = KEngine.desired(3, 2000, list)
    eq("desired: task chosen", task.name, "B")
    eq("desired: its key on", wanted.ItemTushita, true)
    eq("desired: other task keys off", wanted.ItemYama, false)
    eq("desired: idle stays under the task", wanted.AutoFarmLevel, true)

    KConfig.load({ Skip = { B = true } })
    eq("skipped task gives way", KEngine.pick(3, 2000, list).name, "A")
    KConfig.reset()
    doneB = true
    KEngine.reset()
    eq("done task gives way", KEngine.pick(3, 2000, list).name, "A")
    eq("ready() false blocks", KEngine.blocked({ name = "E", priority = 1, ready = function() return false end }, 3, 2000), "not ready")

    -- Real list order follows Teddy's priorities.
    local ordered = KTasks.ordered()
    eq("CDK first", ordered[1].name, "CDK")
    eq("Yama last", ordered[#ordered].name, "Yama")
end

kaitunSetup(7449423635, 2000)
do
    local saved = KTasks.LIST
    local idleMode = { name = "Fake", status = "Nothing to do", enabled = function() return false end }
    KTasks.LIST = { { name = "Lazy", priority = 1, seas = { 3 }, mode = idleMode, keys = { ItemYama = true } } }
    local limit = KEngine.IDLE_LIMIT
    KEngine.IDLE_LIMIT = 0
    KEngine.tick()
    eq("watchdog: rests a task with nothing to do", KEngine.blocked(KTasks.LIST[1], 3, 2000), "resting")
    check("watchdog: logged", (KEngine.status().log[1] or ""):find("Lazy rests", 1, true) ~= nil, KEngine.status().log[1])
    eq("watchdog: resting listed", #KEngine.status().resting, 1)
    KEngine.tick()
    eq("watchdog: key off once resting", Settings.get("ItemYama"), false)
    KEngine.IDLE_LIMIT = limit

    KEngine.reset()
    local busyMode = { name = "Busy", status = "working", enabled = function() return true end }
    KTasks.LIST = { { name = "Slow", priority = 1, seas = { 3 }, mode = busyMode, keys = { ItemYama = true }, maxTime = 0 } }
    KEngine.tick()
    eq("watchdog: rests a task past its max time", KEngine.blocked(KTasks.LIST[1], 3, 2000), "resting")
    check("watchdog: says why", (KEngine.status().log[1] or ""):find("took too long", 1, true) ~= nil)

    KEngine.reset()
    KTasks.LIST = { { name = "Work", priority = 1, seas = { 3 }, mode = busyMode, keys = { ItemYama = true } } }
    KEngine.tick()
    eq("tick: task key on", Settings.get("ItemYama"), true)
    eq("tick: idle key on", Settings.get("AutoFarmLevel"), true)
    eq("tick: background on", Settings.get("StackEliteHunter"), true)
    eq("status: current task", KEngine.status().task, "Work")
    KEngine.stop()
    eq("stop: task key back to default", Settings.get("ItemYama"), false)
    eq("stop: idle key back to default", Settings.get("AutoFarmLevel"), false)
    KTasks.LIST = saved
end

kaitunSetup(7449423635, 2000, {}, {
    getAwakenedAbilities = { { Awakened = true, Cost = 100 }, { Awakened = false, Cost = 500 } },
})
do
    local data = world.player.Data
    local fruit = newInstance("StringValue", "DevilFruit", data)
    fruit.Value = "Flame-Flame"
    local fragments = newInstance("IntValue", "Fragments", data)
    fragments.Value = 100
    eq("fruit raid from the eaten fruit", KTasks.fruitRaid(), "Flame")
    local can, all = KTasks.awakening()
    check("awakening: not affordable yet", not can)
    check("awakening: not all done", not all)
    fragments.Value = 600
    require("Features.Stack.Common").forget()
    check("awakening: affordable", (KTasks.awakening()))
    fruit.Value = "Kitsune-Kitsune"
    eq("no raid for a fruit without one", KTasks.fruitRaid(), nil)
end

---------------------------------------------------------------------------
-- Melee chain to Godhuman, Electric (Lightning Bolt)
---------------------------------------------------------------------------

local Melee = require("Features.Items.Melee")
local Electric = require("Features.Items.Electric")

local function meleeSetup(place, level, inventory, answers, beli, fragments)
    itemsSetup(place, level, inventory, answers)
    Melee.reset()
    Electric.reset()
    local data = world.player.Data
    newInstance("IntValue", "Beli", data).Value = beli or 0
    newInstance("IntValue", "Fragments", data).Value = fragments or 0
end

local function style(name, mastery)
    return { Name = name, Type = "Melee", Count = 1, Mastery = mastery }
end

meleeSetup(2753915549, 100, {}, {}, 200000)
do
    local name, state = Melee.current()
    eq("melee: first style is Black Leg", name, "Black Leg")
    eq("melee: to buy", state, "buy")
    local npc = newInstance("Model", "Dark Step Teacher", folder("NPCs", workspace))
    part("HumanoidRootPart", Vector3.new(0, 0, -4), npc)
    Settings.set("ItemMeleeProgress", true)
    check("melee mode on while something to buy", Melee.mode.enabled())
    Melee.mode.tick()
    eq("melee: bought at the teacher", #buys(world.commF, "BuyBlackLeg"), 1)
end

meleeSetup(2753915549, 100, { style("Dark Step", 150) }, {}, 200000)
do
    eq("melee: old inventory name counts as Black Leg", Melee.mastery("Black Leg"), 150)
    check("melee: owned through the alias", Melee.owned("Black Leg"))
    local action, name = Melee.action()
    eq("melee: not held -> load", action, "load")
    eq("melee: load which", name, "Black Leg")
    Settings.set("ItemMeleeProgress", true)
    Melee.mode.tick()
    local load = calls(world.commF, "LoadItem")[1]
    eq("melee: LoadItem with the inventory's name", load and load[2], "Dark Step")
    local tool = newInstance("Tool", "Dark Step", world.player.Backpack)
    tool.ToolTip = "Melee"
    eq("melee: held -> nothing for the mode", (Melee.action()), nil)
    eq("melee: describe", Melee.describe(), "Black Leg 150/400")
end

meleeSetup(2753915549, 400, { style("Dark Step", 400) }, {}, 200000)
do
    eq("melee: Electric waits on its quest", Melee.missing(Melee.step("Electro")), "the Lightning Bolt quest")
    eq("melee: Fishman waits on money", Melee.missing(Melee.step("Fishman Karate")), "$750000")
    eq("melee: Dragon Claw waits on Sea 2", Melee.missing(Melee.step("Dragon Claw")), "Sea 2")
    eq("melee: nothing buyable -> keep the best owned", (Melee.current()), "Black Leg")
end

meleeSetup(4442272183, 1200, {
    style("Dark Step", 300), style("Electric", 300), style("Water Kung Fu", 450), style("Dragon Breath", 300),
}, {}, 4000000, 2000)
do
    eq("melee: first under 400 is worked on", (Melee.current()), "Black Leg")
    local superhuman = Melee.step("Superhuman")
    eq("melee: Superhuman needs the four at 300 -- met", Melee.missing(superhuman), nil)
    eq("melee: Sharkman waits on its unlock", Melee.missing(Melee.step("Sharkman Karate")), "unlock")
    eq("melee: Death Step waits on Black Leg 400", Melee.missing(Melee.step("Death Step")), "Black Leg 400")
end

meleeSetup(4442272183, 1200, { style("Water Kung Fu", 450) }, { BuySharkmanKarate = 3 }, 4000000, 6000)
do
    check("melee: Sharkman unlocked by the check call", Melee.unlocked("Sharkman Karate"))
    eq("melee: Sharkman buyable", Melee.missing(Melee.step("Sharkman Karate")), nil)
end

meleeSetup(4442272183, 1200, { style("Water Kung Fu", 450) }, { BuySharkmanKarate = "locked" }, 4000000, 6000)
do
    eq("melee: Sharkman locked", Melee.missing(Melee.step("Sharkman Karate")), "unlock")
    Settings.set("ItemWaterKey", true)
    check("water key: nothing without the boss or the key", not Melee.waterKey.enabled())
    newInstance("Tool", "Water Key", world.player.Backpack)
    check("water key: key held", Melee.waterKey.enabled())
    Melee.waterKey.tick()
    local use = calls(world.commF, "BuySharkmanKarate")
    check("water key: used", #use >= 1 and use[#use][2] == true)
end

meleeSetup(7449423635, 2000, {
    style("Superhuman", 400), style("Death Step", 400), style("Sharkman Karate", 400),
    style("Electric Claw", 400), style("Dragon Talon", 400),
    { Name = "Fish Tail", Type = "Material", Count = 20 }, { Name = "Magma Ore", Type = "Material", Count = 3 },
}, { BuyGodhuman = 2 }, 6000000, 6000)
do
    eq("godhuman: first missing material", Melee.missingMaterial(), "Dragon Scale")
    eq("godhuman: waits on the materials", Melee.missing(Melee.step("Godhuman")), "unlock")
end

meleeSetup(7449423635, 2000, {
    style("Superhuman", 400), style("Death Step", 400), style("Sharkman Karate", 400),
    style("Electric Claw", 400), style("Dragon Talon", 400),
}, { BuyGodhuman = 0 }, 6000000, 6000)
do
    eq("godhuman: materials in -> buy it", (Melee.current()), "Godhuman")
    check("melee: first-sea style not needed any more", not Melee.useful(Melee.step("Black Leg")))
end

meleeSetup(7449423635, 2000, { { Name = "Bones", Type = "Material", Count = 80 } },
    { BuyDragonTalon = "Set your heart ablaze." })
do
    check("fire essence: Dragon Talon locked", not Melee.unlocked("Dragon Talon"))
    Settings.set("ItemDragonTalon", true)
    check("fire essence: rolls with 50+ bones", Melee.dragonTalon.enabled())
    Melee.dragonTalon.tick()
    local buys = 0
    for _, call in ipairs(calls(world.commF, "Bones")) do
        if call[2] == "Buy" then buys = buys + 1 end
    end
    eq("fire essence: bone gacha", buys, 1)
end

-- An NPC's "Interact" prompt held like a player would (v30 dialogues).
setup()
do
    local npc = newInstance("Model", "Mad Scientist", folder("NPCs", workspace))
    local root = part("HumanoidRootPart", Vector3.new(0, 0, 0), npc)
    local prompt = newInstance("ProximityPrompt", "ProximityPrompt", root)
    prompt.HoldDuration = 0
    local held = 0
    prompt.InputHoldBegin = function() held = held + 1 end
    prompt.InputHoldEnd = function() end
    check("interact: a prompt near", World.interact(Vector3.new(0, 0, 5), 15))
    stepTasks()
    eq("interact: held", held, 1)
    eq("interact: none far away", World.interact(Vector3.new(500, 0, 0), 15), false)
end

-- A remembered bolt the server denies (cloud phase): forgotten, the cloud
-- is looked for instead of "Giving the Lightning Bolt".
meleeSetup(2753915549, 300, {}, { ElectroQuestState = 1, DeliverLightningBolt = 0 }, 600000)
do
    local files = {}
    local realWrite, realRead, realIs = writefile, readfile, isfile
    writefile = function(path, text) files[path] = text end
    readfile = function(path) return files[path] end
    isfile = function(path) return files[path] ~= nil end
    Electric.reset()
    files["StrawberryHub/electric_bolt_" .. tostring(world.player.UserId or 0) .. ".txt"] = "1"
    Settings.set("ItemElectric", true)
    Electric.mode.tick()
    eq("remembered bolt, state 1: looks for the cloud", Electric.mode.status, "Looking for a charged storm cloud")
    eq("remembered bolt forgotten", files["StrawberryHub/electric_bolt_" .. tostring(world.player.UserId or 0) .. ".txt"], "0")
    writefile, readfile, isfile = realWrite, realRead, realIs
    Electric.reset()
end

-- Electric: the Lightning Bolt quest.
local electricState = 0
meleeSetup(2753915549, 300, {}, {
    ElectroQuestState = function() return electricState end,
    DeliverLightningBolt = 0,
}, 600000)
do
    local npc = newInstance("Model", "Mad Scientist", folder("NPCs", workspace))
    part("HumanoidRootPart", Vector3.new(0, 0, -4), npc)
    Settings.set("ItemElectric", true)
    check("electric: wanted with $500k", Electric.mode.enabled())
    Electric.mode.tick()
    eq("electric: quest accepted", #calls(world.commF, "AcceptElectroQuest"), 1)
    -- With the money, every visit also offers the bolt (the server's state
    -- after the cloud is not always 4), then the purchase.
    eq("electric: rich visit offers the bolt", #calls(world.commF, "DeliverLightningBolt"), 1)
    eq("electric: then BuyElectro", #buys(world.commF, "BuyElectro"), 1)

    require("Features.Stack.Common").forget()
    electricState = 1
    Electric.mode.tick()
    eq("electric: no cloud -> waits over the Skylands", Electric.mode.status, "Looking for a charged storm cloud")

    local cloud = part("StormCloud", Vector3.new(0, 0, 0), workspace)
    local piece = part("CloudPiece", Vector3.new(0, 0, 3), workspace)
    game:GetService("CollectionService"):AddTag(piece, "M1HitRegistry")
    Electric.onMoment("Some Other Moment", "Charge", cloud, piece)
    eq("electric: other moments ignored", Electric.target(), nil)
    Electric.onMoment("Electric Fighting Teacher", "Charge", cloud, piece)
    eq("electric: charged piece known", Electric.target(), piece)
    Electric.mode.tick()
    eq("electric: strike status", Electric.mode.status, "Striking the charged storm cloud")
    local swing = world.registerAttack.Fired and world.registerAttack.Fired[1]
    eq("electric: RegisterAttack 0.3", swing and swing[1], 0.3)
    local hit = world.moduleRegisterHit.Fired and world.moduleRegisterHit.Fired[1]
    eq("electric: RegisterHit on the piece", hit and hit[1], piece)
    Electric.onMoment("Electric Fighting Teacher", "Break", cloud)
    eq("electric: broken cloud forgotten", Electric.target(), nil)

    require("Features.Stack.Common").forget()
    electricState = 4
    Electric.mode.tick()
    eq("electric: bolt delivered", #calls(world.commF, "DeliverLightningBolt"), 2)
    eq("electric: delivery not 1 -> BuyElectro", #buys(world.commF, "BuyElectro"), 2)
end

meleeSetup(2753915549, 300, { style("Electric", 10) }, {}, 600000)
do
    Settings.set("ItemElectric", true)
    check("electric: owned -> nothing to do", not Electric.mode.enabled())
end

---------------------------------------------------------------------------
-- Kaitun: targeted hops, config carried over a hop
---------------------------------------------------------------------------

kaitunSetup(4442272183, 1200)
do
    local saved = KTasks.LIST
    local hops = 0
    local Server = require("Game.Server")
    local realHop = Server.hop
    Server.hop = function() hops = hops + 1; return true end
    local CommonModule = require("Features.Stack.Common")
    CommonModule.reset()
    local afterHop = CommonModule.HOP_AFTER
    CommonModule.HOP_AFTER = 0
    local idleMode = { name = "Key", status = "Waiting", enabled = function() return false end }
    KTasks.LIST = { { name = "Key", priority = 1, seas = { 2 }, mode = idleMode, keys = { ItemWaterKey = true },
        hop = function() return "no Tide Keeper" end } }
    local limit = KEngine.IDLE_LIMIT
    KEngine.IDLE_LIMIT = 0
    local hopAfter = KEngine.HOP_AFTER
    KEngine.HOP_AFTER = 0
    KEngine.tick()
    eq("hop: asked for the missing boss", hops, 1)
    eq("hop: not rested instead", KEngine.blocked(KTasks.LIST[1], 2, 1200), nil)
    eq("hop: shown", KEngine.status().hop, "no Tide Keeper")

    KEngine.reset()
    CommonModule.reset()
    KConfig.load({ Hop = false })
    KEngine.tick()
    eq("hop off: no hop", hops, 1)
    eq("hop off: rested", KEngine.blocked(KTasks.LIST[1], 2, 1200), "resting")

    KEngine.IDLE_LIMIT = limit
    KEngine.HOP_AFTER = hopAfter
    CommonModule.HOP_AFTER = afterHop
    Server.hop = realHop
    KTasks.LIST = saved
    KConfig.reset()
end

do
    KConfig.load({ Team = "Marines", Skip = { CDK = true }, WebhookUrl = 'a"b' })
    local loader = KConfig.loader()
    check("loader sets the config", loader:find("getgenv().StrawberryKaitun = {", 1, true) == 1)
    check("loader loads the Kaitun", loader:find("StrawberryKaitun.lua", 1, true) ~= nil)
    local chunk = (loadstring or load)("local getgenv = ...; " .. loader:gsub("\nloadstring.*$", ""))
    local env = {}
    chunk(function() return env end)
    eq("serialized config: team", env.StrawberryKaitun.Team, "Marines")
    eq("serialized config: skip", env.StrawberryKaitun.Skip.CDK, true)
    eq("serialized config: quotes kept", env.StrawberryKaitun.WebhookUrl, 'a"b')
    KConfig.reset()
end

---------------------------------------------------------------------------
-- Kaitun late game: chalice plan, Valkyrie Helm / Mirror Fractal / Swan /
-- haki colour hops, anchoring, rests, wake
---------------------------------------------------------------------------

local KSummons = require("Features.Stack.Summons")

local function colours(unlocked)
    return function()
        return {
            { HiddenName = "Winter Sky", Unlocked = unlocked },
            { HiddenName = "Pure Red", Unlocked = unlocked },
            { HiddenName = "Snow White", Unlocked = unlocked },
        }
    end
end

local function lateSetup(inventory, answers, fragments)
    meleeSetup(7449423635, 2500, inventory, answers, 0, fragments or 0)
    KConfig.reset()
    KEngine.reset()
    KSummons.reset()
end

local function tool(name)
    local t = newInstance("Tool", name, world.player.Backpack)
    return t
end

lateSetup({}, { getColors = colours(false) })
do
    eq("plan: colours missing, no Mirror Fractal -> Dough King", (KEngine.chalicePlan(2500)), "dough")
    eq("plan: nothing before the late game", KEngine.chalicePlan(2000), nil)
    check("colours needed", KEngine.needsColours(2500))
    local keys = KEngine.background(3, 2500, false)
    eq("dough plan: Dough King summon on", keys.StackSummonDoughKing, true)
    eq("dough plan: no pads", keys.StackHakiPads, false)
    eq("Tushita missing: rip_indra left alive", keys.StackRipIndra, false)
end

lateSetup({}, { getColors = colours(true) })
do
    local plan, goal = KEngine.chalicePlan(2500)
    eq("plan: colours in, no Tushita -> rip_indra", plan, "rip")
    eq("plan: for Tushita", goal, "Tushita")
    eq("rip plan without a chalice: no pads", KEngine.background(3, 2500, false).StackHakiPads, false)
    tool("God's Chalice")
    local keys = KEngine.background(3, 2500, false)
    eq("rip plan with a chalice: pads", keys.StackHakiPads, true)
    eq("rip plan with a chalice: summon", keys.StackSummonRipIndra, true)
end

lateSetup({ { Name = "Tushita", Type = "Sword", Count = 1 }, { Name = "Mirror Fractal", Type = "Material", Count = 1 } },
    { getColors = colours(true) })
do
    local plan, goal = KEngine.chalicePlan(2500)
    eq("plan: Tushita and Mirror Fractal in -> rip_indra", plan, "rip")
    eq("plan: for the Valkyrie Helm", goal, "Valkyrie Helm")
    eq("Tushita owned: rip_indra fought", KEngine.background(3, 2500, false).StackRipIndra, true)
    eq("helm hop: no elite, no rip_indra", KEngine.lateHop(3, 2800), "Valkyrie Helm: no elite for a chalice")
    eq("late hops wait for the max level", KEngine.lateHop(3, 2500), nil)
    mob("Diablo", Vector3.new(0, 0, 50))
    eq("helm hop: an elite here -> stay", KEngine.lateHop(3, 2800), nil)
end

lateSetup({ { Name = "Conjured Cocoa", Type = "Material", Count = 10 } }, { getColors = colours(true) })
do
    -- Tushita owned through the tool, no Mirror Fractal.
    tool("Tushita")
    eq("mirror hop: cocoa in, no chalice, no elite", KEngine.lateHop(3, 2800), "Mirror Fractal: no elite for a chalice")
    tool("Sweet Chalice")
    eq("mirror hop: Sweet Chalice held -> stay", KEngine.lateHop(3, 2800), nil)
end

lateSetup({ { Name = "Conjured Cocoa", Type = "Material", Count = 3 } }, { getColors = colours(true) })
do
    tool("Tushita")
    eq("mirror: cocoa still to farm -> no hop", KEngine.lateHop(3, 2800), nil)
end

local dealer = "Pure Red"
lateSetup({}, {
    getColors = function()
        return { { HiddenName = "Winter Sky", Unlocked = true }, { HiddenName = "Pure Red", Unlocked = true },
            { HiddenName = "Snow White", Unlocked = false } }
    end,
    ColorsDealer = function(what) if what == "1" then return dealer end return 1 end,
}, 8000)
do
    eq("colours: dealer without the missing one -> hop", KEngine.lateHop(3, 2800), "haki colour dealer")
    dealer = "Snow White"
    require("Features.Stack.Common").forget()
    eq("colours: dealer has it -> no hop", KEngine.lateHop(3, 2800), nil)
    KEngine.tick()
    local buys = 0
    for _, call in ipairs(calls(world.commF, "ColorsDealer")) do
        if call[2] == "2" then buys = buys + 1 end
    end
    eq("colours: bought", buys, 1)
    eq("fragment goal covers a colour", KTasks.fragmentGoal(), 7500)
end

local fruitStock = { { Name = "Leopard-Leopard", Price = 5000000, OnSale = true },
    { Name = "Buddha-Buddha", Price = 1200000, OnSale = true }, { Name = "Spin-Spin", Price = 7500, OnSale = true } }
local function swanSetup(beli)
    meleeSetup(4442272183, 1600, {}, {
        BartiloQuestProgress = 3, TalkTrevor = 1, GetFruits = fruitStock,
    }, beli)
    KConfig.reset()
    KEngine.reset()
end
swanSetup(100000)
do
    local World = require("Features.Stack.World")
    check("swan: Trevor needs a fruit", World.needsTrevorFruit())
    eq("swan: cheapest fruit worth 1M", (World.cheapestTrevorFruit()), "Buddha-Buddha")
    eq("swan: a 1M fruit on sale -> farm the money, no hop", KEngine.lateHop(2, 1600), nil)
    local saved = fruitStock
    fruitStock = { { Name = "Spin-Spin", Price = 7500, OnSale = true } }
    world.commF.OnInvoke = function(action, ...)
        if action == "GetFruits" then return fruitStock end
        if action == "BartiloQuestProgress" then return 3 end
        if action == "TalkTrevor" then return 1 end
    end
    require("Features.Stack.Common").forget()
    eq("swan: none worth 1M on sale -> hop for a ground fruit", KEngine.lateHop(2, 1600), "Swan door: no fruit worth 1M on sale")
    fruitStock = saved
end
swanSetup(700000)
do
    eq("swan: half the money there -> keep farming", KEngine.lateHop(2, 1600), nil)
end
swanSetup(2000000)
do
    KEngine.tick()
    local bought = calls(world.commF, "PurchaseRawFruit")[1]
    eq("swan: buys the cheapest fruit worth 1M", bought and bought[2], "Buddha-Buddha")
end

-- Anchoring: a Sea 1 task keeps the New World quest (which travels) off.
kaitunSetup(2753915549, 800)
do
    local list = { { name = "Here", priority = 1, seas = { 1 }, keys = { ItemSaber = true } } }
    local wanted = KEngine.desired(1, 800, list)
    eq("anchored: New World waits", wanted.StackNewWorld, false)
    wanted = KEngine.desired(1, 800, {})
    eq("free: New World on", wanted.StackNewWorld, true)
end

-- A working task keeps the character against a task of the same priority.
kaitunSetup(7449423635, 2500)
do
    local saved = KTasks.LIST
    local busy = { name = "Busy", status = "working", enabled = function() return true end }
    local first = { name = "First", priority = 4, seas = { 3 }, mode = busy, keys = { ItemYama = true } }
    local second = { name = "Second", priority = 4, seas = { 3 }, mode = busy, keys = { ItemTushita = true } }
    local urgent = { name = "Urgent", priority = 1, seas = { 3 }, mode = busy, keys = { ItemCDK = true },
        ready = function() return false end }
    KTasks.LIST = { first, second, urgent }
    KEngine.rest(first, 1, "test")
    KEngine.tick()
    eq("sticky: the other task runs while the first rests", KEngine.status().task, "Second")
    KEngine.reset()
    KTasks.LIST = { first, second, urgent }
    KEngine.tick()
    eq("sticky: first by order", KEngine.status().task, "First")
    KTasks.LIST = { second, first, urgent }
    KEngine.tick()
    eq("sticky: a same-priority task does not cut in", KEngine.status().task, "First")
    urgent.ready = function() return true end
    KEngine.tick()
    eq("sticky: a more urgent task does", KEngine.status().task, "Urgent")
    KTasks.LIST = saved
end

-- Rests double, and wake() ends one early.
kaitunSetup(7449423635, 2500)
do
    local task = { name = "Twice", priority = 1, seas = { 3 }, keys = {} }
    KEngine.rest(task, 100, "test")
    local first = tonumber(KEngine.status().resting[1]:match("(%d+)s"))
    KEngine.rest(task, 100, "test")
    local second = tonumber(KEngine.status().resting[1]:match("(%d+)s"))
    check("second rest twice as long", second >= 199 and first <= 100, tostring(first) .. " / " .. tostring(second))
    local boss = false
    local sleeper = { name = "Sleeper", priority = 1, seas = { 3 }, keys = {}, wake = function() return boss end }
    KEngine.rest(sleeper, 300, "waiting")
    eq("resting until woken", KEngine.blocked(sleeper, 3, 2500), "resting")
    boss = true
    eq("woken early", KEngine.blocked(sleeper, 3, 2500), nil)
end

-- The pads give up on a pad that will not light.
kaitunSetup(7449423635, 2500)
do
    local castle = folder("Boat Castle", folder("Map", workspace))
    local summoner = folder("Summoner", castle)
    local circle = folder("Circle", summoner)
    local padPart = part("Pad", Vector3.new(0, 0, 0), circle)
    local light = part("Part", Vector3.new(0, 0, 0), padPart)
    light.BrickColor = BrickColor and BrickColor.new("Really red") or nil
    Settings.set("StackHakiPads", true)
    local giveUp = KSummons.PAD_GIVE_UP
    KSummons.PAD_GIVE_UP = 0
    local fake = { target = nil }
    KSummons.run(fake, true, false)
    local status = KSummons.run(fake, true, false)
    check("pads: gave up", status:find("will not light", 1, true) ~= nil, status)
    check("pads: resting afterwards", KSummons.resting())
    check("pads: not wanted while resting", not KSummons.want())
    KSummons.PAD_GIVE_UP = giveUp
end

-- Fruits taken out on purpose are not stored straight back.
batchBSetup()
do
    local FruitsModule = require("Features.Fruits")
    local fruitTool = newInstance("Tool", "Buddha Fruit", world.player.Backpack)
    FruitsModule.keep("Buddha-Buddha", 60)
    eq("kept fruit not stored", FruitsModule.storeNext(), nil)
    FruitsModule.reset()
    eq("without keep it is stored", FruitsModule.storeNext(), fruitTool)
end

-- The melee chain lets go of a style the server keeps refusing.
meleeSetup(2753915549, 100, { style("Dark Step", 150) }, {}, 200000)
do
    Settings.set("ItemMeleeProgress", true)
    local every = Melee.LOAD_EVERY
    Melee.LOAD_EVERY = 0
    for _ = 1, Melee.MAX_TRIES do Melee.mode.tick() end
    check("melee: given up after the tries", Melee.givenUp("Black Leg"))
    check("melee: mode lets the farm run", not Melee.mode.enabled())
    Melee.LOAD_EVERY = every
end

-- Something else called "Electric" in the inventory is not the style.
meleeSetup(2753915549, 320, { { Name = "Electric", Type = "Material", Count = 1 } }, {}, 600000)
do
    check("electric: a material named Electric is not the style", not Melee.owned("Electro"))
end
meleeSetup(2753915549, 320, { style("Electric", 0) }, {}, 600000)
do
    check("electric: the style itself counts", Melee.owned("Electro"))
end

-- Tushita and Yama to 350.
itemsSetup(7449423635, 2500, { { Name = "Tushita", Type = "Sword", Mastery = 400 }, { Name = "Yama", Type = "Sword", Mastery = 120 } })
do
    eq("cdk mastery: the sword behind", Cdk.masteryTarget(), "Yama")
end
itemsSetup(7449423635, 2500, { { Name = "Tushita", Type = "Sword", Mastery = 400 }, { Name = "Yama", Type = "Sword", Mastery = 360 } })
do
    eq("cdk mastery: both at 350", Cdk.masteryTarget(), nil)
end

-- The Library Key from Sea 3, once Black Leg is at 400.
meleeSetup(7449423635, 2500, { style("Dark Step", 400) }, { BuyDeathStep = 0 })
do
    check("library key: needed", Melee.libraryKey.needed())
    Settings.set("ItemLibraryKey", true)
    check("library key: wanted from Sea 3", Melee.libraryKey.enabled())
    Melee.libraryKey.tick()
    eq("library key: travels to Sea 2", Melee.libraryKey.status, "Travelling to Sea 2 for the Library Key")
end
meleeSetup(7449423635, 2500, { style("Dark Step", 200) }, { BuyDeathStep = 0 })
do
    check("library key: not needed yet", not Melee.libraryKey.needed())
end

-- The library already open (OpenLibrary answers true): Death Step counts as
-- unlocked even without the fragments, the key is not used forever.
meleeSetup(4442272183, 1074, { style("Dark Step", 347) }, { BuyDeathStep = 0, OpenLibrary = true })
do
    check("library open: Death Step unlocked", Melee.unlocked("Death Step"))
    check("library open: no key job", not Melee.libraryKey.enabled())
end
-- The key used again and again, still in the inventory: open already.
meleeSetup(4442272183, 1074, { style("Dark Step", 347) }, { BuyDeathStep = 0, OpenLibrary = 0 })
do
    newInstance("Tool", "Library Key", world.player.Backpack)
    Settings.set("ItemLibraryKey", true)
    local ask = require("Features.Stack.Common")
    for _ = 1, Melee.KEY_TRIES do
        ask.reset()
        Melee.libraryKey.tick()
    end
    check("key kept after tries: unlocked", Melee.unlocked("Death Step"))
end

-- Electric: no cloud in Sea 1 -> a hop reason for the Kaitun.
meleeSetup(2753915549, 300, {}, { ElectroQuestState = 1 }, 600000)
do
    local electric
    for _, task in ipairs(KTasks.LIST) do if task.name == "Electric" then electric = task end end
    eq("electric: hop when no cloud", electric.hop(), "no charged storm cloud")
    eq("electric: waits 3 minutes first", electric.hopAfter, 180)
end

---------------------------------------------------------------------------
-- Skip level (Teddy's Jump Lv Farming) and boss quests first
---------------------------------------------------------------------------

local SkipLevel = require("Features.SkipLevel")

setup({ level = 10 })
game.PlaceId = 2753915549
do
    eq("skip: level 10 -> Sky Bandit", SkipLevel.step(10).mob, "Sky Bandit")
    eq("skip: level 80 -> God's Guard", SkipLevel.step(80).mob, "God's Guard")
    eq("skip: done at 150", SkipLevel.step(150), nil)
    Settings.set("AutoSkipLevel", true)
    check("skip: on under 150 in Sea 1", SkipLevel.mode.enabled())
    SkipLevel.mode.tick()
    eq("skip: flies to the Skylands first", SkipLevel.mode.status, "Going to the Sky Bandits")
    local bandit = mob("Sky Bandit", Vector3.new(0, 0, 10))
    SkipLevel.mode.tick()
    eq("skip: fights the loaded mob", SkipLevel.mode.target, bandit)
    world.level.Value = 150
    check("skip: off at 150", not SkipLevel.mode.enabled())
    world.level.Value = 50
    game.PlaceId = 4442272183
    check("skip: off outside Sea 1", not SkipLevel.mode.enabled())
end

setup()
do
    eq("boss quest: none while the boss is away", Quests.bossQuest(960), nil)
    local boss = mob("Some Boss", Vector3.new(0, 0, 30))
    local plan = Quests.bossQuest(960)
    eq("boss quest: picked when the boss is up", plan and plan.questName, "BossQuest")
    eq("boss quest: too high for the level", Quests.bossQuest(900), nil)
    eq("boss quest: below the level's mob quest -> not worth it", Quests.bossQuest(980), nil)
    boss.Parent = rs
    eq("boss quest: a model kept in ReplicatedStorage does not count", Quests.bossQuest(960), nil)
end

setup()
LevelFarm.stop()
do
    Settings.set("FarmBossQuests", true)
    mob("Some Boss", Vector3.new(0, 0, 30))
    world.commF.OnInvoke = function() return true end
    LevelFarm.tick()
    check("boss first: goes for the boss quest", tostring(LevelFarm.status):find("Some Boss", 1, true) ~= nil, LevelFarm.status)

    world.guide.Data.QuestData = { Task = { Zombie = 8 } }
    world.questPanel.Visible = true
    LevelFarm.tick()
    eq("boss first: a mob quest is dropped", #calls(world.commF, "AbandonQuest"), 1)
end

setup()
LevelFarm.stop()
do
    Settings.set("FarmBossQuests", true)
    world.guide.Data.QuestData = { Task = { ["Some Boss"] = 1 } }
    world.questPanel.Visible = true
    LevelFarm.tick()
    eq("boss gone: its quest is dropped", #calls(world.commF, "AbandonQuest"), 1)
    Settings.set("FarmBossQuests", false)
    world.guide.Data.QuestData = { Task = { Zombie = 8 } }
    mob("Some Boss", Vector3.new(0, 0, 30))
    LevelFarm.tick()
    eq("boss quests off: nothing dropped", #calls(world.commF, "AbandonQuest"), 1)
end

-- Boss really there: free to fight, decorated names, absent marks.
setup()
do
    local boss = mob("Some Boss [Lv. 25] [Boss]", Vector3.new(0, 0, 30))
    eq("bossUp: decorated name matches", Enemies.bossUp("Some Boss"), boss)
    boss:SetAttribute("BossEngagedWith", 999)
    eq("bossUp: fought by another player -> not up", Enemies.bossUp("Some Boss"), nil)
    eq("boss quest: none for a boss someone else fights", Quests.bossQuest(960), nil)
    boss:SetAttribute("BossEngagedWith", nil)
    check("boss quest: taken when the boss is free", Quests.bossQuest(960) ~= nil)
    boss:SetAttribute("LocalEnemy", "Tester")
    eq("bossUp: a secret quest copy -> not up", Enemies.bossUp("Some Boss"), nil)
    boss:SetAttribute("LocalEnemy", nil)
    Enemies.ignore(boss, 60)
    eq("bossUp: ignored by the watchdog -> not up", Enemies.bossUp("Some Boss"), nil)
    local other = mob("Some Boss", Vector3.new(0, 0, 40))
    eq("bossUp: another copy that can be fought", Enemies.bossUp("Some Boss"), other)
    Enemies.markAbsent("Some Boss", 60)
    eq("bossUp: marked absent -> not up", Enemies.bossUp("Some Boss"), nil)
    Enemies.markAbsent("Some Boss", -1)
    eq("bossUp: the mark wears off", Enemies.bossUp("Some Boss"), other)
end

-- Boss quest held, boss gone: dropped, and not retaken right after.
setup()
LevelFarm.stop()
do
    Settings.set("FarmBossQuests", true)
    world.commF.OnInvoke = function() return true end
    world.guide.Data.QuestData = { Task = { ["Some Boss"] = 1 } }
    world.questPanel.Visible = true
    LevelFarm.tick()
    eq("boss gone: dropped", #calls(world.commF, "AbandonQuest"), 1)
    check("boss gone: says so", LevelFarm.status:find("not really there", 1, true) ~= nil, LevelFarm.status)
    -- A stale model shows up again: the boss stays left alone.
    mob("Some Boss", Vector3.new(0, 0, 30))
    eq("boss gone: no boss quest for a while", Quests.bossQuest(960), nil)
    Settings.set("FarmBossQuests", false)
end

-- Boss quest held, the boss only parked in ReplicatedStorage and nothing
-- loads at its spot: a stale copy, dropped.
setup()
LevelFarm.stop()
do
    Settings.set("FarmBossQuests", true)
    world.commF.OnInvoke = function() return true end
    world.guide.Data.QuestData = { Task = { ["Some Boss"] = 1 } }
    world.questPanel.Visible = true
    mob("Some Boss", Vector3.new(500, 0, 0), 100, rs)
    LevelFarm.tick()
    eq("parked boss: flies to it", LevelFarm.status, "Boss quest: going to Some Boss")
    eq("parked boss: nothing dropped yet", #calls(world.commF, "AbandonQuest"), 0)
    local stale = LevelFarm.BOSS_STALE
    LevelFarm.BOSS_STALE = -1
    world.hrp.Position = Vector3.new(500, 60, 0)
    LevelFarm.tick()
    LevelFarm.tick()
    eq("stale copy: dropped", #calls(world.commF, "AbandonQuest"), 1)
    check("stale copy: absent", Enemies.absent("Some Boss"))
    LevelFarm.BOSS_STALE = stale
    Settings.set("FarmBossQuests", false)
end

kaitunSetup(2753915549, 50)
do
    local keys, name = KEngine.idle(1, 50)
    eq("kaitun: skip under 150", keys.AutoSkipLevel, true)
    eq("kaitun: skip name", name, "Skip level (God's Guard)")
    eq("kaitun: boss quests on", keys.FarmBossQuests, true)
    keys = KEngine.idle(1, 200)
    eq("kaitun: no skip at 200", keys.AutoSkipLevel, nil)
    KConfig.load({ SkipLevel = false })
    eq("kaitun: skip can be turned off", KEngine.idle(1, 50).AutoSkipLevel, nil)
    KConfig.reset()
end

---------------------------------------------------------------------------
-- Codes (2x experience)
---------------------------------------------------------------------------

local Codes = require("Features.Codes")

setup()
do
    Codes.reset()
    local files = {}
    local saved = { isfile, readfile, writefile }
    isfile = function(path) return files[path] ~= nil end
    readfile = function(path) return files[path] end
    writefile = function(path, text) files[path] = text end
    local http = game:GetService("HttpService")
    function http:JSONEncode(value) return value end
    function http:JSONDecode(value) return value end
    local remote = newInstance("RemoteFunction", "Redeem", rs.Remotes)
    local every = Codes.EVERY
    Codes.EVERY = 0
    local sent
    local co = coroutine.create(function() sent = Codes.redeemAll() end)
    coroutine.resume(co)
    for _ = 1, #Data.CODES + 5 do
        if coroutine.status(co) == "dead" then break end
        stepTasks()
        if coroutine.status(co) == "suspended" then coroutine.resume(co) end
    end
    eq("codes: every code sent once", sent, #Data.CODES)
    eq("codes: through Remotes.Redeem", remote.Invoked and #remote.Invoked, #Data.CODES)
    local again = Codes.redeemAll()
    eq("codes: already tried on this account -> none again", again, 0)
    local seen, duplicate = {}, false
    for _, code in ipairs(Data.CODES) do
        if seen[code:lower()] then duplicate = true end
        seen[code:lower()] = true
    end
    check("codes: no duplicate in the list", not duplicate)
    Codes.EVERY = every
    isfile, readfile, writefile = saved[1], saved[2], saved[3]
end

---------------------------------------------------------------------------
-- Team on execute, logo image
---------------------------------------------------------------------------

setup()
do
    world.player.Team = nil
    local asked = {}
    world.commF.OnInvoke = function(action, team)
        if action == "SetTeam" then
            asked[#asked + 1] = team
            if #asked >= 2 then world.player.Team = { Name = team } end
        end
    end
    local done
    local co = coroutine.create(function() done = Player.chooseTeam("Marines", 30) end)
    coroutine.resume(co)
    for _ = 1, 5 do
        if coroutine.status(co) == "dead" then break end
        stepTasks()
        if coroutine.status(co) == "suspended" then coroutine.resume(co) end
    end
    check("team: joined through SetTeam", done == true)
    eq("team: the configured team", asked[1], "Marines")
    eq("team: retried until it took", #asked, 2)
    eq("team: already in one -> nothing sent", (function()
        asked = {}
        Player.chooseTeam("Pirates", 30)
        return #asked
    end)(), 0)
end

do
    local Logo = require("UI.Logo")
    Logo.reset()
    local saved = { getcustomasset, writefile, isfile, makefolder, isfolder }
    local files = {}
    getcustomasset = function(path) return "rbxasset://" .. path end
    writefile = function(path, data) files[path] = data end
    isfile = function(path) return files[path] ~= nil end
    makefolder, isfolder = function() end, function() return true end
    local realGet = game.HttpGet
    game.HttpGet = function() return "\137PNG fake" end
    eq("logo: downloaded and handed to getcustomasset", Logo.asset(), "rbxasset://StrawberryHub/strawberry.png")
    check("logo: saved in the workspace", files["StrawberryHub/strawberry.png"] ~= nil)
    Logo.reset()
    getcustomasset = nil
    eq("logo: no getcustomasset -> text fallback", Logo.asset(), nil)
    game.HttpGet = realGet
    getcustomasset, writefile, isfile, makefolder, isfolder = saved[1], saved[2], saved[3], saved[4], saved[5]
    Logo.reset()
end

-- The user's accounts in Sea 1. Order wanted: a style to buy first (it is
-- quick and unblocks the rest), then Electric once the $500k of the
-- delivery are there, Saber otherwise; never the level farm over them.
local function runningMode()
    for _, mode in ipairs(require("Features.Farm").MODES) do
        if mode.enabled() then return mode.name end
    end
end

-- $504k, Combat only: Black Leg is bought first, Electric is the task.
meleeSetup(2753915549, 320, {}, {}, 504694)
do
    KConfig.reset()
    KEngine.reset()
    KEngine.tick()
    KEngine.tick()
    eq("$504k: Electric is the task", KEngine.status().task, "Electric")
    eq("$504k: Black Leg bought first", runningMode(), "Melee")
    check("$504k: plan says Electric runs", table.concat(KEngine.plan(), " | "):find("Electric: running", 1, true) ~= nil)
end

-- Black Leg held under 400: one style at a time, Electric waits for it.
meleeSetup(2753915549, 369, { style("Dark Step", 197) }, {}, 704630)
do
    newInstance("Tool", "Dark Step", world.player.Backpack).ToolTip = "Melee"
    KConfig.reset()
    KEngine.reset()
    KEngine.tick()
    KEngine.tick()
    check("$704k + Black Leg 197: not Electric", KEngine.status().task ~= "Electric")
    check("$704k + Black Leg 197: plan says Black Leg first",
        table.concat(KEngine.plan(), " | "):find("Black Leg to 400 first", 1, true) ~= nil, table.concat(KEngine.plan(), " | "))
    check("$704k + Black Leg 197: the hub mode waits too", not Electric.mode.enabled())
end

-- Electro bought replaced Black Leg in the inventory: Black Leg is
-- remembered (or answers "owned"), so it is taken back to 400 first.
meleeSetup(2753915549, 340, { style("Electric", 53) }, {}, 20000)
do
    newInstance("Tool", "Electric", world.player.Backpack).ToolTip = "Melee"
    world.commF.OnInvoke = function(action, ask)
        if action == "BuyBlackLeg" and ask == true then return 1 end
        return 0
    end
    Melee.reset()
    eq("black leg remembered as owned", Melee.owned("Black Leg"), true)
    eq("but not held", Melee.held("Black Leg"), false)
    local action, name = Melee.action()
    eq("back to Black Leg first", name, "Black Leg")
    eq("from its teacher", action, "buy")
    Melee.remember("Black Leg", 400)
    eq("black leg at 400: Electro now", select(2, Melee.action()), "Electro")
end

-- Black Leg at 400: the Electric quest is what runs.
meleeSetup(2753915549, 369, { style("Dark Step", 400) }, {}, 704630)
do
    newInstance("Tool", "Dark Step", world.player.Backpack).ToolTip = "Melee"
    KConfig.reset()
    KEngine.reset()
    KEngine.tick()
    KEngine.tick()
    eq("$704k + Black Leg 400: Electric is the task", KEngine.status().task, "Electric")
    eq("$704k + Black Leg 400: the Electric quest runs", runningMode(), "Electric")
end

-- $200k: the quest waits for the money (no cloud announced), Saber runs.
meleeSetup(2753915549, 320, { style("Dark Step", 197) }, {}, 200000)
do
    newInstance("Tool", "Dark Step", world.player.Backpack).ToolTip = "Melee"
    KConfig.reset()
    KEngine.reset()
    KEngine.tick()
    KEngine.tick()
    eq("$200k: Saber is the task", KEngine.status().task, "Saber")
    check("$200k: plan says Electric is not ready", table.concat(KEngine.plan(), " | "):find("Electric: not ready", 1, true) ~= nil)
end

-- Level 120, $50k: nothing holds the character but the skip level.
meleeSetup(2753915549, 120, {}, {}, 50000)
do
    KConfig.reset()
    KEngine.reset()
    KEngine.tick()
    KEngine.tick()
    eq("low level: no task", KEngine.status().task, nil)
    eq("low level: skip level runs", runningMode(), "Skip Level")
end

-- The item replication list once claimed a Saber and the Electric style
-- the account did not have: ownership only trusts the server's lists.
itemsSetup(2753915549, 320, {}, {})
do
    local CommonModule = require("Features.Stack.Common")
    CommonModule.reset()
    moduleScript("ItemReplicationService", rs, {
        KEYS = { QUANTITY = "q", MASTERY = "m" },
        GetItems = function() return { { ItemId = 1, Value = 1 }, { ItemId = 2, Value = 1 } } end,
        ReadItem = function() return 0 end,
    })
    moduleScript("ItemConfig", rs, {
        match = function(id)
            local info = id == 1 and { Display = { Name = "Saber", Category = "Sword" } }
                or { Display = { Name = "Electric", Category = "Melee" } }
            return { unwrap = function() return info end }
        end,
    })
    eq("replication list read", CommonModule.itemCount("Saber"), 1)
    check("but Saber is not owned for it", not KTasks.owned("Saber"))
    check("nor Electric", not Melee.owned("Electro"))
    world.commF.OnInvoke = function(action)
        if action == "getInventoryWeapons" then return { { Name = "Saber" } } end
    end
    CommonModule.forget()
    eq("getInventoryWeapons says Saber", CommonModule.ownedBy("Saber"), "getInventoryWeapons")
    -- The inventory window's controller is never required: requiring it can
    -- block forever (it froze the Kaitun's engine and screen in game).
    local controllers = folder("Controllers", rs)
    local ui = folder("UI", controllers)
    local inventoryWindow = moduleScript("Inventory", ui, nil)
    inventoryWindow.ModuleError = "would block"
    WARNINGS = {}
    eq("ownership never requires the inventory window", CommonModule.ownedBy("Yama"), nil)
    eq("no warning from it", #WARNINGS, 0)
end

-- The user's game: after the cloud the state was neither 4 nor 1/2, and the
-- Kaitun went back to asking the Mad Scientist. The bolt phase is now
-- recognised, and with less than $500k the farms go on.
local boltState = 1
meleeSetup(2753915549, 184, {}, { ElectroQuestState = function() return boltState end }, 202281)
do
    local npc = newInstance("Model", "Mad Scientist", folder("NPCs", workspace))
    part("HumanoidRootPart", Vector3.new(0, 0, -4), npc)
    check("bolt: not yet during the cloud phase", not Electric.hasBolt())
    boltState = 3
    require("Features.Stack.Common").forget()
    check("bolt: the state after the cloud phase means the bolt", Electric.hasBolt())
    Settings.set("ItemElectric", true)
    check("bolt: under $500k the quest waits (farms go on)", not Electric.mode.enabled())
end

meleeSetup(2753915549, 184, {}, { ElectroQuestState = 0 }, 202281)
do
    local npc = newInstance("Model", "Mad Scientist", folder("NPCs", workspace))
    part("HumanoidRootPart", Vector3.new(0, 0, -4), npc)
    local CommonModule = require("Features.Stack.Common")
    Settings.set("ItemElectric", true)
    for _ = 1, Electric.ACCEPT_TRIES + 2 do
        CommonModule.reset()
        Electric.step({})
    end
    check("accept: given up after the same answer again and again", Electric.givenUp())
    check("accept: the mode lets the farms run", not Electric.mode.enabled())
end

---------------------------------------------------------------------------
-- Simulation audit (Sea 1 / Sea 2 / Sea 3): regressions
---------------------------------------------------------------------------

local function taskNamed(name)
    for _, task in ipairs(KTasks.LIST) do if task.name == name then return task end end
end

-- Why the Kaitun raids: the fragments' purpose on the screen.
meleeSetup(4442272183, 1000, { style("Dark Step", 300) }, { BuyDeathStep = 0 }, 100000)
do
    local reason, goal = KTasks.fragmentReason()
    eq("fragments: for Dragon Claw", reason, "Dragon Claw")
    eq("fragments: 1500", goal, 1500)
    check("fragments task detail", tostring(taskNamed("Fragments").detail()):find("Dragon Claw: 0/1500", 1, true) ~= nil,
        tostring(taskNamed("Fragments").detail()))
end


-- Sea 2 Key Hop only from level 1500, and not while the other key's boss is here.
meleeSetup(4442272183, 1200, { style("Dark Step", 400), style("Water Kung Fu", 400) },
    { BuyDeathStep = 0, BuySharkmanKarate = "locked" })
do
    eq("key hop: none under level 1500", taskNamed("LibraryKey").hop(), nil)
    world.level.Value = 1600
    eq("key hop: from 1500 for a missing boss", taskNamed("LibraryKey").hop(), "no Awakened Ice Admiral")
    mob("Tide Keeper", Vector3.new(0, 0, 40))
    eq("key hop: not while the other key's boss is here", taskNamed("LibraryKey").hop(), nil)
    check("key: the boss wakes its task", taskNamed("WaterKey").wake())
end

-- Race: Sea 2 only, with the money of the step.
meleeSetup(4442272183, 1500, {}, { Alchemist = 0, Wenlocktoad = 0 }, 100000)
do
    KConfig.reset(); KEngine.reset()
    eq("race: not ready under $500k", KEngine.blocked(taskNamed("Race"), 2, 1500), "not ready")
    eq("race: waits for level 1500", KEngine.blocked(taskNamed("Race"), 2, 900), "level 1500")
    eq("race: never from Sea 3", KEngine.blocked(taskNamed("Race"), 3, 1600), "other sea")
end

-- Soul Reaper is left alive (and not summoned) during CDK's evil trials 4 / 5.
lateSetup({}, { getColors = colours(true), CDKQuest = function() return { Good = 4, Evil = -5 } end })
do
    local keys = KEngine.background(3, 2500, false)
    eq("cdk evil 5: Soul Reaper not fought", keys.StackSoulReaper, false)
    eq("cdk evil 5: Soul Reaper not summoned", keys.StackSummonSoulReaper, false)
end

-- Godhuman materials beat the idle Katakuri / bones farms.
do
    local keys = KTasks.keysOf(taskNamed("GodhumanMaterials"))
    eq("godhuman materials: Katakuri off", keys.AutoKatakuri, false)
    eq("godhuman materials: bones off", keys.AutoBone, false)
end

-- A task whose mode has nothing to do never takes the character.
kaitunSetup(7449423635, 2500)
do
    local saved = KTasks.LIST
    local busy = { name = "Busy", status = "working", enabled = function() return true end }
    local lazy = { name = "Lazy", status = "idle", enabled = function() return false end,
        wanted = function() return false end }
    local working = { name = "Working", priority = 5, seas = { 3 }, mode = busy, keys = { ItemYama = true } }
    local urgent = { name = "Urgent", priority = 1, seas = { 3 }, mode = lazy, keys = { ItemTushita = true } }
    KTasks.LIST = { working, urgent }
    KEngine.tick()
    KEngine.tick()
    eq("nothing to do: the working task keeps going", KEngine.status().task, "Working")
    eq("nothing to do: shown as such", KEngine.blocked(urgent, 3, 2500), "nothing to do")
    KTasks.LIST = saved
end

-- Teddy's level gates.
eq("electric claw from level 2000", Melee.step("Electric Claw").level, 2000)
eq("tushita from level 2000", taskNamed("Tushita").minLevel, 2000)

-- Raid chips paid with the cheapest fruit under 1M on sale.
meleeSetup(4442272183, 1200, {}, { GetFruits = {
    { Name = "Spin-Spin", Price = 7500, OnSale = true }, { Name = "Kilo-Kilo", Price = 5000, OnSale = true },
    { Name = "Leopard-Leopard", Price = 5000000, OnSale = true } } })
do
    eq("raid chip: cheapest fruit on sale", (Raids.cheapestOnSale()), "Kilo-Kilo")
end

-- Haki abilities bought like Teddy: Geppo / Buso at once, Soru / Ken later.
meleeSetup(2753915549, 100, {}, {}, 60000)
do
    KConfig.reset(); KEngine.reset()
    eq("abilities: Geppo first", KEngine.nextAbility(1).name, "Geppo")
    game:GetService("CollectionService"):AddTag(world.character, "Geppo")
    eq("abilities: then Buso", KEngine.nextAbility(1).name, "Buso")
    game:GetService("CollectionService"):AddTag(world.character, "Buso")
    world.player.Data.Beli.Value = 400000
    eq("abilities: Soru waits for Electric / Sea 2", KEngine.nextAbility(1), nil)
    eq("abilities: Soru in Sea 2", KEngine.nextAbility(2).name, "Soru")
    KEngine.tick()
end

-- Secret quest mobs (LocalEnemy) and mobs that take no damage are not farmed.
setup()
do
    local normal = mob("Prisoner", Vector3.new(0, 0, 30))
    local secret = mob("Prisoner", Vector3.new(0, 0, 5))
    secret:SetAttribute("LocalEnemy", "Tester")
    eq("secret quest mob skipped (the nearer one)", Enemies.nearest("Prisoner"), normal)
    local Fight = require("Features.Fight")
    local after = Fight.NO_DAMAGE_AFTER
    Fight.NO_DAMAGE_AFTER = -1
    local fake = {}
    Fight.engage(fake, normal)
    Fight.engage(fake, normal)
    eq("no damage at all: left alone", Enemies.nearest("Prisoner"), nil)

    -- A mob close by that the character never gets closer to.
    local progress = Fight.NO_PROGRESS_AFTER
    Fight.NO_PROGRESS_AFTER = -1
    local stuck = mob("Prisoner", Vector3.new(0, 0, 300))
    Fight.engage(fake, stuck)
    world.hrp.CFrame = CFrame.new(0, 0, 0)
    Fight.engage(fake, stuck)
    eq("unreachable mob: left alone", Enemies.nearest("Prisoner"), nil)
    Fight.NO_PROGRESS_AFTER = progress

    -- Three mobs in a row for nothing: the character holds still.
    for index = 1, 2 do
        local other = mob("Prisoner", Vector3.new(index, 0, 10))
        Fight.engage(fake, other)
        Fight.engage(fake, other)
    end
    check("three strikes: resyncing", Fight.resyncing())
    check("resync status", Fight.status(normal, true):find("resync", 1, true) ~= nil)
    Fight.NO_DAMAGE_AFTER = after
end

-- The time left before the next fruit spin, shown under the Kaitun's time.
setup()
do
    local FruitsModule = require("Features.Fruits")
    FruitsModule.resetRoll()
    eq("spin: unknown at first", FruitsModule.nextRollIn(), nil)
    local allowed = false
    world.commF.OnInvoke = function(action, arg)
        if action == "Cousin" and arg == "Check" then return 1000000, 900, 50000 end
        if action == "Cousin" and arg == "CheckTime" then return allowed or 3000 end
        if action == "Cousin" then return 1 end
    end
    check("spin: not allowed yet", not FruitsModule.roll())
    local left = FruitsModule.nextRollIn()
    check("spin: the server's time left", left and left <= 3000 and left > 2990, tostring(left))
    allowed = true
    check("spin: rolled", FruitsModule.roll())
    left = FruitsModule.nextRollIn()
    check("spin: two hours from now", left and left > 7190, tostring(left))
    FruitsModule.resetRoll()
end

-- Copies of a bugged mob, the target switching between them: still
-- ignored once the delay passes (one record per mob).
setup()
do
    local Fight = require("Features.Fight")
    local after = Fight.NO_DAMAGE_AFTER
    Fight.NO_DAMAGE_AFTER = -1
    local a = mob("Lava Pirate", Vector3.new(0, 0, 10))
    local b = mob("Lava Pirate", Vector3.new(0, 0, 12))
    local fake = {}
    for _ = 1, 2 do
        Fight.engage(fake, a)
        Fight.engage(fake, b)
    end
    eq("bugged copies: all left alone", Enemies.nearest("Lava Pirate"), nil)
    local said = Fight.status(a, true)
    check("status says it", said:find("cannot be damaged", 1, true) ~= nil or said:find("resync", 1, true) ~= nil, said)
    Fight.NO_DAMAGE_AFTER = after

    -- A small dip (< 1 %) is no progress.
    local c = mob("Lava Pirate", Vector3.new(0, 0, 14))
    c.Humanoid.MaxHealth = 1000
    c.Humanoid.Health = 1000
    Fight.engage(fake, c)
    c.Humanoid.Health = 995
    Fight.NO_DAMAGE_AFTER = -1
    Fight.engage(fake, c)
    eq("small dip: still left alone", Enemies.nearest("Lava Pirate"), nil)
    Fight.NO_DAMAGE_AFTER = after

    -- Too long next to a normal mob, even with its health going down.
    local maxNear = Fight.MOB_MAX_NEAR
    Fight.MOB_MAX_NEAR = -1
    local d = mob("Lava Pirate", Vector3.new(0, 0, 16))
    Fight.engage(fake, d)
    d.Humanoid.Health = 50
    Fight.engage(fake, d)
    eq("too long on a normal mob: left alone", Enemies.nearest("Lava Pirate"), nil)
    local boss = mob("Ice Admiral", Vector3.new(0, 0, 18))
    Fight.engage(fake, boss)
    boss.Humanoid.Health = 50
    Fight.engage(fake, boss)
    eq("a boss is not", Enemies.nearest("Ice Admiral"), boss)
    Fight.MOB_MAX_NEAR = maxNear
end

-- No damage for a few seconds: a real click (the user's own click unstuck
-- the Lava Pirates).
setup()
do
    local Fight = require("Features.Fight")
    local tool = newInstance("Tool", "Fishman Karate", world.character)
    tool.ToolTip = "Melee"
    local activated = 0
    tool.Activate = function() activated = activated + 1 end
    local user = game:GetService("VirtualUser")
    local clicks = 0
    user.CaptureController = function() end
    user.Button1Down = function() clicks = clicks + 1 end
    user.Button1Up = function() end
    local nudge = Fight.NUDGE_AFTER
    Fight.NUDGE_AFTER = -1
    local pirate = mob("Lava Pirate", Vector3.new(0, 0, 10))
    local fake = {}
    Fight.engage(fake, pirate)
    Fight.engage(fake, pirate)
    check("no damage: the tool is used", activated >= 1)
    check("no damage: a mouse click", clicks >= 1)
    Fight.lastIgnored = nil
    local said = Fight.status(pirate, true)
    check("status says it", said:find("clicking to unstick", 1, true) ~= nil or said:find("resync", 1, true) ~= nil, said)
    Fight.NUDGE_AFTER = nudge
    local hurt = mob("Lava Pirate", Vector3.new(0, 0, 12))
    activated = 0
    Fight.engage(fake, hurt)
    hurt.Humanoid.Health = 10
    Fight.engage(fake, hurt)
    eq("health going down: no click", activated, 0)
end

-- The farm-level watchdog: the kill count frozen while fighting.
setup()
do
    LevelFarm.stop()
    world.commF.OnInvoke = function() return true end
    world.questPanel.Visible = true
    world.guide.Data.QuestData = { Task = { Zombie = 8 } }
    local title = newInstance("TextLabel", "Title", world.questPanel)
    title.Text = "Defeat 8 Zombies"
    local count = newInstance("TextLabel", "Count", world.questPanel)
    count.Text = "5/8"
    mob("Zombie", Vector3.new(0, 0, 10))
    local after = LevelFarm.STUCK_AFTER
    LevelFarm.STUCK_AFTER = -1
    Quests.reset()
    LevelFarm.tick()
    LevelFarm.tick()
    eq("frozen count: quest dropped", #calls(world.commF, "AbandonQuest"), 1)
    mob("Zombie", Vector3.new(0, 0, 12))
    Quests.reset()
    LevelFarm.tick()
    LevelFarm.tick()
    eq("frozen again: the character is reset", world.humanoid.Health, 0)
    LevelFarm.STUCK_AFTER = after
end

-- Saber follows the server's progress (ProQuestProgress), step by step.
local Saber = require("Features.Items.Saber")
do
    eq("saber: plates first", Saber.step({ Plates = { true, true, false, false, false } }), "plates")
    local plates = { true, true, true, true, true }
    eq("saber: then the torch", Saber.step({ Plates = plates }), "torch")
    eq("saber: then the cup", Saber.step({ Plates = plates, UsedTorch = true }), "cup")
    eq("saber: then the Rich Son", Saber.step({ Plates = plates, UsedTorch = true, UsedCup = true }), "talk")
    eq("saber: then the Mob Leader", Saber.step({ Plates = plates, UsedTorch = true, UsedCup = true, TalkedSon = true }), "mob")
    eq("saber: then the Relic", Saber.step({ Plates = plates, UsedTorch = true, UsedCup = true, TalkedSon = true, KilledMob = true }), "relic")
    eq("saber: the Saber Expert only after the Relic", Saber.step({ Plates = plates, UsedTorch = true, UsedCup = true,
        TalkedSon = true, KilledMob = true, UsedRelic = true }), "shanks")
    eq("saber: done", Saber.step({ KilledShanks = true }), nil)
end

local saberProgress = { Plates = { true, true, true, true, true }, UsedTorch = true }
itemsSetup(2753915549, 220, {}, { ProQuestProgress = function(what) if what == nil then return saberProgress end end })
do
    Settings.set("ItemSaber", true)
    check("saber: wanted mid-quest", Saber.mode.enabled())
    Saber.mode.tick()
    check("saber: works on the cup, not the Saber Expert", tostring(Saber.mode.status):find("3/6", 1, true) ~= nil, Saber.mode.status)
    saberProgress = { KilledShanks = true }
    require("Features.Stack.Common").forget()
    check("saber: done -> not wanted", not Saber.mode.enabled())
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------

Loop.stopAll()
clearTasks()

print(string.format("core: %d passed, %d failed", passed, failed))
for _, failure in ipairs(failures) do print("  FAIL " .. failure) end
if failed > 0 then os.exit(1) end
