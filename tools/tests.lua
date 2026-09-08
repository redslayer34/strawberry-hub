--=============================================================================
-- TESTS — verifient le COMPORTEMENT, pas seulement la syntaxe
--=============================================================================
--  Execute par tools/test.py : les stubs sont charges, puis le bundle (dont
--  la ligne d'entree a ete retiree), puis ce fichier. `require` est donc en
--  portee et resout les vrais modules.
--
--  Les cas testes sont ceux ou une regression serait silencieuse en jeu :
--  la stricte egalite des noms, l'exclusion des boss, le regroupement, les
--  timeouts, l'invalidation des caches.
--=============================================================================

local passed, failed = 0, 0
local failures = {}

local function check(name, condition, detail)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = name .. (detail and ("  -- " .. tostring(detail)) or "")
    end
end

local function eq(name, actual, expected)
    check(name, actual == expected,
        string.format("attendu %s, obtenu %s", tostring(expected), tostring(actual)))
end

---------------------------------------------------------------------------
-- 1. Chargement de tous les modules
---------------------------------------------------------------------------

local MODULES = {
    "AutomationCore.Log", "AutomationCore.Names", "AutomationCore.Cache",
    "AutomationCore.Trust", "AutomationCore.DynamicMapCache",
    "AutomationCore.StateMachine", "AutomationCore.Config",
    "AutomationCore.Context",
    "AutomationCore.Perception", "AutomationCore.Perception.SeaDetector",
    "AutomationCore.Perception.IslandDetector",
    "AutomationCore.Perception.QuestDetector",
    "AutomationCore.Perception.QuestGiverResolver",
    "AutomationCore.Perception.EnemyScanner",
    "AutomationCore.Perception.SpawnClusterResolver",
    "AutomationCore.Movement.TravelController",
    "AutomationCore.Movement.QuestTravel",
    "AutomationCore.Movement.TargetTravel",
    "AutomationCore.Movement.SafeCombatAnchor",
    "AutomationCore.Combat.TargetValidator",
    "AutomationCore.Combat.BringController",
    "AutomationCore.Combat.AttackController",
    "AutomationCore.Combat.CombatPositionController",
    "AutomationCore.Farming.QuestFarm", "AutomationCore.Farming.BossFarm",
    "AutomationCore.Farming.MasteryFarm", "AutomationCore.Farming.MaterialFarm",
    "AutomationCore.Farming.ServerHop", "AutomationCore.Farming.SpecialFarm",
    "AutomationCore.Farming.TargetedFarm", "AutomationCore.Farming.RoutePlanner",
    "AutomationCore.Recovery.RecoveryController",
    "AutomationCore.SpecialObjectives.CDKController",
    "AutomationCore",
}

for _, name in ipairs(MODULES) do
    local ok, err = pcall(require, name)
    check("charge " .. name, ok, err)
end

local Names = require("AutomationCore.Names")
local Cache = require("AutomationCore.Cache")
local Trust = require("AutomationCore.Trust")
local Log = require("AutomationCore.Log")
local StateMachine = require("AutomationCore.StateMachine")
local Context = require("AutomationCore.Context")
local QuestDetector = require("AutomationCore.Perception.QuestDetector")
local SpawnClusterResolver = require("AutomationCore.Perception.SpawnClusterResolver")
local TargetValidator = require("AutomationCore.Combat.TargetValidator")
local BringController = require("AutomationCore.Combat.BringController")

Log.setEnabled(false)   -- les tests n'ont pas besoin du journal

---------------------------------------------------------------------------
-- 2. Normalisation des noms
---------------------------------------------------------------------------

eq("normalize pluriel simple", Names.normalize("Desert Bandits"), "desert bandit")
eq("normalize casse et espaces", Names.normalize("  DESERT   bandit "), "desert bandit")
eq("normalize -men", Names.normalize("Fishmen Warriors"), "fishman warrior")
eq("normalize article de tete", Names.normalize("The Saw"), "saw")
eq("normalize apostrophe", Names.normalize("God's Guard"), "god s guard")
eq("normalize -ss protege", Names.normalize("Boss"), "boss")
eq("normalize vide", Names.normalize("   "), nil)
eq("normalize non-chaine", Names.normalize(42), nil)

check("matches singulier/pluriel", Names.matches("Desert Bandits", "Desert Bandit"))
check("matches casse", Names.matches("desert bandit", "Desert Bandit"))

-- Le coeur de la regle absolue : une correspondance partielle ne passe pas.
check("REJETTE sous-chaine", not Names.matches("Bandit", "Desert Bandit"))
check("REJETTE sur-chaine", not Names.matches("Desert Bandit Chief", "Desert Bandit"))
check("REJETTE mot proche", not Names.matches("Desert Officer", "Desert Bandit"))

---------------------------------------------------------------------------
-- 3. Cache : expiration, validateur, invalidation
---------------------------------------------------------------------------

local c = Cache.new({ name = "t", ttl = 0.05 })
c:set("valeur")
eq("cache rend la valeur", c:get(), "valeur")
local t0 = os.clock()
while os.clock() - t0 < 0.06 do end
eq("cache expire", c:get(), nil)

local alive = true
local guarded = Cache.new({ validator = function() return alive end })
guarded:set("x")
eq("validateur vrai", guarded:get(), "x")
alive = false
eq("validateur faux", guarded:get(), nil)
eq("invalidation comptee", guarded.invalidations, 1)

---------------------------------------------------------------------------
-- 4. Hierarchie de confiance
---------------------------------------------------------------------------

local value, level = Trust.resolve("test", {
    { level = Trust.LEVEL.STATIC_FALLBACK, why = "figee", get = function() return "vieille" end },
    { level = Trust.LEVEL.LIVE_ENTITY, why = "vivante", get = function() return "fraiche" end },
})
eq("Trust prefere la source la plus sure", value, "fraiche")
eq("Trust rend le niveau", level, Trust.LEVEL.LIVE_ENTITY)

local fallbackValue, fallbackLevel = Trust.resolve("test", {
    { level = Trust.LEVEL.LIVE_ENTITY, get = function() return nil end },
    { level = Trust.LEVEL.STATIC_FALLBACK, why = "figee", get = function() return "vieille" end },
})
eq("Trust retombe sur le repli", fallbackValue, "vieille")
check("Trust signale le mode degrade", Trust.isDegraded(fallbackLevel))

---------------------------------------------------------------------------
-- 5. Machine a etats : transitions, timeout, historique
---------------------------------------------------------------------------

local trace = {}
local sm = StateMachine.new("test", {})
sm:defineAll({
    A = { update = function() return "B" end, exit = function() trace[#trace + 1] = "exitA" end },
    B = {
        timeout = 0.02,
        onTimeout = "C",
        enter = function() trace[#trace + 1] = "enterB" end,
        update = function() return nil end,
    },
    C = { update = function() return nil end },
    RECOVERY = { update = function() return nil end },
})

sm:goTo("A")
sm:update()
eq("transition A -> B", sm.current, "B")
check("exit appele", trace[1] == "exitA")
check("enter appele", trace[2] == "enterB")

local t1 = os.clock()
while os.clock() - t1 < 0.03 do end
sm:update()
eq("timeout declenche", sm.current, "C")

-- Une erreur dans update ne doit pas remonter : elle bascule en RECOVERY.
sm:define("BOOM", { update = function() error("panne simulee") end })
sm:goTo("BOOM")
sm:update()
eq("erreur -> RECOVERY", sm.current, "RECOVERY")

-- Un etat inconnu retombe sur RECOVERY. C'est le filet qui rend un mauvais
-- cablage visible plutot que silencieux : un mode dont l'etat RECOVERY
-- renvoie un nom qu'il ne definit pas boucle ici sans jamais avancer.
sm:goTo("C")
sm:goTo("ETAT_INEXISTANT")
eq("etat inconnu -> RECOVERY", sm.current, "RECOVERY")

-- L'historique doit permettre a la recuperation de savoir d'ou elle vient.
check("historique renseigne", #sm:recent(3) > 0)
check("dernier etat retrouvable",
    sm:lastWhere(function(name) return name == "C" end) == "C")

---------------------------------------------------------------------------
-- 6. Contexte + lecture reelle de la quete
---------------------------------------------------------------------------

local player = newInstance("Player", "LocalPlayer")
local data = newInstance("Folder", "Data", player)
local levelValue = newInstance("IntValue", "Level", data)
levelValue.Value = 75

local gui = newInstance("Folder", "PlayerGui", player)
local main = newInstance("Frame", "Main", gui)
local questFrame = newInstance("Frame", "Quest", main)
questFrame.Visible = true

local container = newInstance("Frame", "Container", questFrame)
local questTitle = newInstance("Frame", "QuestTitle", container)
local title = newInstance("TextLabel", "Title", questTitle)
title.Text = "Bandit Hunter"
local objective = newInstance("TextLabel", "Objective", questFrame)
objective.Text = "Defeat 8 Desert Bandits"
local progress = newInstance("TextLabel", "Progress", questFrame)
progress.Text = "3/8"

local enemiesFolder = newInstance("Folder", "Enemies", workspace)
local npcsFolder = newInstance("Folder", "NPCs", workspace)

local internal = {
    Config = {
        Farming = {
            BringMob = false, SafeMode = true, SafeDistance = 4,
            AttackHeight = 10, UseAutomationCore = true,
        },
        Materials = { ["Leather"] = { mobs = { "Jungle Pirate" } } },
        Quests = {},
    },
    State = { flags = { AutoFarm = false } },
    Util = {},
    Core = {
        character = function() return nil end,
        hrp = function() return { Position = Vector3.new(0, 20, 0) } end,
        humanoid = function() return nil end,
        alive = function() return true end,
        level = function() return 75 end,
    },
    Remote = { invoke = function() end },
    Move = {
        tweenTo = function() end, snapTo = function() end,
        stopTween = function() end, faceTarget = function() end,
    },
    Attack = {
        strike = function() end, equip = function() end,
        releaseHold = function() end, ready = function() return true end,
    },
    Enemies = {}, Quests = {}, Farming = {},
    Server = { hop = function() end, rejoin = function() end },
    Teleport = { toIsland = function() end, toSea = function() end },
    Diagnostics = {},
    Player = player,
}

local ctx = Context.new(internal)

check("contexte trouve le cadre de quete", ctx.world.questFrame() == questFrame)
eq("contexte lit le niveau", ctx.player.level(), 75)

local quest = QuestDetector.read(ctx)
check("quete active", quest.Active)
eq("titre lu", quest.QuestName, "Bandit Hunter")
eq("cible extraite", quest.TargetName, "desert bandit")
eq("cible brute conservee", quest.TargetRaw, "Desert Bandits")
eq("compte requis", quest.RequiredCount, 8)
eq("compte courant", quest.CurrentCount, 3)
eq("restant", quest.Remaining, 5)
check("pas une quete de boss", not quest.IsBossQuest)

-- Objectif portant sa progression en ligne.
objective.Text = "Defeat 5 Snow Bandits [2/5]"
progress.Text = ""
local inline = QuestDetector.read(ctx)
eq("cible malgre progression en ligne", inline.TargetName, "snow bandit")
eq("compte requis en ligne", inline.RequiredCount, 5)
eq("compte courant en ligne", inline.CurrentCount, 2)

-- Cadre masque : aucune quete, aucun objectif.
questFrame.Visible = false
local hidden = QuestDetector.read(ctx)
check("cadre masque = pas de quete", not hidden.Active)
eq("aucune cible sans quete", hidden.TargetName, nil)
questFrame.Visible = true
objective.Text = "Defeat 8 Desert Bandits"
progress.Text = "3/8"

---------------------------------------------------------------------------
-- 7. Validation stricte des cibles
---------------------------------------------------------------------------

local function makeMob(name, health, maxHealth, position, parent)
    local model = newInstance("Model", name, parent or enemiesFolder)
    local humanoid = newInstance("Humanoid", "Humanoid", model)
    humanoid.Health = health
    humanoid.MaxHealth = maxHealth or 1000
    local root = newInstance("Part", "HumanoidRootPart", model)
    root.Position = position or Vector3.new(0, 0, 0)
    return {
        model = model, humanoid = humanoid, root = root,
        name = name, canonical = Names.normalize(name),
        position = root.Position, health = health, maxHealth = humanoid.MaxHealth,
    }
end

local activeQuest = QuestDetector.read(ctx)
ctx.region = nil

local good = makeMob("Desert Bandit", 500, 1000, Vector3.new(10, 0, 10))
check("cible correcte acceptee", TargetValidator.isValidQuestTarget(ctx, good, activeQuest))

local wrongName = makeMob("Desert Officer", 500, 1000, Vector3.new(12, 0, 10))
check("REJETTE nom different",
    not TargetValidator.isValidQuestTarget(ctx, wrongName, activeQuest))

local partial = makeMob("Bandit", 500, 1000, Vector3.new(14, 0, 10))
check("REJETTE nom partiel",
    not TargetValidator.isValidQuestTarget(ctx, partial, activeQuest))

-- Direction inverse, et la plus dangereuse : le nom du mob CONTIENT la cible.
-- Un `find` a la place de l'egalite laisserait passer celui-la sans que rien
-- ne le signale en jeu.
local superstring = makeMob("Desert Bandit Chief", 500, 1000, Vector3.new(15, 0, 10))
check("REJETTE nom contenant la cible",
    not TargetValidator.isValidQuestTarget(ctx, superstring, activeQuest))

-- Meme piege du cote du prefixe.
local prefixed = makeMob("Elite Desert Bandit", 500, 1000, Vector3.new(15, 0, 12))
check("REJETTE nom prefixe",
    not TargetValidator.isValidQuestTarget(ctx, prefixed, activeQuest))

local dead = makeMob("Desert Bandit", 0, 1000, Vector3.new(16, 0, 10))
check("REJETTE mob mort",
    not TargetValidator.isValidQuestTarget(ctx, dead, activeQuest))

-- Boss : meme nom, mais reserve de vie de boss et quete non-boss.
local boss = makeMob("Desert Bandit", 90000, 90000, Vector3.new(18, 0, 10))
check("REJETTE boss hors quete de boss",
    not TargetValidator.isValidQuestTarget(ctx, boss, activeQuest))

-- Le meme boss devient valide quand la quete le designe explicitement.
local bossQuest = {
    Active = true, TargetName = "desert bandit", RequiredCount = 1,
    Remaining = 1, IsBossQuest = true, AllowBoss = true,
}
check("ACCEPTE boss quand la quete le demande",
    TargetValidator.isValidQuestTarget(ctx, boss, bossQuest))

-- PNJ de quete : meme nom, mais dans le dossier NPCs.
local npc = makeMob("Desert Bandit", 500, 1000, Vector3.new(20, 0, 10), npcsFolder)
check("REJETTE pnj de quete",
    not TargetValidator.isValidQuestTarget(ctx, npc, activeQuest))

-- Objectif illisible : aucune cible ne doit passer. C'est le trou qui
-- faisait aspirer toute la zone entre deux cibles.
local noObjective = { Active = true, TargetName = nil, RequiredCount = 0 }
check("REJETTE tout si objectif inconnu",
    not TargetValidator.isValidQuestTarget(ctx, good, noObjective))

-- Filtre de region.
ctx.region = { center = Vector3.new(0, 0, 0), radius = 50, count = 5, stamp = os.clock() }
local faraway = makeMob("Desert Bandit", 500, 1000, Vector3.new(5000, 0, 0))
check("REJETTE hors region",
    not TargetValidator.isValidQuestTarget(ctx, faraway, activeQuest))
check("ACCEPTE dans la region",
    TargetValidator.isValidQuestTarget(ctx, good, activeQuest))
ctx.region = nil

-- filter() ne laisse passer que les valides.
local filtered = TargetValidator.filter(ctx,
    { good, wrongName, partial, superstring, prefixed, dead, boss }, activeQuest)
eq("filter ne garde que la bonne cible", #filtered, 1)
check("filter garde la bonne", filtered[1] == good)

---------------------------------------------------------------------------
-- 8. Regroupement de spawn
---------------------------------------------------------------------------

local entries = {}
-- Paquet dense, proche.
for i = 1, 8 do
    entries[#entries + 1] = { position = Vector3.new(100 + i * 5, 0, 100 + i * 5) }
end
-- Paquet clairseme, lointain.
for i = 1, 2 do
    entries[#entries + 1] = { position = Vector3.new(3000 + i * 5, 0, 3000) }
end

local region = SpawnClusterResolver.resolve(ctx, entries, Vector3.new(0, 0, 0))
check("region trouvee", region ~= nil)
eq("deux groupes distincts", region.groups, 2)
eq("le groupe dense est retenu", region.count, 8)
check("centre sur le groupe dense", region.center.X < 1000)

check("contains accepte un point du groupe",
    SpawnClusterResolver.contains(ctx, region, Vector3.new(120, 0, 120)))
check("contains refuse un point lointain",
    not SpawnClusterResolver.contains(ctx, region, Vector3.new(4000, 0, 4000)))

-- Aucune entree : pas de region inventee.
eq("aucune region sans cible", SpawnClusterResolver.resolve(ctx, {}, nil), nil)

---------------------------------------------------------------------------
-- 9. Emplacements de bring distincts
---------------------------------------------------------------------------

local bring = BringController.new(ctx)
local anchor = CFrame.new(Vector3.new(0, 50, 0))
local seen = {}
local distinct = true
for i = 1, ctx.cfg.Bring.MaxTargets do
    local pos = bring:slotPosition(anchor, i)
    local key = string.format("%.2f/%.2f", pos.X, pos.Z)
    if seen[key] then distinct = false end
    seen[key] = true
end
check("chaque emplacement de bring est distinct", distinct)

local first = bring:slotPosition(anchor, 1)
local second = bring:slotPosition(anchor, 2)
check("les emplacements sont espaces", (first - second).Magnitude > 1)
check("les mobs sont places sous l'ancre", first.Y < anchor.Position.Y)

---------------------------------------------------------------------------
-- 10. Memoire de carte : vidange au changement de contexte
---------------------------------------------------------------------------

ctx.map:put("QuestGivers", "cle", Vector3.new(1, 2, 3))
check("memoire ecrite", ctx.map:get("QuestGivers", "cle") ~= nil)

ctx.map:syncContext("job-1", 1, "Desert")
ctx.map:put("QuestGivers", "cle", Vector3.new(1, 2, 3))
ctx.map:syncContext("job-2", 1, "Desert")
eq("memoire videe au changement de serveur", ctx.map:get("QuestGivers", "cle"), nil)

ctx.map:put("QuestGivers", "cle", Vector3.new(1, 2, 3))
ctx.map:syncContext("job-2", 1, "Jungle")
eq("memoire videe au changement d'ile", ctx.map:get("QuestGivers", "cle"), nil)

---------------------------------------------------------------------------
-- Bilan
---------------------------------------------------------------------------

print(string.format("\n%d reussis, %d echoues", passed, failed))
if failed > 0 then
    print("\nEchecs :")
    for _, name in ipairs(failures) do print("  x " .. name) end
    os.exit(1)
end
print("tout est vert")
