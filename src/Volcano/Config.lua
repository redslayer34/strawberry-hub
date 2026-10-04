--=============================================================================
-- VOLCANO CONFIG — getgenv().StrawberryVolcano, merged over the defaults
--=============================================================================
--  Set before the loader:
--
--      getgenv().StrawberryVolcano = {
--          Weapon = "Sword",
--          CollectBones = false,
--          WebhookUrl = "https://discord.com/api/webhooks/...",   -- your own
--      }
--
--  Anything left out keeps its default; SkillWeapons is merged key by key.
--  Same rules as the Kaitun's config (Kaitun.Config.mergeOver).
--=============================================================================

local KaitunConfig = require("Kaitun.Config")

local Config = {}

Config.DEFAULTS = {
    Team = "Pirates",
    Speed = 300,             -- flying speed (studs/s)
    Boat = "Guardian",       -- the boat bought at the Tiki dealer (Boat.NAMES)
    BoatSpeed = 350,
    Weapon = "Melee",        -- golems and the magnet's mobs: "Melee", "Sword" or "Blox Fruit"
    -- The skills that plug the erupting rocks.
    SkillWeapons = { Melee = true, Sword = true, ["Blox Fruit"] = true, Gun = true },
    CraftMagnet = true,      -- false: bring your own Volcanic Magnet
    CollectBones = true,     -- the Dino Bones after the event
    WalkOnWater = true,
    FpsBoost = false,
    BlackScreen = false,
    WebhookUrl = "",         -- your own: a message when the island spawns
    ShowScreen = true,
}

Config.URL = "https://raw.githubusercontent.com/redslayer34/strawberry-hub/claude/repo-exploration-ez26bn/StrawberryVolcano.lua"

local current = KaitunConfig.mergeOver(Config.DEFAULTS, nil)

function Config.merge(user)
    return KaitunConfig.mergeOver(Config.DEFAULTS, user)
end

function Config.load(user)
    current = Config.merge(user)
    return current
end

function Config.get(key)
    return current[key]
end

-- The script queued with queue_on_teleport: the config, then the loader.
function Config.loader()
    return "getgenv().StrawberryVolcano = " .. KaitunConfig.serialize(current)
        .. "\nloadstring(game:HttpGet(\"" .. Config.URL .. "\"))()"
end

-- Test hook.
function Config.reset()
    current = Config.merge(nil)
end

return Config
