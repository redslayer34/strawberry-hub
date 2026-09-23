--=============================================================================
-- ITEMS TAB — the reference's "Get and Upgrade Items" page
--=============================================================================

local Bind = require("UI.Bind")
local ItemMastery = require("Features.Items.Mastery")
local Loop = require("Core.Loop")

return function(Window)
    local tab = Window:AddTab({ Title = "Items", Icon = "sword" })

    local buys = tab:AddSection("Buy")
    Bind.toggle(buys, "ItemTradeBones", "Auto Trade Bones", "The Death King's gacha, with your bones.")
    Bind.toggle(buys, "ItemLegendarySword", "Auto Buy Legendary Sword")
    Bind.toggle(buys, "ItemHakiColour", "Auto Buy Haki Colour")
    Bind.toggle(buys, "ItemDealerHop", "Hop For The Dealers", "Changes server every minute while buying.")
    Bind.toggle(buys, "ItemSharkAnchor", "Auto Craft Shark Anchor", "Necklace, Terror Jaw, then the Anchor.")

    local swords = tab:AddSection("Swords & Haki (Sea 3)")
    swords:AddParagraph({
        Title = "Order",
        Content = "Like the farms, the first one on wins. When one waits for a boss or an elite, the next farm runs.",
    })
    Bind.toggle(swords, "ItemYama", "Auto Yama", "30 Elite Hunters, then the sealed katana.")
    Bind.toggle(swords, "ItemTushita", "Auto Tushita", "Needs rip_indra up: Holy Torch, 5 torches, Longma.")
    Bind.toggle(swords, "ItemTTK", "Auto True Triple Katana", "Oroshi, Saishi and Shizu to 300 mastery on bone mobs.")
    Bind.toggle(swords, "ItemRainbowHaki", "Auto Rainbow Haki", "The Horned Man's five boss quests.")
    Bind.toggle(swords, "ItemYoru", "Auto Yoru Mini", "Needs the 3 legendary haki colours: chalice, pads, rip_indra.")
    Bind.toggle(swords, "ItemYoruHop", "Yoru: Hop After Chests", "Uses the Chests Before Hop value of Farm Other.")

    local cdk = tab:AddSection("Cursed Dual Katana")
    Bind.toggle(cdk, "ItemCDK", "Auto CDK", "Needs Tushita and Yama at 350 mastery. Every trial, the pedestals, the boss.")
    Bind.toggle(cdk, "CdkHopRaid", "Hop When No Castle Raid", "Good trial 4: hops after 20 s without a raid.")
    Bind.toggle(cdk, "CdkHopCakeQueen", "Hop To Find Cake Queen", "Good trial 5.")

    local guitar = tab:AddSection("Soul Guitar")
    Bind.toggle(guitar, "ItemSoulGuitar", "Auto Soul Guitar",
        "Dark Fragment, 250 Ectoplasm, 500 Bones, 5000 fragments, then the puzzle.")
    Bind.toggle(guitar, "GuitarHopMoon", "Hop For A Full Moon Night")

    local saber = tab:AddSection("Saber (Sea 1)")
    Bind.toggle(saber, "ItemSaber", "Auto Saber", "Level 200: plates, torch, cup, Relic, Saber Expert.")

    local mastery = tab:AddSection("Mastery 600")
    Bind.toggle(mastery, "ItemMeleeMastery", "Auto Melee Mastery 600", "Buys each melee and farms it to 600.")
    Bind.toggle(mastery, "ItemSwordMastery", "Auto Sword Mastery 600", "Your rarest swords first.")

    local upgrade = tab:AddSection("Upgrade (Blacksmith)")
    Bind.toggle(upgrade, "ItemUpgradeSword", "Auto Upgrade Swords")
    Bind.toggle(upgrade, "ItemUpgradeGun", "Auto Upgrade Guns")
    local status = upgrade:AddParagraph({ Title = "Upgrade", Content = "Idle" })
    Loop.start("UpgradePanel", 1, function()
        local text = ItemMastery.upgradeStatus()
        status:SetDesc(text ~= "" and text or "Idle")
    end)

    return tab
end
