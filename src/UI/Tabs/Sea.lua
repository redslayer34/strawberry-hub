--=============================================================================
-- SEA EVENTS TAB — boat, sea events, Mirage, Kitsune, Leviathan, volcano
--=============================================================================

local Bind = require("UI.Bind")
local Boat = require("Game.Boat")
local Loop = require("Core.Loop")
local Pvp = require("Features.Pvp")
local SeaEvents = require("Features.Sea.Events")
local SeaIslands = require("Features.Sea.Islands")
local Settings = require("Core.Settings")

return function(Window)
    local tab = Window:AddTab({ Title = "Sea Events", Icon = "anchor" })

    local setup = tab:AddSection("Boat & Settings")
    Bind.dropdown(setup, "SeaBoat", "Boat", Boat.NAMES, "Bought at the dealer when you have none.")
    Bind.slider(setup, "SeaBoatSpeed", "Boat Speed", 50, 500, 0, "Lowered by itself when the server pulls the boat back.")
    Bind.dropdown(setup, "SeaZone", "Zone (Sea 3)", Boat.ZONE_NAMES, "Zone 1 is the calmest, Zone 6 the most dangerous.")
    Bind.multiDropdown(setup, "SeaSkillWeapons", "Weapons For Skills", { "Blox Fruit", "Melee", "Sword", "Gun" },
        "Sea beasts, ships, the Leviathan and the volcano rocks are hit with skills.")
    Bind.toggle(setup, "SeaRepair", "Auto Repair Your Boat", "Shipwright hammer, when the boat is damaged.")
    Bind.toggle(setup, "SeaBoatMaxSpeed", "Change Boat Speed", "Raises your boat's own max speed.")
    Bind.slider(setup, "SeaBoatMaxValue", "Boat Max Speed", 50, 500, 0)
    Bind.toggle(setup, "SeaResetForBoat", "Reset To Buy The Boat",
        "Far from Tiki Outpost with your spawn there: resets instead of flying back.")

    local events = tab:AddSection("Sea Events")
    Bind.multiDropdown(events, "SeaEventKinds", "Sea Events To Farm", SeaEvents.KINDS)
    Bind.toggle(events, "SeaBrigadeOnly", "Ships: Only Brigades")
    Bind.toggle(events, "SeaSailOut", "Keep Sailing Until An Event", "Sails out to sea instead of waiting at the zone.")
    Bind.toggle(events, "SeaRoughSea", "Avoid Rough Seas", "Moves the zone 7000 studs when a rough sea is met in the rain.")
    Bind.toggle(events, "SeaDodgeTerrorshark", "Dodge The Terrorshark", "Flies up during its charge.")
    Bind.toggle(events, "SeaDodgeSeaBeast", "Dodge Sea Beast Beams", "Flies high while a sea beast fires its beam.")
    local friends = Bind.dropdown(events, "SeaFriendName", "Friend", Pvp.playerNames())
    events:AddButton({ Title = "Refresh players", Callback = function() friends:SetValues(Pvp.playerNames()) end })
    Bind.toggle(events, "SeaFriend", "Sea Event With A Friend", "Stays with your friend, who drives the boat.")
    Bind.toggle(events, "SeaAuto", "Auto Sea Event", "Sails to the zone and fights every selected event.")
    Bind.toggle(events, "SeaDestroyIdk", "Auto Destroy IDK", "Clears the sea events while the spy says 'I don't know'.")

    local islands = tab:AddSection("Mirage & Kitsune")
    Bind.toggle(islands, "SeaFindMirage", "Auto Find Mirage", "Drives out to sea until a Mirage Island spawns.")
    Bind.toggle(islands, "SeaKitsuneSpawn", "Auto Spawn Kitsune Island", "Waits at Zone 6 on a full moon night.")
    Bind.toggle(islands, "SeaKitsuneHop", "Hop Until A Full Moon Is Near")
    Bind.toggle(islands, "SeaKitsuneTeleport", "Teleport To Kitsune Island")
    Bind.toggle(islands, "SeaKitsuneSummon", "Auto Touch The Shrine")
    Bind.toggle(islands, "SeaKitsuneEmbers", "Auto Collect Azure Embers")
    Bind.slider(islands, "SeaAzureEmbers", "Azure Embers To Trade", 1, 25, 0)
    Bind.toggle(islands, "SeaKitsuneTrade", "Auto Trade Azure Embers", "Prays at the statue during the event.")

    local leviathan = tab:AddSection("Leviathan")
    local status = leviathan:AddParagraph({ Title = "Spy", Content = "?" })
    Bind.toggle(leviathan, "SeaBuySpy", "Auto Buy Spy")
    Bind.toggle(leviathan, "SeaBuyBeastHunter", "Buy A Beast Hunter To Find It")
    Bind.toggle(leviathan, "SeaFindLeviathan", "Auto Find Leviathan", "Drives out to sea until the Frozen Dimension spawns.")
    local owners = Bind.dropdown(leviathan, "SeaLeviathanOwner", "Finder Account (Multi)", Pvp.playerNames())
    Bind.toggle(leviathan, "SeaMultiLeviathan", "Multi Find: Ride Its Cannons")
    Bind.toggle(leviathan, "SeaFrozenTeleport", "Teleport To The Frozen Dimension")
    Bind.toggle(leviathan, "SeaLeviathanStart", "Auto Start Leviathan", "Opens the gate at the Frozen Watcher.")
    Bind.toggle(leviathan, "SeaLeviathanAttack", "Auto Attack Leviathan", "Tail, head, then segments, with skills.")
    local heartOwners = Bind.dropdown(leviathan, "SeaHeartOwner", "Harpoon Boat Owner (empty = yours)", Pvp.playerNames())
    Bind.toggle(leviathan, "SeaLeviathanHeart", "Auto Harpoon The Frozen Heart")
    leviathan:AddButton({
        Title = "Refresh accounts",
        Callback = function()
            owners:SetValues(Pvp.playerNames())
            heartOwners:SetValues(Pvp.playerNames())
        end,
    })

    local volcano = tab:AddSection("Volcano (Prehistoric Island)")
    Bind.dropdown(volcano, "VolcanoGolemWeapon", "Weapon For Golems", { "Melee", "Sword", "Blox Fruit" })
    Bind.toggle(volcano, "VolcanoMagnet", "Auto Craft Volcanic Magnet", "10 Scrap Metal + 15 Blaze Ember.")
    Bind.toggle(volcano, "VolcanoFind", "Auto Find Prehistoric Island")
    Bind.toggle(volcano, "VolcanoEvent", "Auto Prehistoric Event", "Starts it, kills the golems, plugs the rocks.")
    Bind.toggle(volcano, "VolcanoEggs", "Auto Collect Dragon Eggs")
    Bind.toggle(volcano, "VolcanoBones", "Auto Collect Dino Bones")
    Bind.toggle(volcano, "VolcanoSkipMagnet", "Fully: Skip The Magnet")
    Bind.toggle(volcano, "VolcanoSkipBones", "Fully: Skip The Bones")
    Bind.toggle(volcano, "VolcanoFully", "Fully Prehistoric Island", "Magnet, find, event, eggs, bones, reset.")

    local drive = tab:AddSection("Drive")
    Bind.toggle(drive, "SeaDriveTiki", "Drive Boat To Tiki Outpost")
    Bind.toggle(drive, "SeaDriveHydra", "Drive Boat To Hydra Island")

    Loop.start("SeaPanel", 5, function()
        if not Settings.get("SeaBuySpy") and not Settings.get("SeaFindLeviathan") then return end
        local ok, text = pcall(SeaIslands.leviathanStatus)
        status:SetDesc(ok and text or "?")
    end)

    return tab
end
