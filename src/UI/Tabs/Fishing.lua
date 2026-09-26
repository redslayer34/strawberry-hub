--=============================================================================
-- FISHING TAB — the reference's fishing options (a farm of Farm Other)
--=============================================================================

local Bind = require("UI.Bind")
local Fishing = require("Features.Other.Fishing")

return function(Window)
    local tab = Window:AddTab({ Title = "Fishing", Icon = "fish" })

    local fishing = tab:AddSection("Fishing")
    local spot = fishing:AddParagraph({ Title = "Fishing spot", Content = Fishing.describeSpot() })
    fishing:AddButton({
        Title = "Save Fishing Position",
        Description = "Stand where you want to fish, facing the water.",
        Callback = function()
            local text = Fishing.saveSpot()
            if text then spot:SetDesc(text) end
        end,
    })
    Bind.dropdown(fishing, "OtherBait", "Bait", Fishing.baitNames(), "Crafted when you have none.")
    Bind.toggle(fishing, "OtherFishing", "Auto Fishing")
    Bind.toggle(fishing, "OtherFishingVortex", "Go To Golden Vortex", "Fishes at the event spot when there is one.")
    Bind.toggle(fishing, "OtherSellFish", "Auto Sell Fish")
    Bind.toggle(fishing, "OtherOpenChests", "Auto Open Fishing Chests")
    Bind.toggle(fishing, "OtherReelSize", "Bigger Reel Zone")
    Bind.multiDropdown(fishing, "OtherAnglerRarities", "Angler Quest Rarities", Fishing.rarityNames(),
        "Quests of other rarities are dropped. None selected = keep all.")
    Bind.toggle(fishing, "OtherAnglerQuest", "Auto Accept Angler Quests")
    Bind.toggle(fishing, "OtherSlapBattle", "Auto Slap Battle", "Times the jumps. It can still miss.")

    return tab
end
