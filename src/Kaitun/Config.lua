--=============================================================================
-- KAITUN CONFIG — getgenv().StrawberryKaitun, merged over the defaults
--=============================================================================
--  Set before the loader:
--
--      getgenv().StrawberryKaitun = {
--          Team = "Marines",
--          Skip = { CDK = true },
--          WebhookUrl = "https://discord.com/api/webhooks/...",   -- your own
--      }
--
--  Anything left out keeps its default. Tables (Skip, Stats) are merged key
--  by key, so `Skip = { CDK = true }` keeps every other task on.
--=============================================================================

local Config = {}

Config.DEFAULTS = {
    Team = "Pirates",
    Hop = true,              -- allow server hops (Soul Guitar full moon, later the targeted hops)
    Speed = 300,             -- flying speed (studs/s)
    SkipLevel = true,        -- Teddy's skip under level 150 (Sky Bandits, God's Guards)
    RedeemCodes = true,      -- every code once per account, while levelling (2x experience)
    WalkOnWater = true,      -- an invisible floor on the sea, as in Banana / Vxeze
    GetRace = "",            -- "Cyborg" or "Ghoul": get that race (Sea 2), then V2/V3 evolve it; "" keeps yours
    StatMode = "Teddy",      -- "Teddy" (Melee first, Defense 15/100, ...) or "Even" (split over Stats)
    Stats = { Melee = true, Defense = true },   -- only for StatMode = "Even"
    Skip = {
        CDK = false,
        Tushita = false,
        Yama = false,
        SoulGuitar = false,
        Saber = false,
        Race = false,
        AwakenFruit = false,
        Rainbow = false,
        Godhuman = false,    -- every step of the melee chain (and Electric)
        Electric = false,
        Fragments = false,   -- raids for the fragments a step waits on
        MirrorFractal = false,
        ValkyrieHelm = false,
        HakiColours = false,
    },
    StoreFruits = true,
    WebhookUrl = "",
    BlackScreen = false,
    FpsBoost = true,
    ShowScreen = true,
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, inner in pairs(value) do out[key] = copy(inner) end
    return out
end

-- The defaults with `user` laid over them. Unknown keys are kept (harmless)
-- and wrong types fall back to the default.
function Config.merge(user)
    local out = copy(Config.DEFAULTS)
    if type(user) ~= "table" then return out end
    for key, value in pairs(user) do
        local default = Config.DEFAULTS[key]
        if type(default) == "table" and type(value) == "table" then
            for inner, innerValue in pairs(value) do out[key][inner] = innerValue end
        elseif default == nil or type(default) == type(value) then
            out[key] = copy(value)
        end
    end
    return out
end

local current = copy(Config.DEFAULTS)

function Config.load(user)
    current = Config.merge(user)
    return current
end

function Config.get(key)
    return current[key]
end

function Config.skipped(task)
    return current.Skip ~= nil and current.Skip[task] == true
end

-- A Lua literal of `value` (strings, numbers, booleans, tables of those),
-- for the loader queued before a server hop: getgenv() does not survive the
-- teleport, so the config travels inside the queued script.
function Config.serialize(value)
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    if kind ~= "table" then return "nil" end
    local keys = {}
    for key in pairs(value) do
        if type(key) == "string" or type(key) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do
        local name = type(key) == "string" and key:match("^[%a_][%w_]*$") and key
            or "[" .. Config.serialize(key) .. "]"
        parts[#parts + 1] = name .. " = " .. Config.serialize(value[key])
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

Config.URL = "https://raw.githubusercontent.com/redslayer34/strawberry-hub/claude/repo-exploration-ez26bn/StrawberryKaitun.lua"

-- The script queued with queue_on_teleport: the config, then the loader.
function Config.loader()
    return "getgenv().StrawberryKaitun = " .. Config.serialize(current)
        .. "\nloadstring(game:HttpGet(\"" .. Config.URL .. "\"))()"
end

-- Test hook.
function Config.reset()
    current = copy(Config.DEFAULTS)
end

return Config
