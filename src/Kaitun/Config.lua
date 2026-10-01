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
    Stats = { Melee = true, Defense = true },
    Skip = {
        CDK = false,
        Tushita = false,
        Yama = false,
        SoulGuitar = false,
        Saber = false,
        Race = false,
        AwakenFruit = false,
        Rainbow = false,
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

-- Test hook.
function Config.reset()
    current = copy(Config.DEFAULTS)
end

return Config
