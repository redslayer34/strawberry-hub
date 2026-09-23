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
