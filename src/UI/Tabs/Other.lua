--=============================================================================
-- FARM OTHER TAB — the reference's "Farming Other" page
--=============================================================================

local Bind = require("UI.Bind")
local Dragon = require("Features.Other.Dragon")
local Farm = require("Features.Farm")
local Fishing = require("Features.Other.Fishing")
local Loop = require("Core.Loop")

return function(Window, ui)
    local tab = Window:AddTab({ Title = "Farm Other", Icon = "list" })

    local status = tab:AddSection("Status")
    status:AddParagraph({
        Title = "One farm at a time",
        Content = "These run like the farms of the Farm tab: the first one on wins "
            .. "(Law > Observation V2 > Observation > Dojo > Dragon Hunter > Berries > Chests > "
            .. "Fishing), Stack events still come first, and when one has nothing to do "
            .. "the next farm runs.",
    })
    local panel = status:AddParagraph({ Title = "Now", Content = Farm.status() })
    Loop.start("OtherPanel", 1, function()
        panel:SetDesc(Farm.status() .. "\n" .. Dragon.describe())
    end)

    local chests = tab:AddSection("Chests")
    Bind.toggle(chests, "OtherChest", "Auto Chest", "Collects every chest, touring the spawns to find more.")
    Bind.toggle(chests, "OtherChestHop", "Hop After Chests")
    Bind.slider(chests, "OtherChestHopAfter", "Chests Before Hop", 1, 100, 0)
    Bind.toggle(chests, "OtherChestTeleport", "Teleport To Chests (risk)",
        "Instant instead of flying. Faster, but the anti-cheat may kick you.")
    Bind.slider(chests, "ChestResetEvery", "Reset Every N Chests (teleport)", 0, 20, 0,
        "With Teleport To Chests: resets your character after this many chests or 10 s, like Teddy Hub, to "
            .. "shed the anti-cheat. 0 = never. Skipped while you hold a Fist, a Chalice or another item lost on death.")

    local berries = tab:AddSection("Berries")
    Bind.toggle(berries, "OtherBerry", "Auto Collect Berries")
    Bind.toggle(berries, "OtherHopBerry", "Hop To Find Berries")

    local law = tab:AddSection("Raid Law")
    Bind.toggle(law, "OtherLaw", "Auto Buy Chip And Kill Law",
        "Sea 2: buys a Microchip (1000 fragments), summons Order and kills it.")

    local observation = tab:AddSection("Observation (Ken)")
    Bind.toggle(observation, "OtherObservation", "Farm Observation",
        "Turns Ken on next to a strong Marine and lets it miss you.")
    Bind.toggle(observation, "OtherObservationHop", "Hop When Ken Is Down")
    Bind.toggle(observation, "OtherObservationV2", "Auto Observation V2",
        "Sea 3 citizen questline, up to buying the upgrade (5M Beli + 3 fruits).")

    local dragon = tab:AddSection("Dragon Quests (Sea 3)")
    Bind.toggle(dragon, "OtherDojo", "Auto Dojo Trainer",
        "Every belt. Yellow, Green and Red use your boat (Sea Events tab settings).")
    Bind.toggle(dragon, "OtherDragonHunter", "Auto Dragon Hunter",
        "Hydra Enforcers, Venomous Assailants, trees, embers.")

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
