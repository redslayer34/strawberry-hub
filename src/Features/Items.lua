--=============================================================================
-- ITEMS — quick buys and the Shark Anchor craft (background loop)
--=============================================================================
--    Trade bones       Bones Buy 1 1 (the Death King's gacha)
--    Legendary sword   LegendarySwordDealer 2, with an optional hop while the
--                      dealer has nothing new
--    Haki colour       ColorsDealer 2, same optional hop
--    Shark Anchor      the three RF/Craft steps, as soon as the materials
--                      for the next one are there
--=============================================================================

local Common = require("Features.Stack.Common")
local Loop = require("Core.Loop")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Items = {}

Items.HOP_EVERY = 60   -- seconds between dealer hops

local dealerSince

local function owned(name)
    return Common.has(name) or Common.itemCount(name) > 0
end

local function enough(name, count)
    return Common.itemCount(name) >= count
end

-- The next Shark Anchor craft possible, or nil.
function Items.nextSharkCraft()
    if owned("Shark Anchor") or owned("Monster Magnet") then return nil end
    if not owned("Shark Tooth Necklace") and enough("Mutant Tooth", 1) and enough("Shark Tooth", 5) then
        return "ToothNecklace"
    end
    if not owned("Terror Jaw") and enough("Mutant Tooth", 2) and enough("Shark Tooth", 5)
        and enough("Terror Eyes", 1) and enough("Fool's Gold", 10) then
        return "TerrorJaw"
    end
    if owned("Shark Tooth Necklace") and owned("Terror Jaw") and enough("Terror Eyes", 2)
        and enough("Shark Tooth", 10) and enough("Electric Wing", 10) and enough("Fool's Gold", 20) then
        return "SharkAnchor"
    end
    return nil
end

function Items.step()
    if Settings.get("ItemTradeBones") and Common.every("TradeBones", 1) then
        Services.invoke("Bones", "Buy", 1, 1)
    end
    local dealerHop = Settings.get("ItemDealerHop")
    if Settings.get("ItemLegendarySword") and Common.every("LegendarySword", 2) then
        Services.invoke("LegendarySwordDealer", "2")
    end
    if Settings.get("ItemHakiColour") and Common.every("HakiColour", 2) then
        Services.invoke("ColorsDealer", "2")
    end
    if dealerHop and (Settings.get("ItemLegendarySword") or Settings.get("ItemHakiColour")) then
        -- The dealers restock per server: give this one a minute, then move on.
        dealerSince = dealerSince or os.clock()
        if os.clock() - dealerSince >= Items.HOP_EVERY and Common.hop("dealers", true) then
            dealerSince = nil
        end
    else
        dealerSince = nil
    end
    if Settings.get("ItemSharkAnchor") and Common.every("SharkCraft", 3) then
        local craft = Items.nextSharkCraft()
        if craft then
            Common.netInvoke("RF/Craft", "Craft", craft, 1, {})
            Common.forget()
        end
    end
end

-- Test hook.
function Items.reset()
    dealerSince = nil
end

function Items.start()
    Loop.start("Items", 0.5, Items.step)
end

return Items
