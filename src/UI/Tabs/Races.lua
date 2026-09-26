--=============================================================================
-- RACES TAB — V2 / V3, Cyborg, Ghoul, Draco, V4
--=============================================================================

local Bind = require("UI.Bind")
local Loop = require("Core.Loop")
local Pvp = require("Features.Pvp")
local RaceV4 = require("Features.Races.V4")

return function(Window)
    local tab = Window:AddTab({ Title = "Races", Icon = "dna" })

    local upgrade = tab:AddSection("Upgrade Race")
    Bind.toggle(upgrade, "RaceV2V3", "Auto Race V2 - V3",
        "Sea 2. V2: flowers (500k). V3 (2M): your race's quest (Fishman: a sea beast, by boat).")
    Bind.toggle(upgrade, "RaceDraco", "Auto Draco V2 - V3",
        "Dragon Wizard: Fire Flowers for V2, a Terrorshark at sea for V3.")
    Bind.toggle(upgrade, "AutoV3", "Auto Race V3", "Uses your race's V3 ability every 3 seconds.")

    local cyborg = tab:AddSection("Cyborg & Ghoul (Sea 2)")
    Bind.toggle(cyborg, "RaceCyborg", "Auto Cyborg", "Microchip (1000 fragments), Order, Core Brain, the trainer.")
    Bind.toggle(cyborg, "RaceCyborgFist", "Cyborg: Get A Fist Of Darkness First", "Collects chests until one drops.")
    Bind.toggle(cyborg, "RaceCyborgHop", "Cyborg: Hop After 20 Chests")
    Bind.toggle(cyborg, "RaceGhoul", "Auto Ghoul", "100 Ectoplasm, the Cursed Captain's Hellfire Torch, the trade.")
    Bind.toggle(cyborg, "RaceGhoulHop", "Ghoul: Hop For The Cursed Captain")

    local v4 = tab:AddSection("Race V4")
    local status = v4:AddParagraph({ Title = "Ancient One", Content = "?" })
    Bind.toggle(v4, "RaceTurnOnV4", "Auto Turn On V4", "When the energy bar is full.")
    Bind.toggle(v4, "RaceBuyGear", "Auto Buy Gear")
    Bind.dropdown(v4, "RaceGearType", "Gear Type", RaceV4.GEAR_TYPES)
    Bind.toggle(v4, "RaceChooseGear", "Auto Choose Gears", "Spends the temple points.")
    Bind.toggle(v4, "RaceTrain", "Auto Finish Train Quest", "V4 on, bone mobs, until the Ancient One is happy.")
    Bind.toggle(v4, "RaceTeleportClock", "Stay At The Ancient Clock")
    Bind.toggle(v4, "RaceNoFog", "No Fog")

    local lever = tab:AddSection("Pull Lever & Trial")
    Bind.toggle(lever, "RacePullLever", "Auto Pull Lever",
        "Valkyrie Helm + Mirror Fractal: the Mirage blue gear at night, then the lever.")
    Bind.toggle(lever, "RaceTrial", "Auto Trial", "Goes to your race door; finishes the trial inside.")
    Bind.toggle(lever, "RaceFindMirage", "Sail To Find A Mirage", "No Mirage: drives your boat out to sea until one spawns.")
    Bind.toggle(lever, "RaceHop", "Hop For Mirage / Full Moon")
    Bind.toggle(lever, "RaceV3AtDoor", "Press T When 2 Players Are At Their Doors")
    Bind.toggle(lever, "RaceTrainFirst", "Train Before Trials", "The trial waits while the Ancient One asks for training.")
    Bind.toggle(lever, "RaceKillPlayers", "Kill Players After The Trial")
    Bind.dropdown(lever, "RaceTrialWeapon", "Weapon For Players", { "Melee", "Sword", "Blox Fruit", "Gun" })
    Bind.toggle(lever, "RaceTrialSkills", "Use Skills On Players")
    Bind.toggle(lever, "RaceTrialKenOnly", "Skills Only When They Use Ken")
    Bind.toggle(lever, "RaceResetCharacter", "Reset When The Free-For-All Starts")
    Bind.toggle(lever, "RaceDracoTrial", "Auto Draco Trial Of Flames",
        "Crafts a Volcanic Magnet and finds a Prehistoric Island first if needed.")

    local multi = tab:AddSection("Multi Trial (accounts in this server)")
    local accounts = Bind.multiDropdown(multi, "RaceMultiAccounts", "Accounts", Pvp.playerNames())
    multi:AddButton({ Title = "Refresh accounts", Callback = function() accounts:SetValues(Pvp.playerNames()) end })
    Bind.toggle(multi, "RaceMultiTrial", "Multi Trial", "Presses T once 2 selected accounts stand at their doors.")

    Loop.start("RacePanel", 3, function()
        local ok, text = pcall(RaceV4.status)
        status:SetDesc(ok and text or "?")
    end)

    return tab
end
