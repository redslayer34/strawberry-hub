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
    "Game.Router", "Game.Entrances",
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
-- Smart travel
---------------------------------------------------------------------------

local CASTLE = Vector3.new(-4967.7, 314.9, -3157.1)

setup()
do
    game.PlaceId = 7449423635   -- Sea 3
    Entrances.reset({ DefeatedIndraTrueForm = true })
    local goal = CASTLE + Vector3.new(60, 0, 60)

    local plan = Router.plan(Vector3.new(0, 0, 0), goal, 300)
    eq("far goal: portal route", plan.kind, "entrance")
    eq("portal nearest the goal", plan.name, "Castle on the Sea")
    check("saving computed", plan.saving > 15, plan.saving)

    local short = Router.plan(Vector3.new(0, 0, 0), Vector3.new(1400, 0, 0), 300)
    eq("small saving: fly directly", short.kind, "direct")

    Entrances.reset({})
    local unflagged = Router.plan(Vector3.new(0, 0, 0), goal, 300)
    eq("missing unlock flag: portal still tried", unflagged.name, "Castle on the Sea")
    check("shown as unconfirmed", Router.describe():find("unlock not confirmed", 1, true) ~= nil, Router.describe())
    Entrances.reset({ DefeatedIndraTrueForm = true })

    -- A jump that works: requestEntrance sent, portal confirmed.
    world.commF.OnInvoke = function(action)
        if action == "requestEntrance" then world.hrp.Position = CASTLE end
        return true
    end
    check("shortcut running", Router.update(Vector3.new(0, 0, 0), goal, 300))
    local call = world.commF.Invoked[#world.commF.Invoked]
    eq("requestEntrance sent", call[1], "requestEntrance")
    near("to the portal position", call[2], CASTLE)
    check("busy while the jump happens", Router.busy())
    check("movement holds still while busy", Router.update(Vector3.new(0, 0, 0), goal, 300))
    stepTasks()
    check("jump done", not Router.busy())
    check("portal confirmed", Router.describe():find("Castle on the Sea: works", 1, true) ~= nil, Router.describe())
    local handled = Router.update(CASTLE, goal, 300)
    check("close goal after the jump: normal flight", not handled)
    local cooling = Router.plan(Vector3.new(0, 0, 0), goal, 300)
    check("same portal not reused during its cooldown", cooling.name ~= "Castle on the Sea", cooling.name)
end

setup()
do
    game.PlaceId = 7449423635
    Entrances.reset({ DefeatedIndraTrueForm = true })
    Router.VERIFY_STEPS = 3
    Router.COOLDOWN = 0
    world.commF.OnInvoke = function() return nil end   -- the jump never happens
    local goal = CASTLE + Vector3.new(60, 0, 60)
    local function attempt()
        Router.update(Vector3.new(0, 0, 0), goal, 300)
        for _ = 1, 4 do stepTasks() end
        Router.update(Vector3.new(0, 0, 0), goal, 300)   -- the flying frame after a try
    end
    attempt()
    local text = Router.describe()
    check("one failure does not lock", text:find("Castle on the Sea: untested", 1, true) ~= nil, text)
    check("last attempt shown", text:find("no move", 1, true) ~= nil, text)
    attempt()
    check("two failures in a row lock", Router.describe():find("Castle on the Sea: locked", 1, true) ~= nil, Router.describe())
    local again = Router.plan(Vector3.new(0, 0, 0), goal, 300)
    check("locked portal no longer planned", again.name ~= "Castle on the Sea", again.name)
    Router.LOCK_TIME = 0
    check("lock expires", Router.plan(Vector3.new(0, 0, 0), goal, 300).name == "Castle on the Sea")
    Router.LOCK_TIME = 120
    Router.VERIFY_STEPS = 24
    Router.COOLDOWN = 4
end

-- The game lands the player on the destination's spawn, not on the point.
setup()
do
    game.PlaceId = 7449423635
    Entrances.reset({ DefeatedIndraTrueForm = true })
    local landing = CASTLE + Vector3.new(800, 0, 0)
    world.commF.OnInvoke = function(action)
        if action == "requestEntrance" then world.hrp.Position = landing end
        return true
    end
    Router.update(Vector3.new(0, 0, 0), landing + Vector3.new(50, 0, 0), 300)
    stepTasks()
    local text = Router.describe()
    check("off-point landing counts as a jump", text:find("Castle on the Sea: works", 1, true) ~= nil, text)
    check("distance moved shown", text:find("moved", 1, true) ~= nil, text)
end

setup()
do
    game.PlaceId = 7449423635
    Entrances.reset({})
    local island = Router.ISLAND + Vector3.new(100, 0, 0)
    local handled, aim = Router.update(Vector3.new(0, 0, 0), island, 300)
    check("submarine: fly to the worker first", not handled and aim ~= nil and (aim - Router.WORKER).Magnitude < 1)
    local net = rs.Modules.Net
    local worker = newInstance("RemoteFunction", "RF/SubmarineWorkerSpeak", net)
    check("at the worker: submarine taken", Router.update(Router.WORKER, island, 300))
    eq("worker asked to travel", worker.Invoked and worker.Invoked[1][1], "TravelToSubmergedIsland")
    stepTasks()

    Router.reset()
    local plan = Router.plan(Router.ISLAND, Vector3.new(0, 0, 0), 300)
    eq("leaving the island: submarine", plan.kind, "submarine")
    near("leaves from the dock", plan.dock, Router.DOCK)
end

setup()
do
    game.PlaceId = 1   -- no known sea: no portal competes with the respawn route
    Entrances.reset({})
    local far = Vector3.new(20000, 0, 20000)
    local spawns = folder("PlayerSpawns", folder("_WorldOrigin", workspace))
    local group = folder("Pirates", spawns)
    local spawnModel = newInstance("Model", "FarIsland", group)
    spawnModel.WorldPivot = CFrame.new(20100, 0, 20000)
    eq("respawn shortcut off by default", Router.plan(Vector3.new(0, 0, 0), far, 300).kind, "direct")
    Settings.set("RespawnShortcut", true)
    local plan = Router.plan(Vector3.new(0, 0, 0), far, 300)
    eq("respawn shortcut when enabled", plan.kind, "respawn")
    check("respawn at the spawn nearest the goal", plan.name:find("FarIsland", 1, true) ~= nil)
end

setup()
do
    game.PlaceId = 7449423635
    Entrances.reset({ DefeatedIndraTrueForm = true })
    world.commF.OnInvoke = function() return true end
    Movement.to(CFrame.new(CASTLE + Vector3.new(60, 0, 60)))
    Movement.step(1 / 60)
    near("movement waits for the portal instead of flying", world.hrp.Position, Vector3.new(0, 0, 0))
    check("status mentions the portal", (Router.note() or ""):find("Castle on the Sea", 1, true) ~= nil)

    Router.reset()
    Movement.reset()
    Movement.to(CFrame.new(100, 0, 0))
    Movement.step(1 / 60)
    near("short trip set in one go", world.hrp.Position, Vector3.new(100, 0, 0))
end

-- The user's case: Teleport tab to the Sea 3 Mansion, far away.
setup()
do
    game.PlaceId = 7449423635
    Entrances.reset(nil)   -- unlocks not read (or flag missing)
    world.commF.OnInvoke = function() return true end
    Travel.cancel()
    Travel.go("Mansion", Vector3.new(-12548.0, 337.0, -7481.0))
    Farm.tick()
    Movement.step(1 / 60)
    local sent = calls(world.commF, "requestEntrance")
    eq("teleport to the Mansion uses a portal", #sent, 1)
    near("the Mansion portal", sent[1] and sent[1][2] or Vector3.new(), Vector3.new(-12463.9, 374.9, -7523.8))
    check("status names the portal", Farm.status():find("Turtle Mansion", 1, true) ~= nil, Farm.status())
    Travel.cancel()
    Farm.stop()
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
end

-- Why a trip flies directly.
setup()
do
    game.PlaceId = 123456789
    Player.resetSea()
    local plan = Router.plan(Vector3.new(0, 0, 0), Vector3.new(9000, 0, 0), 300)
    check("reason: no portal for this sea", plan.reason and plan.reason:find("no portal known", 1, true) ~= nil, plan.reason)

    game.PlaceId = 7449423635
    Entrances.reset({ DefeatedIndraTrueForm = true })
    local near1 = Router.plan(Vector3.new(0, 0, 0), Vector3.new(1600, 0, 0), 300)
    eq("medium trip flies", near1.kind, "direct")
    check("reason: saving too small", near1.reason and near1.reason:find("saves only", 1, true) ~= nil, near1.reason)
    Router.update(Vector3.new(0, 0, 0), Vector3.new(1600, 0, 0), 300)
    check("note starts with flying", (Router.note() or ""):find("flying:", 1, true) == 1, Router.note())
end

-- Test portals: one request per portal, each result recorded.
setup()
do
    game.PlaceId = 4442272183
    Entrances.reset({})
    Router.VERIFY_STEPS = 2
    local moved = 0
    world.commF.OnInvoke = function(action)
        if action == "requestEntrance" then
            moved = moved + 1
            if moved == 1 then world.hrp.Position = Vector3.new(923, 127, 32852) end
        end
        return true
    end
    local done = false
    check("test started", Router.testAll(function() done = true end))
    check("second test refused while running", not Router.testAll())
    for _ = 1, 20 do stepTasks() end
    check("test finished", done)
    eq("one request per portal", #calls(world.commF, "requestEntrance"), #Entrances.POINTS[2])
    local text = Router.describe()
    check("working portal reported", text:find("Cursed Ship: works", 1, true) ~= nil, text)
    check("failed portal reported", text:find("no move", 1, true) ~= nil, text)
    Router.VERIFY_STEPS = 24
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
