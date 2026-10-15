--=============================================================================
-- SCENARIO kaitun_profile — the Kaitun engine on a given account
--=============================================================================
--  A discovery run: an account profile (sea, level, money, items) and the
--  Kaitun engine for 10 simulated minutes. The world is nearly empty (no
--  quests, no mobs), so the point is not to progress but to see what the
--  engine picks, which tasks rest or flap, which remotes it asks for, and
--  that nothing errors. Change PROFILE to replay another account.
--=============================================================================

local Config = require("Kaitun.Config")
local Engine = require("Kaitun.Engine")

local PROFILE = {
    sea = 2, level = 1150, beli = 2500000, fragments = 1200,
    position = Vector3.new(-380, 75, 300),
    inventory = {
        { Name = "Combat", Type = "Melee", Count = 1 },
        { Name = "Ectoplasm", Type = "Material", Count = 40 },
    },
}

SIM.world(PROFILE)
SIM.tool("Combat", "Melee", { "Z", "X", "C" })
SIM.enableBoats()
Config.load({ Team = "Pirates", Hop = false, RedeemCodes = false })

-- Abilities: the game tags the character with the ability once bought
-- (the Kaitun reads CollectionService tags).
local collection = game:GetService("CollectionService")
SIM.on("BuyHaki", function(name)
    collection:AddTag(SIM.character(), name)
    SIM.note("server: bought " .. tostring(name))
    return 1
end)
SIM.on("KenTalk", function() collection:AddTag(SIM.character(), "Ken") return 1 end)

SIM.start()
Engine.start()
SIM.stuckAfter = 180
SIM.run({ seconds = 600 })

local status = Engine.status()
SIM.note("engine task: " .. tostring(status.task) .. " / idle: " .. tostring(status.idle))
for _, line in ipairs(status.log or {}) do SIM.note("engine log: " .. line) end
for _, line in ipairs(status.plan or {}) do SIM.note("plan: " .. line) end
Engine.stop()

local errors = 0
for _, line in ipairs(SIM.incidents) do
    if line:find("ERROR", 1, true) or line:find("WARN", 1, true) then errors = errors + 1 end
end
SIM.expect("no Lua error or warning from the loops", errors == 0, errors)
SIM.expect("the engine chose something", #SIM.timeline > 0)
SIM.finish("kaitun_profile")
