--=============================================================================
-- FARM OTHER TAB — the reference's "Farming Other" page
--=============================================================================

local Bind = require("UI.Bind")
local Dragon = require("Features.Other.Dragon")
local Farm = require("Features.Farm")
local Loop = require("Core.Loop")

return function(Window, ui)
    local tab = Window:AddTab({ Title = "Farm Other", Icon = "list" })

    local status = tab:AddSection("Status")
    status:AddParagraph({
        Title = "One farm at a time",
        Content = "These run like the farms of the Farm tab: the first one on wins "
            .. "(Law > Observation V2 > Observation > Dojo > Dragon Hunter > Berries > Chests > "
            .. "Fishing), Stack events still come first, and when one has nothing to do "
            .. "the next farm runs. Law is in the Fruit & Raid tab, Fishing has its own tab.",
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

    return tab
end
