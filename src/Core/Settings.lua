--=============================================================================
-- SETTINGS — the single source of truth for every option
--=============================================================================
--  Features read settings from here and never from the UI, so they keep
--  working if the interface fails to load. The UI writes here: every Fluent
--  element uses the setting key as its Idx, the default below as its Default,
--  and Settings.set as its Callback. Fluent's SaveManager persists the
--  elements, so persistence needs nothing from this module.
--=============================================================================

local Settings = {}

Settings.DEFAULTS = {
    -- Farm
    AutoFarmLevel = false,
    Weapon = "Melee",
    BringMob = true,
    BringCount = 3,
    FarmHeight = 20,

    -- Farm modes
    AutoBoss = false,
    Boss = "",
    AllBosses = false,
    AutoKatakuri = false,
    IgnoreKatakuri = false,
    AutoBone = false,
    AutoMaterial = false,
    Material = "",
    AutoKillMob = false,
    Mob = "",
    AutoAura = false,
    AuraRadius = 300,

    -- Stack farming: tasks that interrupt the main farm
    StackNewWorld = false,
    StackThirdWorld = false,
    StackChests = false,
    StackFruit = false,
    StackHopFruit = false,
    StackFactory = false,
    StackPirateRaid = false,
    StackEliteHunter = false,
    StackHopElite = false,
    StackHakiPads = false,
    StackSummonRipIndra = false,
    StackRipIndra = false,
    StackSoulReaper = false,
    StackSummonSoulReaper = false,
    StackDoughKing = false,
    StackSummonDoughKing = false,
    StackHopDoughKing = false,
    StackDarkbeard = false,
    StackSummonDarkbeard = false,
    StackHopDarkbeard = false,

    -- Farming Other
    OtherChest = false,
    OtherChestHop = false,
    OtherChestHopAfter = 20,
    OtherChestTeleport = false,
    OtherBerry = false,
    OtherHopBerry = false,
    OtherLaw = false,
    OtherObservation = false,
    OtherObservationHop = false,
    OtherObservationV2 = false,
    OtherDojo = false,
    OtherDragonHunter = false,
    OtherFishing = false,
    OtherFishingVortex = false,
    OtherBait = "",
    OtherSellFish = false,
    OtherOpenChests = false,
    OtherReelSize = false,
    OtherAnglerQuest = false,
    OtherAnglerRarities = {},
    OtherSlapBattle = false,

    -- Devil fruit
    FruitRandom = false,
    FruitStore = false,
    FruitSniper = false,
    FruitSniperList = {},
    FruitAwaken = false,

    -- Raids
    RaidAuto = false,
    RaidName = "Flame",
    RaidCheapFruit = false,
    RaidHopFruit = false,
    RaidInstantKill = false,
    RaidKillDelay = 5,
    MultiRaid = false,
    MultiRaidAccounts = {},
    MultiRaidBuyer = false,
    MultiRaidSlot = false,

    -- Dungeon
    DungeonJoin = false,
    DungeonLeader = false,
    DungeonLeaderName = "",
    DungeonMinPlayers = 2,
    DungeonDifficulty = "Normal",
    DungeonAttack = false,
    DungeonWeapon = "Melee",
    DungeonCards = false,
    DungeonCard1 = "",
    DungeonCard2 = "",
    DungeonCard3 = "",

    -- Items
    ItemTradeBones = false,
    ItemLegendarySword = false,
    ItemHakiColour = false,
    ItemDealerHop = false,
    ItemSharkAnchor = false,
    ItemRainbowHaki = false,
    ItemYama = false,
    ItemTushita = false,
    ItemTTK = false,
    ItemYoru = false,
    ItemYoruHop = false,
    ItemCDK = false,
    CdkHopRaid = false,
    CdkHopCakeQueen = false,
    ItemSoulGuitar = false,
    GuitarHopMoon = false,
    ItemSaber = false,
    ItemMeleeMastery = false,
    ItemSwordMastery = false,
    ItemUpgradeSword = false,
    ItemUpgradeGun = false,

    -- Races
    RaceV2V3 = false,
    RaceCyborg = false,
    RaceCyborgFist = false,
    RaceCyborgHop = false,
    RaceGhoul = false,
    RaceGhoulHop = false,
    RaceDraco = false,
    RaceTurnOnV4 = false,
    RaceBuyGear = false,
    RaceChooseGear = false,
    RaceGearType = "Omega",
    RaceNoFog = false,
    RaceResetCharacter = false,
    RaceTeleportClock = false,
    RaceTrain = false,
    RacePullLever = false,
    RaceTrial = false,
    RaceKillPlayers = false,
    RaceDracoTrial = false,
    RaceHop = false,
    RaceMultiTrial = false,
    RaceMultiAccounts = {},
    RaceV3AtDoor = false,
    RaceFindMirage = false,

    -- Sea events
    SeaAuto = false,
    SeaZone = "Zone 1",
    SeaEventKinds = { SeaBeast = true, Ship = true },
    SeaBrigadeOnly = false,
    SeaBoat = "Guardian",
    SeaBoatSpeed = 350,
    SeaRepair = false,
    SeaSkillWeapons = { ["Blox Fruit"] = true, Melee = true, Sword = true, Gun = true },
    SeaDestroyIdk = false,
    SeaDriveTiki = false,
    SeaDriveHydra = false,
    SeaFindMirage = false,
    SeaKitsuneTeleport = false,
    SeaKitsuneSpawn = false,
    SeaKitsuneHop = false,
    SeaKitsuneSummon = false,
    SeaKitsuneEmbers = false,
    SeaKitsuneTrade = false,
    SeaAzureEmbers = 10,
    SeaBuySpy = false,
    SeaFindLeviathan = false,
    SeaBuyBeastHunter = false,
    SeaMultiLeviathan = false,
    SeaLeviathanOwner = "",
    SeaFrozenTeleport = false,
    SeaLeviathanStart = false,
    SeaLeviathanAttack = false,
    SeaLeviathanHeart = false,
    SeaHeartOwner = "",

    -- Volcano
    VolcanoMagnet = false,
    VolcanoFind = false,
    VolcanoEvent = false,
    VolcanoEggs = false,
    VolcanoBones = false,
    VolcanoFully = false,
    VolcanoSkipMagnet = false,
    VolcanoSkipBones = false,
    VolcanoGolemWeapon = "Melee",

    -- ESP
    EspFruit = false,
    EspBerry = false,
    EspIsland = false,
    EspPlayer = false,

    -- PVP
    PvpPlayer = "",
    PvpMethod = "Nearest enemy",
    PvpFollow = false,
    PvpAimbot = false,
    PvpGunAimbot = false,
    PvpWaterWalk = false,

    -- Screen
    ScreenWhite = false,
    ScreenBlack = false,
    ScreenBoostFps = false,
    ScreenNoNotifications = false,
    ScreenAutoRejoin = false,

    -- Webhook
    WebhookUrl = "",
    WebhookPingId = "",
    WebhookPing = false,
    WebhookProfile = false,
    WebhookStoreFruit = false,
    WebhookFruitRarities = { Mythical = true, Legendary = true },
    WebhookMirage = false,
    WebhookPrehistoric = false,
    WebhookLeviathan = false,
    WebhookIdk = false,

    -- Mastery
    MasteryFarm = false,
    MasteryWeapon = "Blox Fruit",
    MasteryHealth = 40,
    MasterySkills = { Z = true, X = true, C = true, V = true, F = true },

    -- Teleport / shop selections
    Island = "",
    Npc = "",
    FightingStyle = "",

    -- Player
    AutoStats = false,
    StatTargets = { Melee = true, Defense = true },
    Team = "Pirates",
    WalkSpeedOn = false,
    WalkSpeed = 50,
    JumpPowerOn = false,
    JumpPower = 100,
    Noclip = false,

    -- Server
    AutoExecute = true,
    HopForBoss = false,

    -- Combat
    AttackDelay = 0,

    -- Movement
    TweenSpeed = 300,
    SmartTravel = true,
    LearnPortals = false,
    RespawnShortcut = false,
}

Settings.WEAPONS = { "Melee", "Sword", "Blox Fruit", "Gun" }
Settings.MASTERY_WEAPONS = { "Blox Fruit", "Gun" }

local values = {}
local listeners = {}

function Settings.get(key)
    local value = values[key]
    if value == nil then return Settings.DEFAULTS[key] end
    return value
end

-- Unknown keys are an error on purpose: a typo in a tab would otherwise
-- create a setting no feature ever reads, and the toggle would silently do
-- nothing.
function Settings.set(key, value)
    if Settings.DEFAULTS[key] == nil then
        error("unknown setting: " .. tostring(key), 2)
    end
    if values[key] == value then return end
    values[key] = value
    for _, listener in ipairs(listeners) do
        pcall(listener, key, value)
    end
end

-- Returns a function that removes the listener.
function Settings.onChanged(fn)
    listeners[#listeners + 1] = fn
    return function()
        for index, candidate in ipairs(listeners) do
            if candidate == fn then
                table.remove(listeners, index)
                return
            end
        end
    end
end

-- Test hook: back to defaults, no listeners.
function Settings.reset()
    values, listeners = {}, {}
end

return Settings
