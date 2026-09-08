--[[
    Strawberry Hub — Blox Fruits
    ===========================================================================
    Refactored merge of three sources (repeat / redz / "if getgenv").

    Engine only. The window is built by Runtime.Interface on top of the
    StrawberryUI library; this file owns no presentation code and exposes its
    primitives through StrawberryHub.Internal.

    No hostile code: no backdoor, no kick trap, no anti-cheat bypass.

    Modules: Config · Util · Diagnostics · Persist · Core · Remote · Move
             Attack · Enemies · Quests · Farming · Combat · Materials
             Teleport · Shop · Player · Performance · AntiDetection
             Server · Events · FastAttack
]]

--=============================================================================
-- RELOAD GUARD
--=============================================================================
if getgenv().StrawberryHub then
    pcall(function() getgenv().StrawberryHub.Unload() end)
end

--=============================================================================
-- CONFIG — every tunable value. No magic numbers anywhere else.
--=============================================================================
local Config = {
    Debug = false,

    Farming = {
        Mode = "Quest",            -- "Quest" | "No Quest"
        AttackHeight = 10,         -- hauteur au-dessus du mob (hors de portee de ses coups)
        AttackBack = 2,            -- recul derriere le mob
        TweenSpeed = 200,          -- studs/s
        MaxTweenSpeed = 200,       -- plafond dur : au-dela l'anti-triche detecte
        SnapDistance = 250,        -- en dessous : teleport direct
        BringMob = false,
        BringHeight = 12,          -- hauteur a laquelle les mobs sont amenes
        BringDistance = 250,       -- rayon de collecte des mobs a ramener
        BringQuestOnly = true,     -- ne ramener que les mobs de la cible en cours
        BringInterval = 0.1,       -- s entre deux repositionnements (anti-rebond)
        RetweenThreshold = 8,      -- on ne relance un tween que si la cible bouge de +8
        WeaponType = "Melee",   -- "Auto (arme en main)" | Melee | Sword | Gun | Blox Fruit | nom precis
        SafeMode = true,           -- ne modifie AUCUN etat des mobs (recommande)
        SafeDistance = 4,          -- distance laterale de frappe en mode sur
        EngageTimeout = 8,         -- s sans degat avant d'abandonner une cible
        RespawnWait = 3,           -- secondes apres la mort avant de reprendre

        -- Drives the farm through the AutomationCore (dynamic detection, state
        -- machine, recovery) instead of the historical loop built on the frozen
        -- CFrame table. That table stays available as a last resort.
        UseAutomationCore = true,
    },

    Combat = {
        SelectedTarget = nil,
        AuraRange = 60,
        HitboxRange = 60,    -- portee de hitbox forcee sur le controleur
        AttackDelay = 0.1,   -- secondes entre deux passes de fast attack
        Method = "Auto",     -- Auto | Controller | Remote | RemoteRaw
        CalibrateSeconds = 2, -- secondes sans degat avant de tester la strategie suivante
    },

    Player = {
        AutoHaki = true,
        AntiAFK = true,
        Stats = { Melee = false, Defense = false, Sword = false, Gun = false, Fruit = false },
        StatsPerTick = 3,
    },

    -- Central Fast Attack configuration (see the module further down).
    FastAttack = {
        Enabled = true,
        Interval = 0.05,      -- delai entre deux attaques (s)
        IdleInterval = 0.15,  -- delai quand aucune cible n'est a portee
        MaxBackoff = 0.5,     -- ralentissement max apres des refus repetes
        Range = 50,           -- portee de recherche des cibles
        MaxTargets = 15,      -- cibles frappees par attaque (multi-hit)
        NoAnimation = true,   -- masque les animations de combat (client)
        SwingDelay = 0.4,     -- 1er argument de RegisterAttack
    },

    Loops = {
        Farm = 0.05,
        Combat = 0.1,
        Material = 0.2,
        Stats = 0.5,
        Shop = 0.3,
        SeaBeast = 0.5,
    },

    Places = {
        [2753915549] = 1, [100117331123089] = 1,
        [4442272183] = 2, [79091703265657]  = 2,
        [7449423635] = 3, [85211729168715]  = 3,
    },

    Travel = { [1] = "TravelMain", [2] = "TravelDressrosa", [3] = "TravelZou" },

    FightingStyles = {
        { name = "Black Leg",       remote = "BuyBlackLeg",       npc = "Dark Step Teacher" },
        { name = "Fishman Karate",  remote = "BuyFishmanKarate",  npc = "Water Kung-fu Teacher" },
        { name = "Electro",         remote = "BuyElectro",        npc = "Mad Scientist" },
        { name = "SuperHuman",      remote = "BuySuperhuman",     npc = "Martial Arts Master" },
        { name = "Death Step",      remote = "BuyDeathStep",      npc = "Phoeyu, the Reformed" },
        { name = "Sharkman Karate", remote = "BuySharkmanKarate", npc = "Sharkman Teacher" },
        { name = "Electric Claw",   remote = "BuyElectricClaw",   npc = "Previous Hero" },
        { name = "Dragon Talon",    remote = "BuyDragonTalon",    npc = "Uzoth" },
        { name = "God Human",       remote = "BuyGodhuman",       npc = "Ancient Monk" },
        { name = "Sanguine Art",    remote = "BuySanguineArt",    npc = "Shafi" },
    },

    Abilities = {
        { name = "Geppo  [10,000]",        args = { "BuyHaki", "Geppo" } },
        { name = "Buso Haki  [25,000]",    args = { "BuyHaki", "Buso" } },
        { name = "Soru  [100,000]",        args = { "BuyHaki", "Soru" } },
        { name = "Observation  [750,000]", args = { "KenTalk", "Buy" } },
    },

    Materials = {
        ["Ectoplasm"]            = { mobs = { "Ship Deckhand", "Ship Engineer", "Ship Steward", "Ship Officer", "Cursed Captain" } },
        ["Magma Ore"]            = { mobs = { "Lava Pirate", "Magma Ninja" } },
        ["Leather"]              = { mobs = { "Jungle Pirate", "Musketeer Pirate" } },
        ["Scrap Metal"]          = { mobs = { "Jungle Pirate" } },
        ["Angel Wings"]          = { mobs = { "God's Guard", "Shanda", "Royal Squad", "Royal Soldier" } },
        ["Fish Tail"]            = { mobs = { "Fishman Raider", "Fishman Captain" } },
        ["Radioactive Material"] = { mobs = { "Factory Staff" } },
        ["Vampire Fang"]         = { mobs = { "Vampire" } },
        ["Mystic Droplet"]       = { mobs = { "Sea Soldier", "Water Fighter" } },
        ["Mini Tusk"]            = { mobs = { "Mythological Pirate" } },
        ["Gunpowder"]            = { mobs = { "Pistol Billionaire" } },
        ["Demonic Wisp"]         = { mobs = { "Demonic Soul" } },
        ["Dragon Scale"]         = { mobs = { "Dragon Crew Archer", "Dragon Crew Warrior" } },
        ["Conjured Cocoa"]       = { mobs = { "Cocoa Warrior", "Chocolate Bar Battler" } },
        ["Bones"]                = { mobs = { "Reborn Skeleton", "Demonic Soul", "Living Zombie", "Posessed Mummy" } },
    },

    Codes = {
        "SUB2GAMERROBOT_EXP1", "StrawHatMaine", "Sub2OfficialNoobie", "THEGREATACE",
        "SUB2NOOBMASTER123", "Sub2Daigrock", "Axiore", "TantaiGaming", "Bluxxy",
        "3BVISITS", "UPD16", "Sub2Fer999", "Enyu_is_Pro", "JCWK", "StarcodeHEO",
        "MagicBUS", "KittGaming", "Sub2CaptainMaui", "CODESLIDE", "NOOB2ADMIN",
        "NOEXPLOIT", "FIGHT4FRUIT", "EARN_FRUITS", "EXP_5B",
    },

    -- The game's detection/ban/kick remotes to intercept (by tag or name).
    AntiDetection = {
        Enabled = true,
        DisableAbuseScreenshots = true,
        Remotes = {
            "TeleportDetect", "CHECKER", "CHECKER_1", "GUI_CHECK",
            "OneMoreTime", "checkingSPEED", "BANREMOTE", "PERMAIDBAN",
            "KICKREMOTE", "BR_KICKPC", "BR_KICKMOBILE",
        },
    },

    -- Instrumentation. Off by default: when Enabled is false, each probe
    -- costs a single boolean test.
    Diagnostics = {
        Enabled = false,
    },

    Persist = { Folder = "StrawberryHub", File = "settings.json" },


    -- 84 progression bands (sea / level / quest / positions)
    Quests = {
		{ Sea=1, Min=1, Max=9, Name="Bandit", Quest="BanditQuest1", QLevel=1, QCF=CFrame.new(1059.37195, 15.4495068, 1550.4231, 0.939700544, -0, -0.341998369, 0, 1, -0, 0.341998369, 0, 0.939700544), MonCF=CFrame.new(1045.962646484375, 27.00250816345215, 1560.8203125) },
		{ Sea=1, Min=10, Max=14, Name="Monkey", Quest="JungleQuest", QLevel=1, QCF=CFrame.new(-1598.08911, 35.5501175, 153.377838, 0, 0, 1, 0, 1, -0, -1, 0, 0), MonCF=CFrame.new(-1448.51806640625, 67.85301208496094, 11.46579647064209) },
		{ Sea=1, Min=15, Max=29, Name="Gorilla", Quest="JungleQuest", QLevel=2, QCF=CFrame.new(-1598.08911, 35.5501175, 153.377838, 0, 0, 1, 0, 1, -0, -1, 0, 0), MonCF=CFrame.new(-1129.8836669921875, 40.46354675292969, -525.4237060546875) },
		{ Sea=1, Min=30, Max=39, Name="Pirate", Quest="BuggyQuest1", QLevel=1, QCF=CFrame.new(-1141.07483, 4.10001802, 3831.5498, 0.965929627, -0, -0.258804798, 0, 1, -0, 0.258804798, 0, 0.965929627), MonCF=CFrame.new(-1103.513427734375, 13.752052307128906, 3896.091064453125) },
		{ Sea=1, Min=40, Max=59, Name="Brute", Quest="BuggyQuest1", QLevel=2, QCF=CFrame.new(-1141.07483, 4.10001802, 3831.5498, 0.965929627, -0, -0.258804798, 0, 1, -0, 0.258804798, 0, 0.965929627), MonCF=CFrame.new(-1140.083740234375, 14.809885025024414, 4322.92138671875) },
		{ Sea=1, Min=60, Max=74, Name="Desert Bandit", Quest="DesertQuest", QLevel=1, QCF=CFrame.new(894.488647, 5.14000702, 4392.43359, 0.819155693, -0, -0.573571265, 0, 1, -0, 0.573571265, 0, 0.819155693), MonCF=CFrame.new(924.7998046875, 6.44867467880249, 4481.5859375) },
		{ Sea=1, Min=75, Max=89, Name="Desert Officer", Quest="DesertQuest", QLevel=2, QCF=CFrame.new(894.488647, 5.14000702, 4392.43359, 0.819155693, -0, -0.573571265, 0, 1, -0, 0.573571265, 0, 0.819155693), MonCF=CFrame.new(1608.2822265625, 8.614224433898926, 4371.00732421875) },
		{ Sea=1, Min=90, Max=99, Name="Snow Bandit", Quest="SnowQuest", QLevel=1, QCF=CFrame.new(1389.74451, 88.1519318, -1298.90796, -0.342042685, 0, 0.939684391, 0, 1, 0, -0.939684391, 0, -0.342042685), MonCF=CFrame.new(1354.347900390625, 87.27277374267578, -1393.946533203125) },
		{ Sea=1, Min=100, Max=119, Name="Snowman", Quest="SnowQuest", QLevel=2, QCF=CFrame.new(1389.74451, 88.1519318, -1298.90796, -0.342042685, 0, 0.939684391, 0, 1, 0, -0.939684391, 0, -0.342042685), MonCF=CFrame.new(1201.6412353515625, 144.57958984375, -1550.0670166015625) },
		{ Sea=1, Min=120, Max=149, Name="Chief Petty Officer", Quest="MarineQuest2", QLevel=1, QCF=CFrame.new(-5039.58643, 27.3500385, 4324.68018, 0, 0, -1, 0, 1, 0, 1, 0, 0), MonCF=CFrame.new(-4881.23095703125, 22.65204429626465, 4273.75244140625) },
		{ Sea=1, Min=150, Max=174, Name="Sky Bandit", Quest="SkyQuest", QLevel=1, QCF=CFrame.new(-4839.53027, 716.368591, -2619.44165, 0.866007268, 0, 0.500031412, 0, 1, 0, -0.500031412, 0, 0.866007268), MonCF=CFrame.new(-4953.20703125, 295.74420166015625, -2899.22900390625) },
		{ Sea=1, Min=175, Max=189, Name="Dark Master", Quest="SkyQuest", QLevel=2, QCF=CFrame.new(-4839.53027, 716.368591, -2619.44165, 0.866007268, 0, 0.500031412, 0, 1, 0, -0.500031412, 0, 0.866007268), MonCF=CFrame.new(-5259.8447265625, 391.3976745605469, -2229.035400390625) },
		{ Sea=1, Min=190, Max=209, Name="Prisoner", Quest="PrisonerQuest", QLevel=1, QCF=CFrame.new(5308.93115, 1.65517521, 475.120514, -0.0894274712, -5.00292918e-09, -0.995993316, 1.60817859e-09, 1, -5.16744869e-09, 0.995993316, -2.06384709e-09, -0.0894274712), MonCF=CFrame.new(5098.9736328125, -0.3204058110713959, 474.2373352050781) },
		{ Sea=1, Min=210, Max=249, Name="Dangerous Prisoner", Quest="PrisonerQuest", QLevel=2, QCF=CFrame.new(5308.93115, 1.65517521, 475.120514, -0.0894274712, -5.00292918e-09, -0.995993316, 1.60817859e-09, 1, -5.16744869e-09, 0.995993316, -2.06384709e-09, -0.0894274712), MonCF=CFrame.new(5654.5634765625, 15.633401870727539, 866.2991943359375) },
		{ Sea=1, Min=250, Max=274, Name="Toga Warrior", Quest="ColosseumQuest", QLevel=1, QCF=CFrame.new(-1580.04663, 6.35000277, -2986.47534, -0.515037298, 0, -0.857167721, 0, 1, 0, 0.857167721, 0, -0.515037298), MonCF=CFrame.new(-1820.21484375, 51.68385696411133, -2740.6650390625) },
		{ Sea=1, Min=275, Max=299, Name="Gladiator", Quest="ColosseumQuest", QLevel=2, QCF=CFrame.new(-1580.04663, 6.35000277, -2986.47534, -0.515037298, 0, -0.857167721, 0, 1, 0, 0.857167721, 0, -0.515037298), MonCF=CFrame.new(-1292.838134765625, 56.380882263183594, -3339.031494140625) },
		{ Sea=1, Min=300, Max=324, Name="Military Soldier", Quest="MagmaQuest", QLevel=1, QCF=CFrame.new(-5313.37012, 10.9500084, 8515.29395, -0.499959469, 0, 0.866048813, 0, 1, 0, -0.866048813, 0, -0.499959469), MonCF=CFrame.new(-5411.16455078125, 11.081554412841797, 8454.29296875) },
		{ Sea=1, Min=325, Max=374, Name="Military Spy", Quest="MagmaQuest", QLevel=2, QCF=CFrame.new(-5313.37012, 10.9500084, 8515.29395, -0.499959469, 0, 0.866048813, 0, 1, 0, -0.866048813, 0, -0.499959469), MonCF=CFrame.new(-5802.8681640625, 86.26241302490234, 8828.859375) },
		{ Sea=1, Min=375, Max=399, Name="Fishman Warrior", Quest="FishmanQuest", QLevel=1, QCF=CFrame.new(61122.65234375, 18.497442245483, 1569.3997802734), MonCF=CFrame.new(60878.30078125, 18.482830047607422, 1543.7574462890625), Entrance=Vector3.new(61163.8515625, 11.6796875, 1819.7841796875) },
		{ Sea=1, Min=400, Max=449, Name="Fishman Commando", Quest="FishmanQuest", QLevel=2, QCF=CFrame.new(61122.65234375, 18.497442245483, 1569.3997802734), MonCF=CFrame.new(61922.6328125, 18.482830047607422, 1493.934326171875), Entrance=Vector3.new(61163.8515625, 11.6796875, 1819.7841796875) },
		{ Sea=1, Min=450, Max=474, Name="God's Guard", Quest="SkyExp1Quest", QLevel=1, QCF=CFrame.new(-4721.88867, 843.874695, -1949.96643, 0.996191859, -0, -0.0871884301, 0, 1, -0, 0.0871884301, 0, 0.996191859), MonCF=CFrame.new(-4710.04296875, 845.2769775390625, -1927.3079833984375), Entrance=Vector3.new(-4607.82275, 872.54248, -1667.55688) },
		{ Sea=1, Min=475, Max=524, Name="Shanda", Quest="SkyExp1Quest", QLevel=2, QCF=CFrame.new(-7859.09814, 5544.19043, -381.476196, -0.422592998, 0, 0.906319618, 0, 1, 0, -0.906319618, 0, -0.422592998), MonCF=CFrame.new(-7678.48974609375, 5566.40380859375, -497.2156066894531), Entrance=Vector3.new(-7894.6176757813, 5547.1416015625, -380.29119873047) },
		{ Sea=1, Min=525, Max=549, Name="Royal Squad", Quest="SkyExp2Quest", QLevel=1, QCF=CFrame.new(-7906.81592, 5634.6626, -1411.99194, 0, 0, -1, 0, 1, 0, 1, 0, 0), MonCF=CFrame.new(-7624.25244140625, 5658.13330078125, -1467.354248046875) },
		{ Sea=1, Min=550, Max=624, Name="Royal Soldier", Quest="SkyExp2Quest", QLevel=2, QCF=CFrame.new(-7906.81592, 5634.6626, -1411.99194, 0, 0, -1, 0, 1, 0, 1, 0, 0), MonCF=CFrame.new(-7836.75341796875, 5645.6640625, -1790.6236572265625) },
		{ Sea=1, Min=625, Max=649, Name="Galley Pirate", Quest="FountainQuest", QLevel=1, QCF=CFrame.new(5259.81982, 37.3500175, 4050.0293, 0.087131381, 0, 0.996196866, 0, 1, 0, -0.996196866, 0, 0.087131381), MonCF=CFrame.new(5551.02197265625, 78.90135192871094, 3930.412841796875) },
		{ Sea=1, Min=650, Max=999999, Name="Galley Captain", Quest="FountainQuest", QLevel=2, QCF=CFrame.new(5259.81982, 37.3500175, 4050.0293, 0.087131381, 0, 0.996196866, 0, 1, 0, -0.996196866, 0, 0.087131381), MonCF=CFrame.new(5441.95166015625, 42.50205993652344, 4950.09375) },
		{ Sea=2, Min=700, Max=724, Name="Raider", Quest="Area1Quest", QLevel=1, QCF=CFrame.new(-429.543518, 71.7699966, 1836.18188, -0.22495985, 0, -0.974368095, 0, 1, 0, 0.974368095, 0, -0.22495985), MonCF=CFrame.new(-728.3267211914062, 52.779319763183594, 2345.7705078125) },
		{ Sea=2, Min=725, Max=774, Name="Mercenary", Quest="Area1Quest", QLevel=2, QCF=CFrame.new(-429.543518, 71.7699966, 1836.18188, -0.22495985, 0, -0.974368095, 0, 1, 0, 0.974368095, 0, -0.22495985), MonCF=CFrame.new(-1004.3244018554688, 80.15886688232422, 1424.619384765625) },
		{ Sea=2, Min=775, Max=799, Name="Swan Pirate", Quest="Area2Quest", QLevel=1, QCF=CFrame.new(638.43811, 71.769989, 918.282898, 0.139203906, 0, 0.99026376, 0, 1, 0, -0.99026376, 0, 0.139203906), MonCF=CFrame.new(1068.664306640625, 137.61428833007812, 1322.1060791015625) },
		{ Sea=2, Min=800, Max=874, Name="Factory Staff", Quest="Area2Quest", QLevel=2, QCF=CFrame.new(632.698608, 73.1055908, 918.666321, -0.0319722369, 8.96074881e-10, -0.999488771, 1.36326533e-10, 1, 8.92172336e-10, 0.999488771, -1.07732087e-10, -0.0319722369), MonCF=CFrame.new(73.07867431640625, 81.86344146728516, -27.470672607421875) },
		{ Sea=2, Min=875, Max=899, Name="Marine Lieutenant", Quest="MarineQuest3", QLevel=1, QCF=CFrame.new(-2440.79639, 71.7140732, -3216.06812, 0.866007268, 0, 0.500031412, 0, 1, 0, -0.500031412, 0, 0.866007268), MonCF=CFrame.new(-2821.372314453125, 75.89727783203125, -3070.089111328125) },
		{ Sea=2, Min=900, Max=949, Name="Marine Captain", Quest="MarineQuest3", QLevel=2, QCF=CFrame.new(-2440.79639, 71.7140732, -3216.06812, 0.866007268, 0, 0.500031412, 0, 1, 0, -0.500031412, 0, 0.866007268), MonCF=CFrame.new(-1861.2310791015625, 80.17658233642578, -3254.697509765625) },
		{ Sea=2, Min=950, Max=974, Name="Zombie", Quest="ZombieQuest", QLevel=1, QCF=CFrame.new(-5497.06152, 47.5923004, -795.237061, -0.29242146, 0, -0.95628953, 0, 1, 0, 0.95628953, 0, -0.29242146), MonCF=CFrame.new(-5657.77685546875, 78.96973419189453, -928.68701171875) },
		{ Sea=2, Min=975, Max=999, Name="Vampire", Quest="ZombieQuest", QLevel=2, QCF=CFrame.new(-5497.06152, 47.5923004, -795.237061, -0.29242146, 0, -0.95628953, 0, 1, 0, 0.95628953, 0, -0.29242146), MonCF=CFrame.new(-6037.66796875, 32.18463897705078, -1340.6597900390625) },
		{ Sea=2, Min=1000, Max=1049, Name="Snow Trooper", Quest="SnowMountainQuest", QLevel=1, QCF=CFrame.new(609.858826, 400.119904, -5372.25928, -0.374604106, 0, 0.92718488, 0, 1, 0, -0.92718488, 0, -0.374604106), MonCF=CFrame.new(549.1473388671875, 427.3870544433594, -5563.69873046875) },
		{ Sea=2, Min=1050, Max=1099, Name="Winter Warrior", Quest="SnowMountainQuest", QLevel=2, QCF=CFrame.new(609.858826, 400.119904, -5372.25928, -0.374604106, 0, 0.92718488, 0, 1, 0, -0.92718488, 0, -0.374604106), MonCF=CFrame.new(1142.7451171875, 475.6398010253906, -5199.41650390625) },
		{ Sea=2, Min=1100, Max=1124, Name="Lab Subordinate", Quest="IceSideQuest", QLevel=1, QCF=CFrame.new(-6064.06885, 15.2422857, -4902.97852, 0.453972578, -0, -0.891015649, 0, 1, -0, 0.891015649, 0, 0.453972578), MonCF=CFrame.new(-5707.4716796875, 15.951709747314453, -4513.39208984375) },
		{ Sea=2, Min=1125, Max=1174, Name="Horned Warrior", Quest="IceSideQuest", QLevel=2, QCF=CFrame.new(-6064.06885, 15.2422857, -4902.97852, 0.453972578, -0, -0.891015649, 0, 1, -0, 0.891015649, 0, 0.453972578), MonCF=CFrame.new(-6341.36669921875, 15.951770782470703, -5723.162109375) },
		{ Sea=2, Min=1175, Max=1199, Name="Magma Ninja", Quest="FireSideQuest", QLevel=1, QCF=CFrame.new(-5428.03174, 15.0622921, -5299.43457, -0.882952213, 0, 0.469463557, 0, 1, 0, -0.469463557, 0, -0.882952213), MonCF=CFrame.new(-5449.6728515625, 76.65874481201172, -5808.20068359375) },
		{ Sea=2, Min=1200, Max=1249, Name="Lava Pirate", Quest="FireSideQuest", QLevel=2, QCF=CFrame.new(-5428.03174, 15.0622921, -5299.43457, -0.882952213, 0, 0.469463557, 0, 1, 0, -0.469463557, 0, -0.882952213), MonCF=CFrame.new(-5213.33154296875, 49.73788070678711, -4701.451171875) },
		{ Sea=2, Min=1250, Max=1274, Name="Ship Deckhand", Quest="ShipQuest1", QLevel=1, QCF=CFrame.new(1037.80127, 125.092171, 32911.6016), MonCF=CFrame.new(1212.0111083984375, 150.79205322265625, 33059.24609375), Entrance=Vector3.new(923.21252441406, 126.9760055542, 32852.83203125) },
		{ Sea=2, Min=1275, Max=1299, Name="Ship Engineer", Quest="ShipQuest1", QLevel=2, QCF=CFrame.new(1037.80127, 125.092171, 32911.6016), MonCF=CFrame.new(919.4786376953125, 43.54401397705078, 32779.96875), Entrance=Vector3.new(923.21252441406, 126.9760055542, 32852.83203125) },
		{ Sea=2, Min=1300, Max=1324, Name="Ship Steward", Quest="ShipQuest2", QLevel=1, QCF=CFrame.new(968.80957, 125.092171, 33244.125), MonCF=CFrame.new(919.4385375976562, 129.55599975585938, 33436.03515625), Entrance=Vector3.new(923.21252441406, 126.9760055542, 32852.83203125) },
		{ Sea=2, Min=1325, Max=1349, Name="Ship Officer", Quest="ShipQuest2", QLevel=2, QCF=CFrame.new(968.80957, 125.092171, 33244.125), MonCF=CFrame.new(1036.0179443359375, 181.4390411376953, 33315.7265625), Entrance=Vector3.new(923.21252441406, 126.9760055542, 32852.83203125) },
		{ Sea=2, Min=1350, Max=1374, Name="Arctic Warrior", Quest="FrostQuest", QLevel=1, QCF=CFrame.new(5667.6582, 26.7997818, -6486.08984, -0.933587909, 0, -0.358349502, 0, 1, 0, 0.358349502, 0, -0.933587909), MonCF=CFrame.new(5966.24609375, 62.97002029418945, -6179.3828125), Entrance=Vector3.new(-6508.5581054688, 5000.034996032715, -132.83953857422) },
		{ Sea=2, Min=1375, Max=1424, Name="Snow Lurker", Quest="FrostQuest", QLevel=2, QCF=CFrame.new(5667.6582, 26.7997818, -6486.08984, -0.933587909, 0, -0.358349502, 0, 1, 0, 0.358349502, 0, -0.933587909), MonCF=CFrame.new(5407.07373046875, 69.19437408447266, -6880.88037109375) },
		{ Sea=2, Min=1425, Max=1449, Name="Sea Soldier", Quest="ForgottenQuest", QLevel=1, QCF=CFrame.new(-3054.44458, 235.544281, -10142.8193, 0.990270376, -0, -0.13915664, 0, 1, -0, 0.13915664, 0, 0.990270376), MonCF=CFrame.new(-3028.2236328125, 64.67451477050781, -9775.4267578125) },
		{ Sea=2, Min=1450, Max=999999, Name="Water Fighter", Quest="ForgottenQuest", QLevel=2, QCF=CFrame.new(-3054.44458, 235.544281, -10142.8193, 0.990270376, -0, -0.13915664, 0, 1, -0, 0.13915664, 0, 0.990270376), MonCF=CFrame.new(-3352.9013671875, 285.01556396484375, -10534.841796875) },
		{ Sea=3, Min=1500, Max=1524, Name="Pirate Millionaire", Quest="PiratePortQuest", QLevel=1, QCF=CFrame.new(-290.074677, 42.9034653, 5581.58984, 0.965929627, -0, -0.258804798, 0, 1, -0, 0.258804798, 0, 0.965929627), MonCF=CFrame.new(-245.9963836669922, 47.30615234375, 5584.1005859375) },
		{ Sea=3, Min=1525, Max=1574, Name="Pistol Billionaire", Quest="PiratePortQuest", QLevel=2, QCF=CFrame.new(-290.074677, 42.9034653, 5581.58984, 0.965929627, -0, -0.258804798, 0, 1, -0, 0.258804798, 0, 0.965929627), MonCF=CFrame.new(-187.3301544189453, 86.23987579345703, 6013.513671875) },
		{ Sea=3, Min=1575, Max=1599, Name="Dragon Crew Warrior", Quest="AmazonQuest", QLevel=1, QCF=CFrame.new(5832.83594, 51.6806107, -1101.51563, 0.898790359, -0, -0.438378751, 0, 1, -0, 0.438378751, 0, 0.898790359), MonCF=CFrame.new(6141.140625, 51.35136413574219, -1340.738525390625) },
		{ Sea=3, Min=1600, Max=1624, Name="Dragon Crew Archer", Quest="AmazonQuest", QLevel=2, QCF=CFrame.new(5833.1147460938, 51.60498046875, -1103.0693359375), MonCF=CFrame.new(6616.41748046875, 441.7670593261719, 446.0469970703125) },
		{ Sea=3, Min=1625, Max=1649, Name="Female Islander", Quest="AmazonQuest2", QLevel=1, QCF=CFrame.new(5446.8793945313, 601.62945556641, 749.45672607422), MonCF=CFrame.new(4685.25830078125, 735.8078002929688, 815.3425903320312) },
		{ Sea=3, Min=1650, Max=1699, Name="Giant Islander", Quest="AmazonQuest2", QLevel=2, QCF=CFrame.new(5446.8793945313, 601.62945556641, 749.45672607422), MonCF=CFrame.new(4729.09423828125, 590.436767578125, -36.97627639770508) },
		{ Sea=3, Min=1700, Max=1724, Name="Marine Commodore", Quest="MarineTreeIsland", QLevel=1, QCF=CFrame.new(2180.54126, 27.8156815, -6741.5498, -0.965929747, 0, 0.258804798, 0, 1, 0, -0.258804798, 0, -0.965929747), MonCF=CFrame.new(2286.0078125, 73.13391876220703, -7159.80908203125) },
		{ Sea=3, Min=1725, Max=1774, Name="Marine Rear Admiral", Quest="MarineTreeIsland", QLevel=2, QCF=CFrame.new(2179.98828125, 28.731239318848, -6740.0551757813), MonCF=CFrame.new(3656.773681640625, 160.52406311035156, -7001.5986328125) },
		{ Sea=3, Min=1775, Max=1799, Name="Fishman Raider", Quest="DeepForestIsland3", QLevel=1, QCF=CFrame.new(-10581.6563, 330.872955, -8761.18652, -0.882952213, 0, 0.469463557, 0, 1, 0, -0.469463557, 0, -0.882952213), MonCF=CFrame.new(-10407.5263671875, 331.76263427734375, -8368.5166015625) },
		{ Sea=3, Min=1800, Max=1824, Name="Fishman Captain", Quest="DeepForestIsland3", QLevel=2, QCF=CFrame.new(-10581.6563, 330.872955, -8761.18652, -0.882952213, 0, 0.469463557, 0, 1, 0, -0.469463557, 0, -0.882952213), MonCF=CFrame.new(-10994.701171875, 352.38140869140625, -9002.1103515625) },
		{ Sea=3, Min=1825, Max=1849, Name="Forest Pirate", Quest="DeepForestIsland", QLevel=1, QCF=CFrame.new(-13234.04, 331.488495, -7625.40137, 0.707134247, -0, -0.707079291, 0, 1, -0, 0.707079291, 0, 0.707134247), MonCF=CFrame.new(-13274.478515625, 332.3781433105469, -7769.58056640625) },
		{ Sea=3, Min=1850, Max=1899, Name="Mythological Pirate", Quest="DeepForestIsland", QLevel=2, QCF=CFrame.new(-13234.04, 331.488495, -7625.40137, 0.707134247, -0, -0.707079291, 0, 1, -0, 0.707079291, 0, 0.707134247), MonCF=CFrame.new(-13680.607421875, 501.08154296875, -6991.189453125) },
		{ Sea=3, Min=1900, Max=1924, Name="Jungle Pirate", Quest="DeepForestIsland2", QLevel=1, QCF=CFrame.new(-12680.3818, 389.971039, -9902.01953, -0.0871315002, 0, 0.996196866, 0, 1, 0, -0.996196866, 0, -0.0871315002), MonCF=CFrame.new(-12256.16015625, 331.73828125, -10485.8369140625) },
		{ Sea=3, Min=1925, Max=1974, Name="Musketeer Pirate", Quest="DeepForestIsland2", QLevel=2, QCF=CFrame.new(-12680.3818, 389.971039, -9902.01953, -0.0871315002, 0, 0.996196866, 0, 1, 0, -0.996196866, 0, -0.0871315002), MonCF=CFrame.new(-13457.904296875, 391.545654296875, -9859.177734375) },
		{ Sea=3, Min=1975, Max=1999, Name="Reborn Skeleton", Quest="HauntedQuest1", QLevel=1, QCF=CFrame.new(-9479.2168, 141.215088, 5566.09277, 0, 0, 1, 0, 1, -0, -1, 0, 0), MonCF=CFrame.new(-8763.7236328125, 165.72299194335938, 6159.86181640625) },
		{ Sea=3, Min=2000, Max=2024, Name="Living Zombie", Quest="HauntedQuest1", QLevel=2, QCF=CFrame.new(-9479.2168, 141.215088, 5566.09277, 0, 0, 1, 0, 1, -0, -1, 0, 0), MonCF=CFrame.new(-10144.1318359375, 138.62667846679688, 5838.0888671875) },
		{ Sea=3, Min=2025, Max=2049, Name="Demonic Soul", Quest="HauntedQuest2", QLevel=1, QCF=CFrame.new(-9516.99316, 172.017181, 6078.46533, 0, 0, -1, 0, 1, 0, 1, 0, 0), MonCF=CFrame.new(-9505.8720703125, 172.10482788085938, 6158.9931640625) },
		{ Sea=3, Min=2050, Max=2074, Name="Posessed Mummy", Quest="HauntedQuest2", QLevel=2, QCF=CFrame.new(-9516.99316, 172.017181, 6078.46533, 0, 0, -1, 0, 1, 0, 1, 0, 0), MonCF=CFrame.new(-9582.0224609375, 6.251527309417725, 6205.478515625) },
		{ Sea=3, Min=2075, Max=2099, Name="Peanut Scout", Quest="NutsIslandQuest", QLevel=1, QCF=CFrame.new(-2104.3908691406, 38.104167938232, -10194.21875, 0, 0, -1, 0, 1, 0, 1, 0, 0), MonCF=CFrame.new(-2143.241943359375, 47.72198486328125, -10029.9951171875) },
		{ Sea=3, Min=2100, Max=2124, Name="Peanut President", Quest="NutsIslandQuest", QLevel=2, QCF=CFrame.new(-2104.3908691406, 38.104167938232, -10194.21875, 0, 0, -1, 0, 1, 0, 1, 0, 0), MonCF=CFrame.new(-1859.35400390625, 38.10316848754883, -10422.4296875) },
		{ Sea=3, Min=2125, Max=2149, Name="Ice Cream Chef", Quest="IceCreamIslandQuest", QLevel=1, QCF=CFrame.new(-820.64825439453, 65.819526672363, -10965.795898438, 0, 0, -1, 0, 1, 0, 1, 0, 0), MonCF=CFrame.new(-872.24658203125, 65.81957244873047, -10919.95703125) },
		{ Sea=3, Min=2150, Max=2199, Name="Ice Cream Commander", Quest="IceCreamIslandQuest", QLevel=2, QCF=CFrame.new(-820.64825439453, 65.819526672363, -10965.795898438, 0, 0, -1, 0, 1, 0, 1, 0, 0), MonCF=CFrame.new(-558.06103515625, 112.04895782470703, -11290.7744140625) },
		{ Sea=3, Min=2200, Max=2224, Name="Cookie Crafter", Quest="CakeQuest1", QLevel=1, QCF=CFrame.new(-2021.32007, 37.7982254, -12028.7295, 0.957576931, -8.80302053e-08, 0.288177818, 6.9301187e-08, 1, 7.51931211e-08, -0.288177818, -5.2032135e-08, 0.957576931), MonCF=CFrame.new(-2374.13671875, 37.79826354980469, -12125.30859375) },
		{ Sea=3, Min=2225, Max=2249, Name="Cake Guard", Quest="CakeQuest1", QLevel=2, QCF=CFrame.new(-2021.32007, 37.7982254, -12028.7295, 0.957576931, -8.80302053e-08, 0.288177818, 6.9301187e-08, 1, 7.51931211e-08, -0.288177818, -5.2032135e-08, 0.957576931), MonCF=CFrame.new(-1598.3070068359375, 43.773197174072266, -12244.5810546875) },
		{ Sea=3, Min=2250, Max=2274, Name="Baking Staff", Quest="CakeQuest2", QLevel=1, QCF=CFrame.new(-1927.91602, 37.7981339, -12842.5391, -0.96804446, 4.22142143e-08, 0.250778586, 4.74911062e-08, 1, 1.49904711e-08, -0.250778586, 2.64211941e-08, -0.96804446), MonCF=CFrame.new(-1887.8099365234375, 77.6185073852539, -12998.3505859375) },
		{ Sea=3, Min=2275, Max=2299, Name="Head Baker", Quest="CakeQuest2", QLevel=2, QCF=CFrame.new(-1927.91602, 37.7981339, -12842.5391, -0.96804446, 4.22142143e-08, 0.250778586, 4.74911062e-08, 1, 1.49904711e-08, -0.250778586, 2.64211941e-08, -0.96804446), MonCF=CFrame.new(-2216.188232421875, 82.884521484375, -12869.2939453125) },
		{ Sea=3, Min=2300, Max=2324, Name="Cocoa Warrior", Quest="ChocQuest1", QLevel=1, QCF=CFrame.new(233.22836303710938, 29.876001358032227, -12201.2333984375), MonCF=CFrame.new(-21.55328369140625, 80.57499694824219, -12352.3876953125) },
		{ Sea=3, Min=2325, Max=2349, Name="Chocolate Bar Battler", Quest="ChocQuest1", QLevel=2, QCF=CFrame.new(233.22836303710938, 29.876001358032227, -12201.2333984375), MonCF=CFrame.new(582.590576171875, 77.18809509277344, -12463.162109375) },
		{ Sea=3, Min=2350, Max=2374, Name="Sweet Thief", Quest="ChocQuest2", QLevel=1, QCF=CFrame.new(150.5066375732422, 30.693693161010742, -12774.5029296875), MonCF=CFrame.new(165.1884765625, 76.05885314941406, -12600.8369140625) },
		{ Sea=3, Min=2375, Max=2399, Name="Candy Rebel", Quest="ChocQuest2", QLevel=2, QCF=CFrame.new(150.5066375732422, 30.693693161010742, -12774.5029296875), MonCF=CFrame.new(134.86563110351562, 77.2476806640625, -12876.5478515625) },
		{ Sea=3, Min=2400, Max=2424, Name="Candy Pirate", Quest="CandyQuest1", QLevel=1, QCF=CFrame.new(-1150.0400390625, 20.378934860229492, -14446.3349609375), MonCF=CFrame.new(-1310.5003662109375, 26.016523361206055, -14562.404296875) },
		{ Sea=3, Min=2425, Max=2449, Name="Snow Demon", Quest="CandyQuest1", QLevel=2, QCF=CFrame.new(-1150.0400390625, 20.378934860229492, -14446.3349609375), MonCF=CFrame.new(-880.2006225585938, 71.24776458740234, -14538.609375) },
		{ Sea=3, Min=2450, Max=2474, Name="Isle Outlaw", Quest="TikiQuest1", QLevel=1, QCF=CFrame.new(-16547.748046875, 61.13533401489258, -173.41360473632812), MonCF=CFrame.new(-16442.814453125, 116.13899993896484, -264.4637756347656) },
		{ Sea=3, Min=2475, Max=2499, Name="Island Boy", Quest="TikiQuest1", QLevel=2, QCF=CFrame.new(-16547.748046875, 61.13533401489258, -173.41360473632812), MonCF=CFrame.new(-16901.26171875, 84.06756591796875, -192.88906860351562) },
		{ Sea=3, Min=2500, Max=2524, Name="kissed", Quest="TikiQuest2", QLevel=1, QCF=CFrame.new(-16539.078125, 55.68632888793945, 1051.5738525390625), MonCF=CFrame.new(-16349.8779296875, 92.0808334350586, 1123.4169921875) },
		{ Sea=3, Min=2525, Max=2550, Name="Isle Champion", Quest="TikiQuest2", QLevel=2, QCF=CFrame.new(-16539.078125, 55.68632888793945, 1051.5738525390625), MonCF=CFrame.new(-16347.4150390625, 92.09503936767578, 1122.335205078125) },
    },
}

--=============================================================================
-- SERVICES
--=============================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local VirtualUser       = game:GetService("VirtualUser")
local HttpService       = game:GetService("HttpService")
local TeleportService   = game:GetService("TeleportService")
local Lighting          = game:GetService("Lighting")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- Declared here, filled in at the very bottom: the modules in between (Farming)
-- must be able to read StrawberryHub.FarmDriver, and a reference placed after
-- their definition would resolve as a global (so nil).
local StrawberryHub

--=============================================================================
-- STATE
--=============================================================================
local State = {
    flags = {},           -- flags[nom] = bool, pilote chaque boucle
    connections = {},
    guis = {},
    sea = Config.Places[game.PlaceId] or 1,
    selectedWeapon = nil,
    selectedIsland = nil,
    floorPart = nil,
    tween = nil,
    alive = true,         -- false apres Unload : arrete tout
    attackError = nil,    -- message si le moteur de combat est indisponible
    attackCount = 0,      -- nombre d'attaques effectivement envoyees
    antiDetectError = nil,-- message si le hook anti-detection a echoue
    tweenGoal = nil,      -- destination du tween en cours
    bringAnchor = nil,    -- point de vol fixe pendant le bring
    bringFilter = nil,    -- nom du mob a ramener (cible de quete en cours)
    bringDriver = nil,    -- pose par l'AutomationCore : remplace Move.bringMobs
    holdTarget = nil,     -- HumanoidRootPart de la cible a suivre
    holdOffset = nil,     -- decalage a maintenir par rapport a elle
    workingMethod = nil,  -- strategie d'attaque validee par les degats observes
    damageSeen = 0,       -- nombre de fois ou une cible a reellement perdu de la vie
    firedSinceRotate = false, -- notre strategie a-t-elle tire depuis le dernier changement
}

--=============================================================================
-- UTIL
--=============================================================================
local Util = {}

function Util.log(...)
    if Config.Debug then print("[StrawberryHub]", ...) end
end

function Util.try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and Config.Debug then warn("[StrawberryHub]", err) end
    return ok, err
end

function Util.dist(a, b)
    return (a - b).Magnitude
end

function Util.keys(tbl)
    local out = {}
    for k in pairs(tbl) do table.insert(out, k) end
    table.sort(out)
    return out
end

--=============================================================================
-- DIAGNOSTICS — measurable instrumentation, switchable, side-effect free
--=============================================================================
--  Purpose: turn the audit's CORROBORATED / LIKELY / UNKNOWN points into real
--  numbers, before anything is removed or optimised.
--
--  Constraints honoured:
--    * near-zero cost when disabled (one boolean test per probe);
--    * no print/log on hot paths — counters only;
--    * statistics computed on demand, never continuously;
--    * no change to behaviour, in either state;
--    * full cleanup through Unload().
--=============================================================================
local Diagnostics = {}

local enabled = false
local startedAt = os.clock()

local counters = {}       -- cle -> nombre d'appels
local timings = {}        -- cle -> { n, total, min, max, inspected, found }
local observations = {}   -- categorie -> { cle -> valeur }
local firstSeen = {}      -- cle -> horodatage du 1er appel
local lastSeen = {}       -- cle -> horodatage du dernier appel

function Diagnostics.isEnabled() return enabled end

function Diagnostics.setEnabled(value)
    value = value and true or false
    if value == enabled then return end
    enabled = value
    if value then
        startedAt = os.clock()
    end
end

function Diagnostics.reset()
    table.clear(counters)
    table.clear(timings)
    table.clear(observations)
    table.clear(firstSeen)
    table.clear(lastSeen)
    startedAt = os.clock()
end

function Diagnostics.cleanup()
    enabled = false
    Diagnostics.reset()
end

-- Simple counter. Hot path: one comparison plus one addition.
function Diagnostics.count(key, n)
    if not enabled then return end
    local now = os.clock()
    if not firstSeen[key] then firstSeen[key] = now end
    lastSeen[key] = now
    counters[key] = (counters[key] or 0) + (n or 1)
end

-- Start of a measurement. Returns nil when disabled: Diagnostics.stop then
-- becomes a plain nil test, so it is free.
function Diagnostics.start()
    if not enabled then return nil end
    return os.clock()
end

-- End of a measurement. `inspected` = items walked, `found` = results kept.
function Diagnostics.stop(key, t0, inspected, found)
    if not t0 then return end
    local dt = os.clock() - t0
    local t = timings[key]
    if not t then
        t = { n = 0, total = 0, min = math.huge, max = 0, inspected = 0, found = 0 }
        timings[key] = t
        firstSeen[key] = firstSeen[key] or t0
    end
    t.n = t.n + 1
    t.total = t.total + dt
    if dt < t.min then t.min = dt end
    if dt > t.max then t.max = dt end
    t.inspected = t.inspected + (inspected or 0)
    t.found = t.found + (found or 0)
    lastSeen[key] = os.clock()
end

-- Observed value (not cumulative): weapon -> delay, and so on.
function Diagnostics.observe(category, key, value)
    if not enabled then return end
    local c = observations[category]
    if not c then
        c = {}
        observations[category] = c
    end
    c[tostring(key)] = value
end

-- Keeps the largest value seen for a key (distances, peaks).
function Diagnostics.observeMax(category, key, value)
    if not enabled then return end
    local c = observations[category]
    if not c then
        c = {}
        observations[category] = c
    end
    local k = tostring(key)
    local prev = tonumber(c[k]) or 0
    if value > prev then c[k] = value end
end

-- True when the category has not yet been observed for this key: avoids
-- repeating an expensive probe (e.g. GetWeaponData) on every attack.
function Diagnostics.seen(category, key)
    local c = observations[category]
    return c ~= nil and c[tostring(key)] ~= nil
end

--------------------------------------------------------------------- report
local function fmtMs(seconds)
    return string.format("%.3f ms", seconds * 1000)
end

local function perMinute(n, elapsed)
    if elapsed <= 0 then return 0 end
    return n / (elapsed / 60)
end

local function line(out, text) out[#out + 1] = text end

local function section(out, title)
    line(out, "")
    line(out, "-- " .. title)
end

-- Readable report. Missing values are printed explicitly rather than omitted:
-- "0" is a measurement, not a gap.
function Diagnostics.Dump()
    local elapsed = os.clock() - startedAt
    local out = {}

    line(out, "========== STRAWBERRY DIAGNOSTICS ==========")
    line(out, ("Etat: %s   Duree de mesure: %.1f s")
        :format(enabled and "ACTIF" or "INACTIF", elapsed))

    ------------------------------------------------------------------ combat
    section(out, "COMBAT (compteurs d'appels)")
    local combatKeys = {
        "ModernCombatCalls", "LegacyCombatFallbackCalls",
        "SendHitsCalls", "CombatControllerCalls",
        "ControllerCalls", "RemoteCalls", "RemoteRawCalls",
        "ControllerResolveCalls", "ControllerResolveHits",
        "BladeTargetsCalls", "NextTokenCalls",
        "GlobalSendHits_Modern", "GlobalSendHits_Legacy",
    }
    for _, k in ipairs(combatKeys) do
        local n = counters[k] or 0
        local first = firstSeen[k]
        line(out, ("  %-26s %8d   %6.1f/min%s")
            :format(k, n, perMinute(n, elapsed),
                first and ("   1er@%.1fs  dernier@%.1fs")
                    :format(first - startedAt, (lastSeen[k] or first) - startedAt) or ""))
    end

    ------------------------------------------------------- CF availability
    section(out, "COMBAT REFERENCES (presence, not usage)")
    local d = State.diag or {}
    line(out, ("  Global.SendHitsToServer : %s"):format(tostring(d.sendHits)))
    line(out, ("  CombatController        : %s"):format(tostring(d.rigLib)))
    line(out, ("  RE/RegisterAttack       : %s"):format(tostring(d.registerAttack)))
    line(out, ("  activeController (getgc): %s"):format(tostring(d.controller)))
    line(out, ("  Remotes.Validator       : %s"):format(tostring(d.validator)))

    ------------------------------------------------------------- scans
    section(out, "ENEMY SCANS (real cost)")
    local scanKeys = {
        "Enemies.nearest", "TargetManager:FindTargets",
        "engage", "Move.bringMobs", "Enemies.nearestOfList",
    }
    local grandTotal, grandCalls = 0, 0
    for _, k in ipairs(scanKeys) do
        local t = timings[k]
        if t and t.n > 0 then
            grandTotal = grandTotal + t.total
            grandCalls = grandCalls + t.n
            line(out, ("  %-26s n=%-7d %6.1f/s")
                :format(k, t.n, elapsed > 0 and t.n / elapsed or 0))
            line(out, ("      moy %s | min %s | max %s | total %s")
                :format(fmtMs(t.total / t.n), fmtMs(t.min), fmtMs(t.max), fmtMs(t.total)))
            line(out, ("      objets parcourus %d (moy %.1f) | cibles retenues %d")
                :format(t.inspected, t.inspected / t.n, t.found))
        else
            line(out, ("  %-26s n=0"):format(k))
        end
    end
    line(out, "")
    line(out, ("  TOTAL SCAN COST: %s over %.1f s  =>  %.2f%% of the time")
        :format(fmtMs(grandTotal), elapsed,
            elapsed > 0 and (grandTotal / elapsed) * 100 or 0))
    line(out, ("  (%d appels cumules, %.1f/s)")
        :format(grandCalls, elapsed > 0 and grandCalls / elapsed or 0))

    ------------------------------------------------------------- movement
    section(out, "DEPLACEMENT")
    for _, k in ipairs({ "Move.tweenTo", "Move.snap", "Move.hold", "Move.tweenSpeed" }) do
        line(out, ("  %-26s %8d"):format(k, counters[k] or 0))
    end
    local mv = observations.movement
    if mv then
        for k, v in pairs(mv) do
            line(out, ("    %s = %s"):format(k, tostring(v)))
        end
    end

    ------------------------------------------------------------- weapons
    section(out, "ARMES (source de verite du delai)")
    local w = observations.weapon
    if w and next(w) then
        for name, info in pairs(w) do
            line(out, ("  %s"):format(name))
            line(out, ("    %s"):format(tostring(info)))
        end
    else
        line(out, "  no observation (attack at least once, with the module active)")
    end

    ------------------------------------------------------------- errors
    section(out, "ERREURS")
    local errs = observations.error
    if errs and next(errs) then
        for k, v in pairs(errs) do
            line(out, ("  %s : %s"):format(k, tostring(v)))
        end
    else
        line(out, "  no errors recorded")
    end

    ------------------------------------------------------------- transitions
    section(out, "TRANSITIONS D'ETAT")
    for k, n in pairs(counters) do
        if string.sub(k, 1, 6) == "state." then
            line(out, ("  %-26s %8d"):format(string.sub(k, 7), n))
        end
    end

    line(out, "")
    line(out, "============================================")
    return table.concat(out, "\n")
end

-- Writes the report where the user can retrieve it, without ever polluting a
-- hot path (manual call only).
function Diagnostics.Export()
    local report = Diagnostics.Dump()
    warn(report)
    pcall(function()
        if setclipboard then setclipboard(report) end
    end)
    pcall(function()
        if writefile then
            if makefolder and isfolder and not isfolder(Config.Persist.Folder) then
                makefolder(Config.Persist.Folder)
            end
            writefile(Config.Persist.Folder .. "/diagnostics.txt", report)
        end
    end)
    return report
end

--=============================================================================
-- PERSIST — settings storage (JSON idea taken from "if getgenv")
--=============================================================================
local Persist = {}

local function canWriteFiles()
    return type(writefile) == "function" and type(readfile) == "function"
        and type(isfile) == "function"
end

function Persist.save()
    if not canWriteFiles() then return end
    Util.try(function()
        if type(makefolder) == "function" and type(isfolder) == "function"
            and not isfolder(Config.Persist.Folder) then
            makefolder(Config.Persist.Folder)
        end
        local data = {
            Farming = Config.Farming,
            FastAttack = Config.FastAttack,
            Diagnostics = { Enabled = Config.Diagnostics.Enabled },
            Combat  = { AuraRange = Config.Combat.AuraRange,
                        HitboxRange = Config.Combat.HitboxRange,
                        AttackDelay = Config.Combat.AttackDelay,
                        Method = Config.Combat.Method,
                        CalibrateSeconds = Config.Combat.CalibrateSeconds },
            Player  = Config.Player,
            AntiDetection = { Enabled = Config.AntiDetection.Enabled,
                              DisableAbuseScreenshots = Config.AntiDetection.DisableAbuseScreenshots },
            Debug   = Config.Debug,
        }
        writefile(Config.Persist.Folder .. "/" .. Config.Persist.File,
            HttpService:JSONEncode(data))
    end)
end

function Persist.load()
-- Measurement follows the saved setting: off by default.
Diagnostics.setEnabled(Config.Diagnostics.Enabled)
    if not canWriteFiles() then return end
    Util.try(function()
        local path = Config.Persist.Folder .. "/" .. Config.Persist.File
        if not isfile(path) then return end
        local data = HttpService:JSONDecode(readfile(path))
        -- Careful merge: only known keys are overwritten.
        for section, values in pairs(data) do
            if type(values) == "table" and type(Config[section]) == "table" then
                for k, v in pairs(values) do
                    if Config[section][k] ~= nil then Config[section][k] = v end
                end
            elseif Config[section] ~= nil and type(values) ~= "table" then
                Config[section] = values
            end
        end

        -- Settings saved before the nerf may hold a speed above the cap: they
        -- are brought back within limits, and the cap itself is never restored
        -- from the file.
        Config.Farming.MaxTweenSpeed = 200
        if type(Config.Farming.TweenSpeed) ~= "number"
            or Config.Farming.TweenSpeed > Config.Farming.MaxTweenSpeed then
            Config.Farming.TweenSpeed = Config.Farming.MaxTweenSpeed
        end
    end)
end

--=============================================================================
-- CORE — character refs, stoppable loops, connections
--=============================================================================
local Core = {}

function Core.character() return LocalPlayer.Character end

function Core.hrp()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

function Core.humanoid()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

function Core.alive()
    local h = Core.humanoid()
    return h ~= nil and h.Health > 0 and Core.hrp() ~= nil
end

function Core.level()
    local data = LocalPlayer:FindFirstChild("Data")
    local lvl = data and data:FindFirstChild("Level")
    return lvl and lvl.Value or 1
end

function Core.bind(connection)
    table.insert(State.connections, connection)
    return connection
end

-- Stoppable loop: runs while the flag is true AND the hub is loaded.
function Core.loop(flag, interval, body)
    task.spawn(function()
        while State.alive and State.flags[flag] do
            Util.try(body)
            task.wait(interval)
        end
    end)
end

function Core.setFlag(flag, value, interval, body)
    State.flags[flag] = value and true or false
    if value and interval and body then Core.loop(flag, interval, body) end
end

-- Cuts every loop at once.
function Core.stopAll()
    for flag in pairs(State.flags) do State.flags[flag] = false end
end

--=============================================================================
-- REMOTE
--=============================================================================
local Remote = {}
local commFCache

function Remote.commF()
    if commFCache and commFCache.Parent then return commFCache end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    commFCache = remotes and remotes:FindFirstChild("CommF_")
    return commFCache
end

function Remote.invoke(...)
    local commF = Remote.commF()
    if not commF then return false end
    local args = table.pack(...)
    return pcall(function()
        return commF:InvokeServer(table.unpack(args, 1, args.n))
    end)
end

function Remote.redeem(code)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local redeem = remotes and remotes:FindFirstChild("Redeem")
    if redeem then pcall(function() redeem:InvokeServer(code) end) end
end

--=============================================================================
-- MOVE — tween movement plus an anti-drowning floor
--=============================================================================
local Move = {}

-- True when a movement feature is active (drives the floor).
-- The floor is only useful WHILE moving (not sinking / not falling).
-- Once glued to a target, Move.hold writes the position every frame:
-- the floor becomes useless, and worse HARMFUL (a solid 40x40 platform under
-- the player catapulted the mobs just below it -> enemies thrown, desynced,
-- unreachable).
function Move.wantFloor()
    -- In safe mode no solid object is created: the invisible platform used to
    -- hit mobs and send them flying.
    if Config.Farming.SafeMode then return false end
    if State.holdTarget then return false end
    if Config.Farming.BringMob then return false end
    for flag, on in pairs(State.flags) do
        if on and (flag == "AutoFarm" or flag == "FarmTarget" or flag == "SeaBeast"
            or string.sub(flag, 1, 4) == "Mat_") then
            return true
        end
    end
    return false
end

function Move.updateFloor(active)
    if active then
        local hrp = Core.hrp()
        if not hrp then return end
        if not State.floorPart or not State.floorPart.Parent then
            local part = Instance.new("Part")
            part.Name = "StrawberryFloor"
            part.Anchored = true
            part.CanCollide = true
            part.Transparency = 1
            part.Size = Vector3.new(16, 1, 16)
            part.Parent = workspace
            State.floorPart = part
        end
        State.floorPart.CFrame = hrp.CFrame * CFrame.new(0, -3.6, 0)
    elseif State.floorPart then
        State.floorPart:Destroy()
        State.floorPart = nil
    end
end

-- Keeps the player glued to the target at 60 Hz, cancelling velocity.
-- Without cancelling velocity the character drifts and is then snapped back
-- into place: that is exactly the observed jitter.
-- Pulls every living enemy within the configured radius to the player. This is
-- the real "bring mob": the MOBS move, not the player.
-- It must be replayed every frame, since the server repositions the enemies.
-- Safe mode forbids DEFORMING mobs (size, speed), not moving them: bring is a
-- positioning feature, enabled explicitly.
-- The old SafeMode guard made this function return doing nothing, which froze
-- the farm (the player did not move either in bring mode).
-- Name of the mob to bring, derived from the active mode. Deriving the filter
-- from current state (rather than a variable set/cleared per target) avoids the
-- gap between two enemies, during which EVERYTHING was vacuumed up, bosses
-- included. Returns (mobName, allowedToBring).
-- The filter is fed continuously by the farming loop (State.bringFilter), never
-- derived here: the Quests module is declared further down the file and would
-- not be visible from this scope.
function Move.bringFilterName()
    if not Config.Farming.BringQuestOnly then return nil, true end
    if State.bringFilter then return State.bringFilter, true end
    -- Unknown filter: bring NOTHING rather than vacuum the whole zone
    -- (bosses included, which desynced them).
    return nil, false
end

local lastBring = 0

function Move.bringMobs()
    -- The AutomationCore, when attached, places the mobs itself: on distinct
    -- slots around the anchor, from an already-validated list. The version
    -- below stacks every mob on a single CFrame and trusts State.bringFilter;
    -- it stays as a fallback.
    local driver = State.bringDriver
    if driver then return driver() end

    -- Bring fights the server: at 60 Hz the mobs bounce and end up desynced.
    -- Ten repositionings per second is plenty.
    --
    local now = os.clock()
    if now - lastBring < Config.Farming.BringInterval then return end
    lastBring = now

    local t0 = Diagnostics.start()
    local filter, allowed = Move.bringFilterName()
    if not allowed then
        Diagnostics.stop("Move.bringMobs", t0, 0, 0)
        return
    end

    local hrp = Core.hrp()
    local folder = workspace:FindFirstChild("Enemies")
    if not hrp or not folder then
        Diagnostics.stop("Move.bringMobs", t0, 0, 0)
        return
    end

    local origin = hrp.Position
    local radius = Config.Farming.BringDistance
    local height = Config.Farming.BringHeight

    local children = folder:GetChildren()
    local moved = 0
    for _, enemy in ipairs(children) do
        local ehrp = enemy:FindFirstChild("HumanoidRootPart")
        local ehum = enemy:FindFirstChildOfClass("Humanoid")
        if ehrp and ehum and ehum.Health > 0
            and (not filter or enemy.Name == filter) then
            local d = (ehrp.Position - origin).Magnitude
            -- Only mobs still far away are repositioned. Rewriting the position
            -- of a mob already in place at 60 Hz meant fighting the server
            -- continuously: permanent bouncing and unreachable enemies.
            if d <= radius and d > 6 then
                ehrp.CanCollide = false
                ehrp.CFrame = hrp.CFrame * CFrame.new(0, -height, 0)
                ehrp.AssemblyLinearVelocity = Vector3.zero
                moved = moved + 1
            end
        end
    end
    Diagnostics.stop("Move.bringMobs", t0, #children, moved)
end

-- Places the player at the wanted offset AND faces the target. Melee M1 is
-- directional server-side: without the facing, the blow does not land.
-- Used by Move.hold (60 Hz) AND by Attack.strike (immediate placement), so the
-- first strike already goes the right way.
function Move.faceTarget(targetPart, offset)
    local hrp = Core.hrp()
    if not hrp or not targetPart or not targetPart.Parent then return end

    local pos
    if Config.Farming.SafeMode then
        -- Stand back AND above, facing the mob. Since hits are sent directly by
        -- FastAttack (RegisterHit), height no longer blocks damage: it only
        -- puts us out of reach of the enemy's melee.
        --
        local tp = targetPart.Position
        local from = hrp.Position
        local dir = Vector3.new(from.X - tp.X, 0, from.Z - tp.Z)
        if dir.Magnitude < 0.1 then dir = Vector3.new(0, 0, 1) end
        pos = tp
            + dir.Unit * Config.Farming.SafeDistance
            + Vector3.new(0, Config.Farming.AttackHeight, 0)
    else
        pos = (targetPart.CFrame * offset).Position
    end
    -- Guard: two identical points give a NaN CFrame.lookAt, which throws the
    -- character off the map.
    if (pos - targetPart.Position).Magnitude < 0.5 then
        pos = targetPart.Position + Vector3.new(0, 3, 3)
    end
    hrp.CFrame = CFrame.lookAt(pos, targetPart.Position)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

function Move.hold()
    Diagnostics.count("Move.hold")
    local hrp = Core.hrp()
    if not hrp then return end

    -- Bring mode: the player is held flying at a fixed point and the mobs are
    -- brought just below. Without that hold the player stayed on the ground and
    -- the enemies were therefore brought UNDER the scenery.
    if Config.Farming.BringMob then
        if State.bringAnchor then
            hrp.CFrame = State.bringAnchor
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        Move.bringMobs()
        return
    end

    local target, offset = State.holdTarget, State.holdOffset
    if not target or not target.Parent or not offset then return end
    -- Stand NEAR the target and LOOK at it: melee M1 is directional, you have
    -- to face the mob for the blow to land server-side.
    Move.faceTarget(target, offset)
end

-- Effective movement speed, ALWAYS bounded. A game update tightened speed
-- detection: past MaxTweenSpeed studs/s the movement is flagged. The cap is
-- applied here, at the single place speed is consumed, so no path (UI, saved
-- config, manual edit) can get around it.
--
function Move.tweenSpeed()
    Diagnostics.count("Move.tweenSpeed")
    local wanted = tonumber(Config.Farming.TweenSpeed) or Config.Farming.MaxTweenSpeed
    return math.clamp(wanted, 20, Config.Farming.MaxTweenSpeed)
end

function Move.stopTween()
    if State.tween then
        Util.try(function() State.tween:Cancel() end)
        State.tween = nil
    end
    State.tweenGoal = nil
end

function Move.snapTo(cframe)
    local hrp = Core.hrp()
    if hrp then hrp.CFrame = cframe end
end

function Move.tweenTo(targetCFrame)
    local hrp = Core.hrp()
    if not hrp then return end
    local hum = Core.humanoid()
    if hum and hum.Sit then hum.Sit = false end

    local distance = Util.dist(targetCFrame.Position, hrp.Position)
    if distance <= Config.Farming.SnapDistance then
        -- Instant teleport: a movement mode distinct from the tween, measured
        -- separately (no speed is applied to it).
        Diagnostics.count("Move.snap")
        Diagnostics.observeMax("movement", "snap_max_distance", math.floor(distance))
        Move.stopTween()
        hrp.CFrame = targetCFrame
        return
    end

    -- A tween already running to the same destination must NOT be recreated:
    -- called from a 20 Hz loop it restarted from scratch on every tick and the
    -- character never got anywhere.
    if State.tween and State.tweenGoal
        and Util.dist(State.tweenGoal.Position, targetCFrame.Position)
            < Config.Farming.RetweenThreshold
        and State.tween.PlaybackState == Enum.PlaybackState.Playing then
        return
    end

    Move.stopTween()
    Util.try(function()
        State.tweenGoal = targetCFrame
        local speed = Move.tweenSpeed()
        local duration = distance / speed
        Diagnostics.count("Move.tweenTo")
        if Diagnostics.isEnabled() then
            Diagnostics.observe("movement", "last_tween_distance", math.floor(distance))
            Diagnostics.observe("movement", "last_tween_speed", speed)
            Diagnostics.observe("movement", "last_tween_duration_s",
                math.floor(duration * 100) / 100)
        end
        State.tween = TweenService:Create(hrp,
            TweenInfo.new(duration, Enum.EasingStyle.Linear),
            { CFrame = targetCFrame })
        State.tween:Play()
    end)
end

--=============================================================================
-- ATTACK — the real combat engine (CombatFramework)
--=============================================================================
--  A VirtualUser click deals NO damage in Blox Fruits: the server only accepts
--  the RigControllerEvent + Validator token sequence. That sequence is what is
--  reproduced here (merged from repeat.lua, the only source that carried a
--  local implementation of it).
--
--  Fragile by nature: the upvalue indices of `attack` change with every major
--  game update. Everything is therefore guarded, and failure is reported once
--  through State.attackError rather than in a loop.
--=============================================================================
local Attack = {}

local CF = {
    ready = false,
    controller = nil,
    rigLib = nil,
    rigEvent = nil,
    validator = nil,
    registerAttack = nil,  -- RE/RegisterAttack : consequence interne, pas le point d'entree
    combatController = nil, -- Controllers.CombatController : LE vrai point d'entree M1
    combatUtil = nil,      -- Modules.CombatUtil : donnees d'arme / CanAttack
    globalMod = nil,       -- Modules.Global : SendHitsToServer (jeton de session)
    hooked = false,
}

-- Resolves the CombatFramework references. Replayable after a respawn.
function Attack.init()
    local ok = pcall(function()
        local scripts = LocalPlayer:WaitForChild("PlayerScripts", 10)
        local cfModule = scripts and scripts:FindFirstChild("CombatFramework")
        if not cfModule then error("CombatFramework introuvable") end

        local ups = debug.getupvalues(require(cfModule))
        -- Upvalue 2 historically holds the activeController container, but we
        -- look it up by shape to survive an index shift.
        for _, up in pairs(ups) do
            if type(up) == "table" and up.activeController ~= nil then
                CF.controller = up
                break
            end
        end
        if not CF.controller then CF.controller = ups[2] end
        if type(CF.controller) ~= "table" then error("activeController introuvable") end

    end)

    -- INDEPENDENT resolution of each piece: one missing piece must not stop
    -- the other strategies from working.
    pcall(function() CF.rigLib = require(ReplicatedStorage.CombatFramework.RigLib) end)
    pcall(function() CF.rigEvent = ReplicatedStorage:FindFirstChild("RigControllerEvent") end)
    pcall(function()
        local r = ReplicatedStorage:FindFirstChild("Remotes")
        CF.validator = r and r:FindFirstChild("Validator")
    end)
    pcall(function()
        local mods = ReplicatedStorage:FindFirstChild("Modules")
        local net = mods and mods:FindFirstChild("Net")
        -- The name contains a slash: FindFirstChild handles that fine.
        CF.registerAttack = net and net:FindFirstChild("RE/RegisterAttack")
    end)
    -- The official M1 entry point, as called by ClientComponents.
    -- WeaponToolClient: `CombatController:Attack(tool)`.
    pcall(function()
        local ctrl = ReplicatedStorage:FindFirstChild("Controllers")
        local mod = ctrl and ctrl:FindFirstChild("CombatController")
        if mod then CF.combatController = require(mod) end
    end)
    pcall(function()
        local mods = ReplicatedStorage:FindFirstChild("Modules")
        local mod = mods and mods:FindFirstChild("CombatUtil")
        if mod then CF.combatUtil = require(mod) end
    end)
    -- Global exposes SendHitsToServer, the only way to register a hit: it
    -- restarts the internal coroutine that adds the session token the server
    -- expects (4th argument of RE/RegisterHit).
    pcall(function()
        local mod = ReplicatedStorage:FindFirstChild("Global")
        if mod then CF.globalMod = require(mod) end
    end)

    -- If the requires failed (paths changed by an update), getBladeHits is
    -- recovered by scanning memory.
    Attack.resolveRig()

    CF.ready = ok
    -- The "Controller" fast attack depends ONLY on the controller: we consider
    -- it ready as soon as that is resolved, even without the remotes.
    State.diag = {
        controller = (Attack.controller() ~= nil),
        rigLib = (CF.combatController ~= nil),
        sendHits = (CF.globalMod ~= nil
            and type(CF.globalMod.SendHitsToServer) == "function"),
        registerAttack = (CF.registerAttack ~= nil),
        validator = (CF.validator ~= nil),
    }
    if not State.diag.controller then
        State.attackError = "controleur de combat introuvable"
    end
    return ok
end

-- Removes attack animation delays (rate gain).
function Attack.hookAnimations()
    if CF.hooked then return end
    CF.hooked = true
    Util.try(function()
        local particle = require(LocalPlayer.PlayerScripts.CombatFramework.Particle)
        local rigLib = require(ReplicatedStorage.CombatFramework.RigLib)
        local originalPlay = particle.play

        rigLib.wrapAttackAnimationAsync = function(animation, char, weapon, range, callback)
            local hits = rigLib.getBladeHits(char, weapon, range)
            if not hits then return end
            particle.play = function() end
            animation:Play(0.1, 0.1, 0.1)
            callback(hits)
            particle.play = originalPlay
            task.wait(0.1)
            animation:Stop()
        end
    end)
    Util.try(function() require(ReplicatedStorage.Util.CameraShaker):Stop() end)
end

-- Three attack strategies coexist, plus an "Auto" mode that works out which
-- one actually functions by OBSERVING the damage dealt. That is the only
-- reliable way: depending on the game version and the executor, the strategy
-- that gets through differs, and none of them reports its own failure.
--
--   Controller — resets activeController then calls :attack().
--                Depends on no upvalue index.
--   Remote     — the full network sequence: weaponChange + Validator token
--                + hit. Depends on upvalues 4/5/6/7 of `attack`.
--   RemoteRaw  — weaponChange + hit, without the token (older versions).
Attack.METHODS = { "Auto", "SendHits", "CombatController", "RegisterAttack", "Controller", "Remote", "RemoteRaw" }

-- Combat controller resolution.
-- PRIMARY method: a getgc scan, which identifies the controller table by its
-- SHAPE (hitboxMagnitude + attack + blades fields) rather than by a fragile
-- upvalue index. That is what survives game updates (v31.4 broke the old
-- method: Ctrl:NO in the diagnostics).
local controllerCache

local function looksLikeController(o)
    return type(o) == "table"
        and rawget(o, "hitboxMagnitude") ~= nil
        and type(rawget(o, "attack")) == "function"
        and rawget(o, "blades") ~= nil
end

local lastScan = 0
function Attack.controller()
    if looksLikeController(controllerCache) then return controllerCache end
    Diagnostics.count("ControllerResolveCalls")
    controllerCache = nil

    -- Throttle: the getgc scan is expensive; called from Stepped (60 Hz) it
    -- would freeze the game while nothing is found. One attempt per second max.
    if os.clock() - lastScan < 1 then return nil end
    lastScan = os.clock()

    -- 1) getgc: the most reliable on modern executors (Delta included).
    if type(getgc) == "function" then
        local ok, res = pcall(function()
            for _, o in pairs(getgc(true)) do
                if looksLikeController(o) then return o end
            end
        end)
        if ok and res then
            Diagnostics.count("ControllerResolveHits")
            controllerCache = res
            return res
        end
    end

    -- 2) Fallback: CombatFramework module upvalues (the old method).
    pcall(function()
        local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
        local cfModule = scripts and scripts:FindFirstChild("CombatFramework")
        if not cfModule then return end
        local mod = require(cfModule)
        local function scan(fn)
            for i = 1, 20 do
                local okc, _, val = pcall(debug.getupvalue, fn, i)
                if not okc then break end
                if looksLikeController(val) then return val end
                if type(val) == "table" and looksLikeController(rawget(val, "activeController")) then
                    return val.activeController
                end
            end
        end
        if type(mod) == "function" then
            controllerCache = scan(mod)
        elseif type(mod) == "table" then
            for _, v in pairs(mod) do
                if type(v) == "function" then
                    controllerCache = scan(v)
                    if controllerCache then break end
                end
            end
        end
    end)
    return controllerCache
end

-- Finds the getBladeHits function (RigLib module) via getgc if the require fails.
function Attack.resolveRig()
    if CF.rigLib then return end
    if type(getgc) ~= "function" then return end
    pcall(function()
        for _, o in pairs(getgc(true)) do
            if type(o) == "table" and type(rawget(o, "getBladeHits")) == "function" then
                CF.rigLib = o
                return
            end
        end
    end)
end

function Attack.bladeName()
    local ok, name = pcall(function()
        local ctrl = Attack.controller()
        local blade = ctrl and ctrl.blades and ctrl.blades[1]
        if not blade then return nil end
        local char = Core.character()
        while blade and blade.Parent and blade.Parent ~= char do
            blade = blade.Parent
        end
        return blade and tostring(blade) or nil
    end)
    return ok and name or nil
end

local function currentBlade()
    local ctrl = Attack.controller()
    local blade = ctrl and ctrl.blades and ctrl.blades[1]
    if not blade then return nil end
    local char = Core.character()
    while blade and blade.Parent and blade.Parent ~= char do
        blade = blade.Parent
    end
    return blade
end

-- A fresh controller state: without this the game imposes its own delays.
local function primeController(ctrl)
    ctrl.hitboxMagnitude = Config.Combat.HitboxRange
    ctrl.active = false
    ctrl.blocking = false
    ctrl.focusStart = 0
    ctrl.increment = 0
    ctrl.timeToNextAttack = 0
    ctrl.timeToNextBlock = 0
    ctrl.attacking = false
end

-- Hittable targets around the player, deduplicated by model.
local function bladeTargets()
    Diagnostics.count("BladeTargetsCalls")
    local char, hrp = Core.character(), Core.hrp()
    if not char or not hrp or not CF.rigLib then return {} end
    local ok, raw = pcall(function()
        return CF.rigLib.getBladeHits(char, { hrp }, Config.Combat.HitboxRange)
    end)
    if not ok or not raw then return {} end

    local targets, seen = {}, {}
    for _, part in pairs(raw) do
        local model = part.Parent
        local mhrp = model and model:FindFirstChild("HumanoidRootPart")
        if mhrp and not seen[model] then
            seen[model] = true
            table.insert(targets, mhrp)
        end
    end
    return targets
end

------------------------------------------------------------------ strategies
local Strategy = {}

-- Part names the game accepts (CombatUtil's v_u_36 table). A hit sent on a
-- part outside this list is ignored server-side.
local VALID_HIT_PARTS = {
    "UpperTorso", "LowerTorso", "Head", "ModelHitbox", "Torso",
    "RightUpperArm", "RightLowerArm", "RightHand",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
    "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
}

-- Returns a hittable part of an enemy.
local function hitPartOf(enemy)
    for _, name in ipairs(VALID_HIT_PARTS) do
        local part = enemy:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part end
    end
    return nil
end

-- MASTER STRATEGY — the one that actually registers damage.
--
-- Source: ReplicatedStorage.Modules.CombatUtil (decompiled). Hits are sent
-- through RE/RegisterHit with FOUR arguments:
--     FireServer(hitPart, otherHits, nil, sessionToken)
--
-- The token is `tostring(UserId):sub(2,4) .. tostring(coroutine.running()):sub(11,15)`
-- and is generated inside an internal coroutine: impossible to rebuild from
-- outside. But the game exposes `Global.SendHitsToServer(part, extras)`, which
-- restarts that coroutine and adds the token for us.
--
-- THIS is the piece that was missing: RegisterAttack announces the blow,
-- RegisterHit applies the damage. Only the first was being sent.
function Strategy.SendHits()
    Diagnostics.count("SendHitsCalls")
    local G = CF.globalMod
    if not G or type(G.SendHitsToServer) ~= "function" then return false end

    local hrp = Core.hrp()
    local folder = workspace:FindFirstChild("Enemies")
    if not hrp or not folder then return false end

    local range = Config.Combat.HitboxRange
    local first, extras = nil, {}
    for _, enemy in ipairs(folder:GetChildren()) do
        local ehum = enemy:FindFirstChildOfClass("Humanoid")
        local ehrp = enemy:FindFirstChild("HumanoidRootPart")
        if ehum and ehrp and ehum.Health > 0
            and (ehrp.Position - hrp.Position).Magnitude <= range then
            local part = hitPartOf(enemy)
            if part then
                if not first then
                    first = part
                else
                    -- Expected format: { rig, hitPart }
                    table.insert(extras, { enemy, part })
                end
            end
        end
    end
    if not first then return false end

    -- The swing (animation + RE/RegisterAttack) is still useful: the server
    -- expects to see an attack before the hits.
    Strategy.CombatController()

    Diagnostics.count("GlobalSendHits_Legacy")
    return pcall(function()
        G.SendHitsToServer(first, extras)
    end)
end

-- PRIMARY STRATEGY — reproduces exactly what the game does on a click.
--
-- Source: ReplicatedStorage.ClientComponents.WeaponToolClient (decompiled):
--     if weaponData.WeaponType == "Melee" then
--         CombatController:Attack(tool)
--     else
--         CombatController:Attack(tool, inputObject)
--     end
--
-- Going through this entry point runs the whole official chain (GetWeaponData,
-- CanAttack, attackMelee, RunHitDetection), which itself ends at
-- RE/RegisterAttack. Firing the remote alone skipped that chain: the server
-- then had no hit data -> no damage.
function Strategy.CombatController()
    Diagnostics.count("CombatControllerCalls")
    local cc = CF.combatController
    if not cc or type(cc.Attack) ~= "function" then return false end

    local char = Core.character()
    if not char then return false end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return false end

    return pcall(function()
        -- The cooldown lives on the tool: reset it to chain blows (that is
        -- what makes the "fast" in fast attack).
        pcall(function() tool:SetAttribute("Cooldown", 0) end)
        -- :Attack can yield (animations): never from Stepped.
        task.spawn(function()
            pcall(function() cc:Attack(tool) end)
        end)
    end)
end

-- Signature observed with a remote spy (v31.4): RE/RegisterAttack(delay, combo).
-- Kept as a fallback: it does not trigger the hit-detection chain, so it is
-- rarely enough on its own.
local combo = 0
function Strategy.RegisterAttack()
    if not CF.registerAttack then return false end
    combo = combo % 4 + 1
    return pcall(function()
        CF.registerAttack:FireServer(0.4, combo)
    end)
end

function Strategy.Controller()
    Diagnostics.count("ControllerCalls")
    local ctrl = Attack.controller()
    if not ctrl or not ctrl.attack then return false end
    return pcall(function()
        primeController(ctrl)
        ctrl:attack()
    end)
end

-- Builds the anti-cheat token from the upvalues of `attack`.
-- Returns (seed, counter), or nil if the expected shape has changed.
local function nextToken(ctrl)
    Diagnostics.count("NextTokenCalls")
    local a = debug.getupvalue(ctrl.attack, 5)
    local m = debug.getupvalue(ctrl.attack, 6)
    local c = debug.getupvalue(ctrl.attack, 4)
    local counter = debug.getupvalue(ctrl.attack, 7)
    if type(a) ~= "number" or type(m) ~= "number"
        or type(c) ~= "number" or type(counter) ~= "number" then
        return nil
    end
    local seed = (a * 798405 + c * 727595) % m
    seed = (seed * m + c * 798405) % 1099511627776
    a = math.floor(seed / m)
    c = seed - a * m
    counter = counter + 1
    debug.setupvalue(ctrl.attack, 5, a)
    debug.setupvalue(ctrl.attack, 6, m)
    debug.setupvalue(ctrl.attack, 4, c)
    debug.setupvalue(ctrl.attack, 7, counter)
    return seed, counter
end

local function playSwing(ctrl)
    if ctrl.animator and ctrl.animator.anims and ctrl.animator.anims.basic then
        pcall(function() ctrl.animator.anims.basic[1]:Play(0.01, 0.01, 0.01) end)
    end
end

function Strategy.Remote()
    Diagnostics.count("RemoteCalls")
    if not CF.rigEvent or not CF.validator then return false end
    local ctrl = Attack.controller()
    if not ctrl or not ctrl.attack then return false end
    local targets = bladeTargets()
    if #targets == 0 then return false end
    local blade = currentBlade()
    if not blade then return false end

    return pcall(function()
        local seed, counter = nextToken(ctrl)
        if not seed then
            State.attackError = "upvalues changed by a game update"
            error("token")
        end
        playSwing(ctrl)
        CF.rigEvent:FireServer("weaponChange", tostring(blade))
        CF.validator:FireServer(math.floor(seed / 1099511627776 * 16777215), counter)
        CF.rigEvent:FireServer("hit", targets, 1, "")
        primeController(ctrl)
    end)
end

function Strategy.RemoteRaw()
    Diagnostics.count("RemoteRawCalls")
    if not CF.rigEvent then return false end
    local ctrl = Attack.controller()
    if not ctrl then return false end
    local targets = bladeTargets()
    if #targets == 0 then return false end
    local blade = currentBlade()
    if not blade then return false end

    return pcall(function()
        playSwing(ctrl)
        CF.rigEvent:FireServer("weaponChange", tostring(blade))
        CF.rigEvent:FireServer("hit", targets, 1, "")
        primeController(ctrl)
    end)
end

------------------------------------------------------------------ calibration
-- In Auto mode we try one strategy; if no damage is observed for
-- CalibrateSeconds, we move to the next. As soon as a strategy deals damage we
-- lock onto it (State.workingMethod).
local rotation = { "SendHits", "CombatController", "RegisterAttack", "Controller", "Remote", "RemoteRaw" }
local rotationIndex = 1
local lastRotate = os.clock()

function Attack.currentStrategy()
    if Config.Combat.Method ~= "Auto" then return Config.Combat.Method end
    if State.workingMethod then return State.workingMethod end
    return rotation[rotationIndex]
end

-- Called when damage is observed: freezes the winning strategy.
function Attack.confirmWorking()
    -- Observed damage only counts if OUR strategy has fired since the last
    -- rotation: otherwise we wrongly locked onto damage coming from the
    -- player's manual clicks (diagnostic: Controller* with Hits:0).
    if not State.firedSinceRotate then return end
    lastRotate = os.clock()
    if State.workingMethod then return end
    State.workingMethod = Attack.currentStrategy()
    Util.log("Strategie retenue :", State.workingMethod)
end

function Attack.noteDamage()
    lastRotate = os.clock()   -- une strategie qui touche ne doit pas etre abandonnee
end

-- PURELY time-based rotation: every CalibrateSeconds without confirmed damage,
-- move to the next strategy. Independent of rigLib (otherwise an incomplete
-- init blocked the cycling and we stayed stuck on Controller).
local function rotateStrategy()
    if Config.Combat.Method ~= "Auto" or State.workingMethod then return end
    if os.clock() - lastRotate >= Config.Combat.CalibrateSeconds then
        lastRotate = os.clock()
        rotationIndex = rotationIndex % #rotation + 1
        State.firedSinceRotate = false
        Util.log("No damage - trying strategy", rotation[rotationIndex])
    end
end

-- Single entry point.
function Attack.fast()
    -- This path is reached ONLY when FastAttack is unavailable or disabled
    -- (guarded in the Stepped loop): its counter therefore measures the real
    -- usage of the fallback system.
    Diagnostics.count("LegacyCombatFallbackCalls")
    local name = Attack.currentStrategy()
    local fn = Strategy[name]
    if not fn then return false end

    local ok = fn()
    if ok then
        State.attackCount = (State.attackCount or 0) + 1
        State.firedSinceRotate = true
    end
    rotateStrategy()
    return ok
end

-- True when a combat feature is running (drives the Stepped loop).
function Attack.active()
    return State.flags.AutoFarm or State.flags.FarmTarget
        or State.flags.KillAura or State.flags.SeaBeast
        or State.flags.MatActive
end

-- Makes a target hittable: widened hitbox (without which getBladeHits detects
-- nothing), collisions off, movement blocked.
-- The real size of a Roblox HumanoidRootPart: used to REPAIR mobs deformed by
-- older versions of the script.
local NORMAL_HRP = Vector3.new(2, 2, 1)

-- Prepares a target WITHOUT breaking its network state.
--
-- What was removed here, and why:
--   * `ehrp.Size = 70`: purely CLIENT-side. The server keeps the real hitbox,
--     so it did nothing for RE/RegisterAttack (which is server-authoritative),
--     but it deformed the mob, shifted its physical centre and made it float or
--     spin out -> "invincible", buggy mobs.
--   * `Humanoid.WalkSpeed = 0`: also CLIENT-side. The server kept moving the
--     mob -> desync between the position seen and the real one, so blows landed
--     beside it.
--
-- Only CanCollide=false is kept, which stops the player being pushed without
-- desyncing anything.
function Attack.prepareTarget(enemy)
    if not enemy then return end
    Util.try(function()
        local ehrp = enemy:FindFirstChild("HumanoidRootPart")
        -- Systematic repair: undoes deformations left by previous versions,
        -- even in safe mode.
        if ehrp and ehrp.Size.X > 4 then ehrp.Size = NORMAL_HRP end

        -- In safe mode we stop here: no change to the mob's state at all.
        -- Any client-side mutation (collision, speed, size) desyncs the mob
        -- from the server, which then refuses the blows.
        if Config.Farming.SafeMode then return end

        if ehrp then ehrp.CanCollide = false end
        local head = enemy:FindFirstChild("Head")
        if head then head.CanCollide = false end
    end)
end

-- Straightens out every deformed enemy in the area (UI button).
function Attack.repairMobs()
    local folder = workspace:FindFirstChild("Enemies")
    if not folder then return 0 end
    local n = 0
    for _, enemy in ipairs(folder:GetChildren()) do
        Util.try(function()
            local ehrp = enemy:FindFirstChild("HumanoidRootPart")
            if ehrp and ehrp.Size.X > 4 then
                ehrp.Size = NORMAL_HRP
                n = n + 1
            end
        end)
    end
    return n
end

function Attack.ready() return CF.ready end

-- Prepares the target and DECLARES the position to hold. The actual
-- repositioning is done at 60 Hz by Move.hold() from Heartbeat: teleporting in
-- jerks every 100 ms let gravity take over between jumps, which produced the
-- visible back-and-forth around the mob.
-- Enables Buso Haki during farming when it is not already on.
function Attack.autoHaki()
    if not Config.Player.AutoHaki then return end
    local char = Core.character()
    if char and not char:FindFirstChild("HasBuso") then
        Remote.invoke("Buso")
    end
end

-- Special selector value: impose nothing, keep the weapon in hand.
Attack.AUTO = "Auto (arme en main)"

-- Types the game recognises through a Tool's ToolTip property.
Attack.TYPES = { "Melee", "Sword", "Gun", "Blox Fruit" }

local typeSet = {}
for _, kind in ipairs(Attack.TYPES) do typeSet[kind] = true end

function Attack.isType(value)
    return typeSet[value] == true
end

local function toolsOf(container)
    local out = {}
    if not container then return out end
    for _, t in ipairs(container:GetChildren()) do
        if t:IsA("Tool") then table.insert(out, t) end
    end
    return out
end

-- First Tool in the backpack matching the requested type (ToolTip).
local function findByType(wantedType)
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    for _, t in ipairs(toolsOf(backpack)) do
        local ok, tip = pcall(function() return t.ToolTip end)
        if ok and tip == wantedType then return t end
    end
    return nil
end

local function heldTool()
    local char = Core.character()
    return char and char:FindFirstChildOfClass("Tool") or nil
end

local function heldType()
    local held = heldTool()
    if not held then return nil end
    local ok, tip = pcall(function() return held.ToolTip end)
    return ok and tip or nil
end

-- Guarantees a weapon is in hand. Three modes: Auto (touches nothing if a
-- weapon is already held), a TYPE (Melee/Sword/Gun/Blox Fruit via ToolTip), or
-- a precise NAME. No change if the wanted weapon is already equipped: that is
-- what lets you switch weapon by hand without being overridden.
function Attack.equip(selection)
    local hum = Core.humanoid()
    local char = Core.character()
    if not hum or not char then return end

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local held = heldTool()

    local function equipTool(tool)
        if tool then Util.try(function() hum:EquipTool(tool) end) end
    end

    if not selection or selection == Attack.AUTO then
        if not held then equipTool(toolsOf(backpack)[1]) end
        return
    end

    if Attack.isType(selection) then
        if heldType() == selection then return end
        local tool = findByType(selection)
        -- The game's default melee is called "Combat": CombatController:Attack
        -- requires an equipped Tool, so we also find it by name.
        if not tool and selection == "Melee" and backpack then
            tool = backpack:FindFirstChild("Combat")
        end
        if tool then
            equipTool(tool)
        elseif not held then
            equipTool(toolsOf(backpack)[1])
        end
        return
    end

    if held and held.Name == selection then return end
    local tool = backpack and backpack:FindFirstChild(selection)
    if tool then
        equipTool(tool)
    elseif not held then
        equipTool(toolsOf(backpack)[1])
    end
end

function Attack.strike(enemy)
    local ehrp = enemy and enemy:FindFirstChild("HumanoidRootPart")
    if not ehrp or not Core.hrp() then return end

    Attack.prepareTarget(enemy)

    local f = Config.Farming
    -- The current target defines which mobs are brought in (quest filter).
    State.bringFilter = enemy.Name

    if f.BringMob then
        State.holdTarget = nil
        State.holdOffset = nil
        -- Fixed flight point, taken above the target: the mobs will be brought
        -- just below, in range, with nothing going through the floor.
        if not State.bringAnchor then
            State.bringAnchor = CFrame.new(
                ehrp.Position + Vector3.new(0, f.AttackHeight + f.BringHeight, 0))
        end
    else
        State.holdTarget = ehrp
        State.holdOffset = CFrame.new(0, f.AttackHeight, f.AttackBack)
        -- Immediate AND oriented placement: without it the first strike goes
        -- out of range (or with our back to the mob) until the next Heartbeat.
        Move.faceTarget(ehrp, State.holdOffset)
    end

    Attack.equip(State.selectedWeapon)
    Attack.autoHaki()
    -- Deliberately NO call to Attack.fast() here: the Stepped loop is the only
    -- one that strikes. Striking from both places consumed the Validator token
    -- twice per attack and desynced the counter, which is why damage only got
    -- through every other time.
end

function Attack.releaseHold()
    State.holdTarget = nil
    State.holdOffset = nil
    -- Release the anchor: otherwise the player would stay stuck flying after
    -- the target dies, preventing movement to the next one.
    State.bringAnchor = nil
end

--=============================================================================
-- ENEMIES
--=============================================================================
local Enemies = {}

function Enemies.folder() return workspace:FindFirstChild("Enemies") end

function Enemies.nearest(name, maxRange)
    local t0 = Diagnostics.start()
    local folder = Enemies.folder()
    local hrp = Core.hrp()
    if not folder or not hrp then
        Diagnostics.stop("Enemies.nearest", t0, 0, 0)
        return nil
    end
    local best, bestDist
    local children = folder:GetChildren()
    for _, e in ipairs(children) do
        if not name or e.Name == name then
            local ehrp = e:FindFirstChild("HumanoidRootPart")
            local ehum = e:FindFirstChildOfClass("Humanoid")
            if ehrp and ehum and ehum.Health > 0 then
                local d = Util.dist(hrp.Position, ehrp.Position)
                if (not bestDist or d < bestDist) and (not maxRange or d <= maxRange) then
                    best, bestDist = e, d
                end
            end
        end
    end
    Diagnostics.stop("Enemies.nearest", t0, #children, best and 1 or 0)
    return best, bestDist
end

-- First mob found among a list of names (for materials).
function Enemies.nearestOfList(names)
    -- Note: each iteration restarts a full scan. The cumulative cost is
    -- measured here, separately from Enemies.nearest.
    local t0 = Diagnostics.start()
    for i, n in ipairs(names) do
        local e = Enemies.nearest(n)
        if e then
            Diagnostics.stop("Enemies.nearestOfList", t0, i, 1)
            return e
        end
    end
    Diagnostics.stop("Enemies.nearestOfList", t0, #names, 0)
    return nil
end

function Enemies.nearestNPC(name)
    local folder = workspace:FindFirstChild("NPCs")
    local hrp = Core.hrp()
    if not folder or not hrp then return nil end
    local best, bestDist
    for _, npc in ipairs(folder:GetChildren()) do
        if npc.Name == name then
            local nhrp = npc:FindFirstChild("HumanoidRootPart")
            if nhrp then
                local d = Util.dist(hrp.Position, nhrp.Position)
                if not bestDist or d < bestDist then best, bestDist = npc, d end
            end
        end
    end
    return best, bestDist
end

function Enemies.listNames()
    local names, seen = {}, {}
    local folder = Enemies.folder()
    if folder then
        for _, e in ipairs(folder:GetChildren()) do
            if not seen[e.Name] then
                seen[e.Name] = true
                table.insert(names, e.Name)
            end
        end
    end
    table.sort(names)
    return names
end

--=============================================================================
-- QUESTS
--=============================================================================
local Quests = {}

function Quests.current()
    local level, sea = Core.level(), State.sea
    local fallback
    for _, q in ipairs(Config.Quests) do
        if q.Sea == sea then
            if level >= q.Min and level <= q.Max then return q end
            fallback = q
        end
    end
    return fallback
end

local function questFrame()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local main = pg and pg:FindFirstChild("Main")
    return main and main:FindFirstChild("Quest")
end

function Quests.isActive()
    local q = questFrame()
    return q ~= nil and q.Visible == true
end

function Quests.activeTitle()
    local q = questFrame()
    if not q or not q.Visible then return nil end
    local ok, txt = pcall(function() return q.Container.QuestTitle.Title.Text end)
    return ok and txt or nil
end

--=============================================================================
-- FARMING
--=============================================================================
local Farming = {}

function Farming.set(value)
    Core.setFlag("AutoFarm", value, Config.Loops.Farm, Farming.tick)
    if not value then
        Move.stopTween()
        State.bringFilter = nil
    end
end

-- Stays locked on one enemy until it dies rather than re-sweeping the
-- Workspace every frame: that is what makes the farm genuinely efficient.
-- `guard` decides whether the loop should continue (flag still on, etc.).
local function engage(enemy, guard)
    local t0 = Diagnostics.start()
    local hum = enemy:FindFirstChildOfClass("Humanoid")
    if not hum then
        Diagnostics.stop("engage", t0, 0, 0)
        return
    end

    local lastHealth = hum.Health
    local lastProgress = os.clock()
    while State.alive and guard() and enemy.Parent
        and hum.Health > 0 and Core.alive() do
        -- Give up if the target stops losing health for too long: without this,
        -- an unreachable mob blocked the farm indefinitely.
        if hum.Health < lastHealth then lastProgress = os.clock() end
        if os.clock() - lastProgress > Config.Farming.EngageTimeout then
            Util.log("Target dropped (no damage for", Config.Farming.EngageTimeout, "s)")
            break
        end
        Attack.strike(enemy)
        task.wait(Config.Combat.AttackDelay)

        -- Damage observation: the only proof a strategy really works. It is
        -- what locks in Auto mode.
        if hum.Health < lastHealth then
            State.damageSeen = (State.damageSeen or 0) + 1
            Attack.confirmWorking()
        end
        lastHealth = hum.Health
    end
    -- `found` = 1 if the target died during the engagement.
    Diagnostics.stop("engage", t0, 1, (hum.Health <= 0) and 1 or 0)
    Attack.releaseHold()
end

function Farming.tick()
    if not State.flags.AutoFarm then return end

    -- The AutomationCore, when attached, replaces the body below entirely: it
    -- does its own detection, its own target validation and its own recovery.
    -- The historical loop stays in place as a fallback if the core could not
    -- load.
    local driver = StrawberryHub.FarmDriver
    if driver and Config.Farming.UseAutomationCore then
        return driver()
    end

    -- Death: stop all movement and let the respawn happen.
    if not Core.alive() then
        Move.stopTween()
        task.wait(Config.Farming.RespawnWait)
        return
    end

    local q = Quests.current()
    if not q then return end

    -- Bring filter maintained on every tick: without it the filter vanished
    -- between two targets and every mob in the zone was vacuumed up.
    State.bringFilter = q.Name

    -- Distant-zone transit (Fishman / Ship / Sky) through requestEntrance.
    if q.Entrance then
        local hrp = Core.hrp()
        if hrp and Util.dist(q.QCF.Position, hrp.Position) > 10000 then
            Remote.invoke("requestEntrance", q.Entrance)
            return
        end
    end

    local function stillFarming() return State.flags.AutoFarm end

    -- "No Quest" mode: hit the mob without ever taking the quest.
    if Config.Farming.Mode == "No Quest" then
        local enemy = Enemies.nearest(q.Name)
        if enemy then
            engage(enemy, stillFarming)
        else
            Move.tweenTo(q.MonCF)
        end
        return
    end

    -- "Quest" mode: abandon a quest that no longer matches the level band.
    local title = Quests.activeTitle()
    if title and not string.find(title, q.Name, 1, true) then
        Remote.invoke("AbandonQuest")
        return
    end

    if not Quests.isActive() then
        Move.tweenTo(q.QCF)
        local hrp = Core.hrp()
        if hrp and Util.dist(q.QCF.Position, hrp.Position) <= 8 then
            Remote.invoke("StartQuest", q.Quest, q.QLevel)
        end
        return
    end

    local enemy = Enemies.nearest(q.Name)
    if enemy then
        -- Drop the target too if the quest ends in the meantime.
        engage(enemy, function()
            return State.flags.AutoFarm and Quests.isActive()
        end)
    else
        Move.tweenTo(q.MonCF)
    end
end

Farming.engage = engage

--=============================================================================
-- COMBAT
--=============================================================================
local Combat = {}

function Combat.setTarget(value)
    Core.setFlag("FarmTarget", value, Config.Loops.Combat, function()
        if not State.flags.FarmTarget or not Core.alive() then return end
        State.bringFilter = Config.Combat.SelectedTarget
        local enemy = Enemies.nearest(Config.Combat.SelectedTarget)
        if enemy then
            Farming.engage(enemy, function() return State.flags.FarmTarget end)
        end
    end)
    if not value then Move.stopTween() end
end

-- Strike without teleporting: useful in town / raids.
function Combat.setKillAura(value)
    Core.setFlag("KillAura", value, Config.Loops.Combat, function()
        if not State.flags.KillAura or not Core.alive() then return end
        -- The strike is delivered by the Stepped loop (the KillAura flag is
        -- included in Attack.active): here we only arm the character.
        if Enemies.nearest(nil, Config.Combat.AuraRange) then
            Attack.equip(State.selectedWeapon)
            Attack.autoHaki()
        end
    end)
end

--=============================================================================
-- MATERIALS
--=============================================================================
local Materials = {}

local function refreshMaterialFlag()
    for flag, on in pairs(State.flags) do
        if on and string.sub(flag, 1, 4) == "Mat_" then
            State.flags.MatActive = true
            return
        end
    end
    State.flags.MatActive = false
end

function Materials.set(name, value)
    local flag = "Mat_" .. name
    Core.setFlag(flag, value, Config.Loops.Material, function()
        if not State.flags[flag] or not Core.alive() then return end
        local info = Config.Materials[name]
        if not info then return end
        local target = Enemies.nearestOfList(info.mobs)
        if target then
            State.bringFilter = target.Name
            Farming.engage(target, function() return State.flags[flag] end)
        end
    end)
    refreshMaterialFlag()
    if not value then Move.stopTween() end
end

--=============================================================================
-- TELEPORT
--=============================================================================
local Teleport = {}

function Teleport.locationsFolder()
    local origin = workspace:FindFirstChild("_WorldOrigin")
    return origin and origin:FindFirstChild("Locations")
end

function Teleport.listIslands()
    local names = {}
    local folder = Teleport.locationsFolder()
    if folder then
        for _, loc in ipairs(folder:GetChildren()) do table.insert(names, loc.Name) end
        table.sort(names)
    end
    return names
end

function Teleport.toIsland(name)
    local folder = Teleport.locationsFolder()
    local loc = folder and folder:FindFirstChild(name)
    if loc then Move.tweenTo(loc.CFrame + Vector3.new(0, 6, 0)) end
end

function Teleport.toSea(sea)
    local dest = Config.Travel[sea]
    if dest then Remote.invoke(dest) end
end

--=============================================================================
-- SHOP
--=============================================================================
local Shop = {}

function Shop.setFightingStyle(entry, value)
    local flag = "Fight_" .. entry.remote
    Core.setFlag(flag, value, Config.Loops.Shop, function()
        if not State.flags[flag] or not Core.alive() then return end
        local npc = Enemies.nearestNPC(entry.npc)
        local nhrp = npc and npc:FindFirstChild("HumanoidRootPart")
        if not nhrp then return end
        Move.snapTo(nhrp.CFrame * CFrame.new(0, 4, 5))
        local hrp = Core.hrp()
        if hrp and Util.dist(hrp.Position, nhrp.Position) < 14 then
            Remote.invoke(entry.remote)
        end
    end)
end

function Shop.buyAbility(entry) Remote.invoke(table.unpack(entry.args)) end

function Shop.redeemAll()
    task.spawn(function()
        for _, code in ipairs(Config.Codes) do
            Remote.redeem(code)
            task.wait(0.2)
        end
    end)
end

function Shop.rerollRace() Remote.invoke("BlackbeardReward", "Reroll", "2") end

function Shop.resetStats()
    Remote.invoke("BlackbeardReward", "Refund", "1")
    Remote.invoke("BlackbeardReward", "Refund", "2")
end

--=============================================================================
-- PLAYER
--=============================================================================
local Player = {}

function Player.initAntiAFK()
    Core.bind(LocalPlayer.Idled:Connect(function()
        if not Config.Player.AntiAFK then return end
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end))
end

-- Re-equips the weapon and restarts cleanly after a respawn.
function Player.initRespawn()
    Core.bind(LocalPlayer.CharacterAdded:Connect(function(char)
        Move.stopTween()
        char:WaitForChild("HumanoidRootPart", 15)
        task.wait(Config.Farming.RespawnWait)
        -- activeController is recreated on every respawn: without this re-init,
        -- the fast attack silently stops working after a death.
        Attack.init()
        Attack.hookAnimations()
        if State.selectedWeapon then Attack.equip(State.selectedWeapon) end
    end))
end

function Player.setStats(value)
    Core.setFlag("AutoStats", value, Config.Loops.Stats, function()
        if not State.flags.AutoStats then return end
        local amount = tostring(Config.Player.StatsPerTick)
        local map = { Melee = "Melee", Defense = "Defense", Sword = "Sword",
                      Gun = "Gun", Fruit = "DevilFruit" }
        for key, stat in pairs(map) do
            if Config.Player.Stats[key] then Remote.invoke("AddPoint", stat, amount) end
        end
    end)
end

--=============================================================================
-- PERFORMANCE
--=============================================================================
local Performance = {}

function Performance.fpsBoost()
    Util.try(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        settings().Rendering.QualityLevel = 1
        for _, v in ipairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                v.Material = Enum.Material.Plastic
                v.Reflectance = 0
            elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
                v.Lifetime = NumberRange.new(0)
            elseif v:IsA("Explosion") then
                v.BlastPressure, v.BlastRadius = 1, 1
            end
        end
    end)
end

function Performance.removeFog()
    Util.try(function()
        Lighting.FogEnd, Lighting.FogStart = 9e9, 9e9
        local layers = Lighting:FindFirstChild("LightingLayers")
        if layers then layers:Destroy() end
    end)
end


--=============================================================================
-- ANTI-DETECTION — blocks the game's detection/ban/kick telemetry
--=============================================================================
--  Blox Fruits reports anti-cheat signals to the server through tagged remotes
--  (TeleportDetect, CHECKER, BANREMOTE, KICKREMOTE...). This module intercepts
--  `game`'s __namecall and swallows those outgoing calls before they reach the
--  server, while letting everything else through.
--
--  Taken from repeat.lua's hook, but made REVERSIBLE: the original metamethod
--  is stored and restored by disable()/Unload(). Nothing hostile to the player
--  is touched; only the self-reporting is prevented.
--
--  Limitation: it does not guarantee no ban (the server has other checks).
--  It can break on a major update -> everything is under pcall, off in one click.
--=============================================================================
local AntiDetection = {}

local hooked = false
local originalNamecall

-- Case-insensitive lookup in the list of blocked tags.
local function isBlocked(value)
    if value == nil then return false end
    local key = string.lower(tostring(value))
    for _, name in ipairs(Config.AntiDetection.Remotes) do
        if string.lower(name) == key then return true end
    end
    return false
end

function AntiDetection.enable()
    if hooked then return true end
    if not (getrawmetatable and setreadonly and newcclosure) then
        State.antiDetectError = "executor without getrawmetatable/setreadonly"
        Util.log(State.antiDetectError)
        return false
    end

    local ok = pcall(function()
        local mt = getrawmetatable(game)
        originalNamecall = mt.__namecall
        setreadonly(mt, false)

        mt.__namecall = newcclosure(function(self, ...)
            if Config.AntiDetection.Enabled then
                local args = { ... }
                -- Block if the tag (first argument) OR the remote name matches.
                if isBlocked(args[1]) then return end
                local okName, name = pcall(function() return self.Name end)
                if okName and isBlocked(name) then return end
            end
            return originalNamecall(self, ...)
        end)

        setreadonly(mt, true)
    end)

    if ok then
        hooked = true
        AntiDetection.startFFlags()
    else
        State.antiDetectError = "__namecall hook failed"
        Util.log(State.antiDetectError)
    end
    return ok
end

function AntiDetection.disable()
    if not hooked then return end
    pcall(function()
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        mt.__namecall = originalNamecall
        setreadonly(mt, true)
    end)
    hooked = false
end

-- Disables abuse-report screenshots (a single loop).
function AntiDetection.startFFlags()
    if not Config.AntiDetection.DisableAbuseScreenshots then return end
    if type(setfflag) ~= "function" then return end
    if State.flags.AntiScreenshot then return end
    State.flags.AntiScreenshot = true
    Core.loop("AntiScreenshot", 1, function()
        if not Config.AntiDetection.DisableAbuseScreenshots then return end
        setfflag("AbuseReportScreenshot", "False")
        setfflag("AbuseReportScreenshotPercentage", "0")
    end)
end

function AntiDetection.isActive() return hooked end

--=============================================================================
-- SERVER
--=============================================================================
local Server = {}

function Server.rejoin()
    TeleportService:Teleport(game.PlaceId, LocalPlayer)
end

local function fetchServers()
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100")
        :format(game.PlaceId)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if not ok then return nil end
    local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
    return ok2 and data or nil
end

function Server.hop(lowestOnly)
    task.spawn(function()
        local data = fetchServers()
        if not data or not data.data then return end
        local best
        for _, s in ipairs(data.data) do
            if s.playing and s.maxPlayers and s.playing < s.maxPlayers and s.id ~= game.JobId then
                if not lowestOnly then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
                    return
                end
                if not best or s.playing < best.playing then best = s end
            end
        end
        if best then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, best.id, LocalPlayer)
        end
    end)
end

--=============================================================================
-- EVENTS
--=============================================================================
local Events = {}

function Events.setSeaBeast(value)
    Core.setFlag("SeaBeast", value, Config.Loops.SeaBeast, function()
        if not State.flags.SeaBeast or not Core.alive() then return end
        local folder = workspace:FindFirstChild("SeaBeasts")
        if not folder then return end
        local beast = folder:GetChildren()[1]
        local bhrp = beast and beast:FindFirstChild("HumanoidRootPart")
        if bhrp then
            Attack.equip(State.selectedWeapon)
            Attack.autoHaki()
            Move.snapTo(bhrp.CFrame * CFrame.new(0, 30, 40))
        end
    end)
    if not value then Move.stopTween() end
end

--=============================================================================
-- FAST ATTACK — free rate plus an optional no-animation mode
--=============================================================================
--  Principle: do NOT go through CombatController:Attack(), which plays the
--  animation and whose RunHitDetection loops while that animation runs
--  (`while elapsed < length and track.IsPlaying`). The rate is then the
--  animation's, i.e. that of a normal click.
--
--  So we send directly the two messages that chain ends up producing:
--
--      RE/RegisterAttack(delay, combo)           -> declares the blow
--      Global.SendHitsToServer(part, extras)     -> applies the damage
--
--  Components: Configuration · TargetManager · WeaponAdapter
--              · AnimationController · AttackController
--=============================================================================
local FastAttack = {}

------------------------------------------------------------------ Configuration
-- The values live in Config.FastAttack (central configuration).
local function cfg() return Config.FastAttack end

------------------------------------------------------------------ TargetManager
local TargetManager = {}
FastAttack.TargetManager = TargetManager

-- Part names the game accepts (CombatUtil's allow-list): a hit sent on any
-- other part is ignored by the server.
local VALID_PARTS = {
    "UpperTorso", "LowerTorso", "Head", "ModelHitbox", "Torso",
    "RightUpperArm", "RightLowerArm", "RightHand",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
    "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
}

function TargetManager:GetHitPart(rig)
    for _, name in ipairs(VALID_PARTS) do
        local part = rig:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part end
    end
    return nil
end

function TargetManager:IsValid(rig, origin, range)
    if not rig or not rig.Parent then return false end
    local hum = rig:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local root = rig:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    return (root.Position - origin).Magnitude <= range
end

-- Returns { first = BasePart, extras = { {rig, part}, ... }, count = n }
-- `first` and `extras` map exactly onto the first two arguments RegisterHit
-- expects.
function TargetManager:FindTargets()
    local t0 = Diagnostics.start()
    local hrp = Core.hrp()
    local folder = workspace:FindFirstChild("Enemies")
    if not hrp or not folder then
        Diagnostics.stop("TargetManager:FindTargets", t0, 0, 0)
        return nil
    end

    local origin = hrp.Position
    local range = cfg().Range
    local maxTargets = cfg().MaxTargets

    local first, extras, count = nil, {}, 0
    local children = folder:GetChildren()
    for _, rig in ipairs(children) do
        if count >= maxTargets then break end
        if self:IsValid(rig, origin, range) then
            local part = self:GetHitPart(rig)
            if part then
                count = count + 1
                if not first then
                    first = part
                else
                    table.insert(extras, { rig, part })
                end
            end
        end
    end
    Diagnostics.stop("TargetManager:FindTargets", t0, #children, count)
    if not first then return nil end
    return { first = first, extras = extras, count = count }
end

-- Single nearest target (used by the farm to position itself).
function TargetManager:FindNearest(name)
    return Enemies.nearest(name, cfg().Range)
end

------------------------------------------------------------------ WeaponAdapter
-- Common interface: the AttackController knows no weapon in particular.
local WeaponAdapter = {}
FastAttack.WeaponAdapter = WeaponAdapter

local comboIndex = 0

function WeaponAdapter:GetTool()
    local char = Core.character()
    if not char then return nil end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then return tool end
    -- Fallback: tool tagged by the game (CombatUtil's GetEquippedWeaponTool).
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool")
            and (child:HasTag("MeleeTool") or child:HasTag("GunTool")) then
            return child
        end
    end
    return nil
end

function WeaponAdapter:GetWeaponType()
    local tool = self:GetTool()
    if not tool then return nil end
    local ok, t = pcall(function() return tool:GetAttribute("WeaponType") end)
    return ok and t or nil
end

-- Validation delegated to the game when available: CanAttack checks Stun,
-- Busy, Sit and the global cooldown (Global.tapCooldown).
function WeaponAdapter:CanAttack()
    local char = Core.character()
    local hum = Core.humanoid()
    if not char or not hum or hum.Health <= 0 then return false end
    if not self:GetTool() then return false end

    local cu = CF.combatUtil
    if cu and type(cu.CanAttack) == "function" then
        local ok, allowed = pcall(function()
            return cu:CanAttack(char, self:GetWeaponType())
        end)
        -- CanAttack returns true, or nothing at all if the attack is refused.
        if ok and not allowed then return false end
    end
    return true
end

-- Triggers an attack on the given targets. Returns true when the pair
-- (declaration + hits) was sent.
-- READ-ONLY probe: records what the game declares for the equipped weapon, to
-- identify the source of truth for the delay sent to RegisterAttack.
-- Runs only when Diagnostics is on, and once per weapon.
function WeaponAdapter:ProbeWeapon(tool)
    if not Diagnostics.isEnabled() or not tool then return end
    local cu = CF.combatUtil
    if not cu then return end

    local ok, name = pcall(function()
        return tool:GetAttribute("WeaponName") or tool.Name
    end)
    if not ok or not name then return end
    if Diagnostics.seen("weapon", name) then return end

    pcall(function()
        local data = cu:GetWeaponData(name)
        if not data then
            Diagnostics.observe("weapon", name, "GetWeaponData -> nil")
            return
        end
        local parts = {
            "type=" .. tostring(data.WeaponType),
            "hitbox=" .. tostring(data.HitboxMagnitude),
            "frontHits=" .. tostring(data.ValidateFrontHits),
            "vfxDelay=" .. tostring(data.VFXDelay),
            "configSwingDelay=" .. tostring(Config.FastAttack.SwingDelay),
        }
        local basic = data.Moveset and data.Moveset.Basic
        if basic then
            for i = 1, 4 do
                local m = basic[i]
                if m then
                    parts[#parts + 1] = ("combo%d{vfx=%s push=%s aoe=%s}")
                        :format(i, tostring(m.VFXDelay), tostring(m.PushDelay),
                            tostring(m.AOEDelay))
                end
            end
        else
            parts[#parts + 1] = "Moveset.Basic=nil"
        end
        Diagnostics.observe("weapon", name, table.concat(parts, "  "))
    end)
end

function WeaponAdapter:Attack(targets)
    local tool = self:GetTool()
    if not tool or not targets then return false end

    self:ProbeWeapon(tool)
    Diagnostics.count("ModernCombatCalls")

    -- The cooldown lives on the tool: release it to chain blows.
    pcall(function() tool:SetAttribute("Cooldown", 0) end)

    comboIndex = comboIndex % 4 + 1

    local sent = false
    -- 1) Declare the blow (no animation: we do not call Attack()).
    if CF.registerAttack then
        sent = pcall(function()
            CF.registerAttack:FireServer(cfg().SwingDelay, comboIndex)
        end)
    end

    -- 2) Register the hits: this is what deals the damage.
    local G = CF.globalMod
    if G and type(G.SendHitsToServer) == "function" then
        Diagnostics.count("GlobalSendHits_Modern")
        local ok = pcall(function()
            G.SendHitsToServer(targets.first, targets.extras)
        end)
        sent = sent and ok or ok
    end
    return sent
end

------------------------------------------------------------ AnimationController
-- Hides combat animations client-side only. The combat logic is untouched:
-- only the tracks are stopped as they start playing.
local AnimationController = {}
FastAttack.AnimationController = AnimationController

local animConn, animatorConn
local enabled = false

-- An animation belongs to the combat system when its name follows the
-- convention set by CombatUtil.ToggleLoadMovesetAnims: "<weapon>-basic<N>" or
-- "<weapon>-<key>". No name is hardcoded.
local function isCombatAnim(track)
    local ok, name = pcall(function() return track.Animation.Name end)
    if not ok or not name then return false end
    if string.find(name, "-basic", 1, true) then return true end

    -- Checked against the game's moveset cache, when reachable.
    local cu = CF.combatUtil
    local hum = Core.humanoid()
    if cu and hum and type(cu.GetMovesetAnimCache) == "function" then
        local ok2, cache = pcall(function() return cu:GetMovesetAnimCache(hum) end)
        if ok2 and type(cache) == "table" and cache[name] then return true end
    end
    return false
end

local function silence(track)
    if not enabled then return end
    if isCombatAnim(track) then
        pcall(function() track:Stop(0) end)
    end
end

local function bindAnimator()
    local hum = Core.humanoid()
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    if animConn then animConn:Disconnect() end
    animConn = animator.AnimationPlayed:Connect(silence)
    -- Also stop the ones already running.
    pcall(function()
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            silence(track)
        end
    end)
end

function AnimationController:Enable()
    if enabled then return end
    enabled = true
    bindAnimator()
    -- The character changes on respawn: rebind.
    if not animatorConn then
        animatorConn = Core.bind(LocalPlayer.CharacterAdded:Connect(function()
            task.wait(1)
            if enabled then bindAnimator() end
        end))
    end
end

function AnimationController:Disable()
    enabled = false
    if animConn then
        animConn:Disconnect()
        animConn = nil
    end
end

function AnimationController:IsEnabled() return enabled end

------------------------------------------------------------- AttackController
local AttackController = {}
FastAttack.AttackController = AttackController

local running = false
local busy = false          -- empeche deux attaques simultanees
local backoff = 0           -- ralentissement temporaire apres des refus
local refusals = 0

function AttackController:IsRunning() return running end

function AttackController:Stop()
    running = false
    busy = false
    backoff = 0
    refusals = 0
end

-- One iteration: check state, look for a target, attack.
-- Returns the delay to respect before the next attempt.
function AttackController:Step()
    if busy then return cfg().Interval end
    busy = true

    local delay = cfg().Interval
    Util.try(function()
        if not WeaponAdapter:CanAttack() then
            Diagnostics.count("state.AttackRefused")
            refusals = refusals + 1
            -- Repeated refusals: slow down instead of hammering the server.
            backoff = math.min(cfg().MaxBackoff, backoff + cfg().Interval)
            delay = cfg().Interval + backoff
            return
        end

        local targets = TargetManager:FindTargets()
        if not targets then
            -- Nothing to hit: take a breath, without treating it as a refusal.
            delay = cfg().IdleInterval
            return
        end

        if WeaponAdapter:Attack(targets) then
            refusals = 0
            backoff = 0
            State.attackCount = (State.attackCount or 0) + 1
            delay = cfg().Interval
        else
            refusals = refusals + 1
            backoff = math.min(cfg().MaxBackoff, backoff + cfg().Interval)
            delay = cfg().Interval + backoff
        end
    end)

    busy = false
    return delay
end

function AttackController:Start()
    if running then return end
    running = true
    task.spawn(function()
        while running and State.alive do
            local wait = self:Step()
            task.wait(wait)
        end
        running = false
    end)
end

------------------------------------------------------------------ facade
function FastAttack:Start()
    Diagnostics.count("state.FastAttack.Start")
    if cfg().NoAnimation then AnimationController:Enable() end
    AttackController:Start()
end

function FastAttack:Stop()
    Diagnostics.count("state.FastAttack.Stop")
    AttackController:Stop()
    AnimationController:Disable()
end

function FastAttack:SetNoAnimation(value)
    Config.FastAttack.NoAnimation = value
    if value and AttackController:IsRunning() then
        AnimationController:Enable()
    elseif not value then
        AnimationController:Disable()
    end
end

function FastAttack:IsReady()
    return CF.globalMod ~= nil
        and type(CF.globalMod.SendHitsToServer) == "function"
        and CF.registerAttack ~= nil
end

--=============================================================================
-- INTERFACE SUPPORT
--=============================================================================
-- Weapon choices offered: "Auto", then the game's four combat types, then the
-- specific weapons actually owned. Selecting a TYPE is the recommended mode:
-- it keeps working when you change sword or fruit.
local function listWeapons()
    local out = { Attack.AUTO }
    for _, kind in ipairs(Attack.TYPES) do
        table.insert(out, kind)
    end

    local seen = {}
    for _, src in ipairs({ LocalPlayer:FindFirstChild("Backpack"), Core.character() }) do
        if src then
            for _, t in ipairs(src:GetChildren()) do
                if t:IsA("Tool") and not seen[t.Name] then
                    seen[t.Name] = true
                    -- A name identical to a type is not added, to avoid two
                    -- indistinguishable entries in the list.
                    if not Attack.isType(t.Name) then
                        table.insert(out, t.Name)
                    end
                end
            end
        end
    end
    return out
end


--=============================================================================
-- INIT
--=============================================================================
StrawberryHub = { Config = Config, State = State, Loaded = false }

-- Primitives exposed to the AutomationCore and to Runtime.Interface. This is
-- the only contact surface between the engine and everything built on top of
-- it, which is what lets either side be tested or replaced on its own.
--
-- PlayerModule is the runtime's player feature set; Player is the Roblox
-- LocalPlayer instance. Two different things, so two different names.
StrawberryHub.Internal = {
    Config = Config, State = State, Util = Util, Core = Core,
    Remote = Remote, Move = Move, Attack = Attack, Enemies = Enemies,
    Quests = Quests, Farming = Farming, Combat = Combat, Server = Server,
    Teleport = Teleport, Materials = Materials, Shop = Shop,
    Performance = Performance, AntiDetection = AntiDetection,
    Events = Events, FastAttack = FastAttack, Diagnostics = Diagnostics,
    Persist = Persist, PlayerModule = Player, Player = LocalPlayer,
    listWeapons = listWeapons,
}

function StrawberryHub.Unload()
    State.alive = false
    Core.stopAll()
    Diagnostics.cleanup()
    AntiDetection.disable()
    Move.stopTween()
    Move.updateFloor(false)
    for _, conn in ipairs(State.connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(State.connections)
    for _, gui in ipairs(State.guis) do
        pcall(function() gui:Destroy() end)
    end
    table.clear(State.guis)
    getgenv().StrawberryHub = nil
end

getgenv().StrawberryHub = StrawberryHub

Persist.load()
Util.log("Startup — Place:", game.PlaceId, "Sea:", State.sea,
    "Executor:", (identifyexecutor and identifyexecutor()) or "unknown")

-- Enabled first of all: the protection must cover the init phase too.
if Config.AntiDetection.Enabled then AntiDetection.enable() end

Player.initAntiAFK()
Player.initRespawn()

Attack.init()
Attack.hookAnimations()

-- The game resets the hitbox and the timings to their defaults constantly: we
-- re-force them while a combat feature is active.
-- THIS is where the attack is actually delivered. The game resets the
-- controller's timings every frame, so we have to strike from Stepped,
-- continuously, while a combat feature is active.
-- Fast Attack supervisor: starts/stops the module's loop depending on whether
-- a combat feature is active. The module handles its own rate, its slowdown on
-- refusals and its clean shutdown.
Core.bind(RunService.Heartbeat:Connect(function()
    if not State.alive then return end
    local want = Config.FastAttack.Enabled and Attack.active()
        and FastAttack:IsReady()
    if want and not FastAttack.AttackController:IsRunning() then
        FastAttack:Start()
    elseif not want and FastAttack.AttackController:IsRunning() then
        FastAttack:Stop()
    end
end))

-- Fallback: when the module is unavailable (remotes not found), we drop back
-- to the old strategy rotation, driven by Stepped.
local lastPulse = 0
Core.bind(RunService.Stepped:Connect(function()
    if not State.alive or not Attack.active() then return end
    if Config.FastAttack.Enabled and FastAttack:IsReady() then return end
    if not (State.holdTarget or State.flags.KillAura or State.flags.SeaBeast) then
        return
    end
    local now = os.clock()
    if now - lastPulse < Config.Combat.AttackDelay then return end
    lastPulse = now
    Attack.fast()
end))

Core.bind(RunService.Heartbeat:Connect(function()
    if not State.alive then return end
    Move.updateFloor(Move.wantFloor())
    if Attack.active() then Move.hold() end
end))

-- The window itself is built by Runtime.Interface, on top of the StrawberryUI
-- library. This module now stops at the engine: it exposes primitives and
-- owns no presentation code.
StrawberryHub.Loaded = true

return StrawberryHub
