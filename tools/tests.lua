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

---------------------------------------------------------------------------
-- Modules load
---------------------------------------------------------------------------

local MODULES = {
    "Core.Services", "Core.Settings", "Core.Loop", "Core.Player",
    "Game.Quests", "Game.Enemies", "Game.Movement", "Game.Combat", "Game.Bring",
    "Features.LevelFarm", "Features.Farm",
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

    world.questPanel.Visible = true
    world.guide.Data.QuestData = { Task = { Zombie = 8 } }
    check("quest panel visible", Quests.active())
    local target = Quests.target()
    eq("active quest mob", target and target.mob, "Zombie")
    eq("active quest count", target and target.count, 8)

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
-- Report
---------------------------------------------------------------------------

Loop.stopAll()
clearTasks()

print(string.format("core: %d passed, %d failed", passed, failed))
for _, failure in ipairs(failures) do print("  FAIL " .. failure) end
if failed > 0 then os.exit(1) end
