--=============================================================================
-- FRUIT & RAID TAB — devil fruits, raids, multi raid, dungeon
--=============================================================================

local Bind = require("UI.Bind")
local Dungeon = require("Features.Dungeon")
local Fruits = require("Features.Fruits")
local Pvp = require("Features.Pvp")
local Raids = require("Features.Raids")

return function(Window)
    local tab = Window:AddTab({ Title = "Fruit & Raid", Icon = "cherry" })

    local fruit = tab:AddSection("Devil Fruit")
    Bind.toggle(fruit, "FruitRandom", "Random Devil Fruit", "Rolls the Cousin's gacha whenever it is allowed.")
    Bind.toggle(fruit, "FruitStore", "Auto Store Fruit", "Every fruit you hold goes to the fruit storage.")
    Bind.multiDropdown(fruit, "FruitSniperList", "Fruits To Snipe", Fruits.stockNames(),
        "Bought from the stock when on sale, unless you already eat one of them.")
    Bind.toggle(fruit, "FruitSniper", "Buy Sniped Fruits")
    Bind.toggle(fruit, "FruitAwaken", "Auto Awaken Fruit", "Asks the Awakener after each raid.")

    local raids = tab:AddSection("Raids")
    Bind.dropdown(raids, "RaidName", "Raid", Raids.names())
    Bind.toggle(raids, "RaidAuto", "Auto Raid", "Level 1100+: buys the chip, starts the raid and clears it.")
    Bind.toggle(raids, "RaidCheapFruit", "Pay With A Cheap Stored Fruit",
        "Takes a fruit worth under 1M from the storage to pay the chip.")
    Bind.toggle(raids, "RaidHopFruit", "Hop To Find A Fruit", "No fruit to pay with: picks one up or hops.")
    Bind.toggle(raids, "RaidInstantKill", "Instant Kill (risk)", "Kills raid mobs at once. The anti-cheat may notice.")
    Bind.slider(raids, "RaidKillDelay", "Instant Kill Delay", 0, 5, 0, "Seconds between two instant kills.")

    local law = tab:AddSection("Raid Law")
    Bind.toggle(law, "OtherLaw", "Auto Buy Chip And Kill Law",
        "Sea 2: buys a Microchip (1000 fragments), summons Order and kills it.")

    local multi = tab:AddSection("Multi Raid (accounts in this server)")
    multi:AddParagraph({
        Title = "How it works",
        Content = "Run the hub on every account in the same server. One account buys the chip and "
            .. "starts, the others take the slots. Select the other accounts on the buyer.",
    })
    local accounts = Bind.multiDropdown(multi, "MultiRaidAccounts", "Accounts", Pvp.playerNames())
    multi:AddButton({ Title = "Refresh accounts", Callback = function() accounts:SetValues(Pvp.playerNames()) end })
    Bind.toggle(multi, "MultiRaidBuyer", "This Account Buys The Chip And Starts")
    Bind.toggle(multi, "MultiRaidSlot", "This Account Takes A Slot")
    Bind.toggle(multi, "MultiRaid", "Auto Multi Raid")

    local join = tab:AddSection("Join Dungeon")
    Bind.toggle(join, "DungeonLeader", "This Account Starts The Dungeon",
        "Off: this account follows the leader chosen below.")
    local leader = Bind.dropdown(join, "DungeonLeaderName", "Leader Account", Pvp.playerNames())
    join:AddButton({ Title = "Refresh accounts", Callback = function() leader:SetValues(Pvp.playerNames()) end })
    Bind.slider(join, "DungeonMinPlayers", "Players Before Start", 0, 4, 0)
    Bind.dropdown(join, "DungeonDifficulty", "Difficulty", Dungeon.DIFFICULTIES)
    Bind.toggle(join, "DungeonJoin", "Auto Join Dungeon")

    local dungeon = tab:AddSection("Dungeon")
    Bind.dropdown(dungeon, "DungeonWeapon", "Weapon", Dungeon.WEAPONS)
    Bind.toggle(dungeon, "DungeonAttack", "Auto Attack Dungeon", "Clears each floor, then takes the exit.")
    local cards = Dungeon.cardNames()
    Bind.dropdown(dungeon, "DungeonCard1", "Card Priority 1", cards)
    Bind.dropdown(dungeon, "DungeonCard2", "Card Priority 2", cards)
    Bind.dropdown(dungeon, "DungeonCard3", "Card Priority 3", cards)
    Bind.toggle(dungeon, "DungeonCards", "Auto Pick Cards", "Your priorities first, otherwise a random card.")

    return tab
end
