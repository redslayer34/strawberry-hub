--=============================================================================
-- SHOP TAB — abilities, fighting styles, misc purchases
--=============================================================================

local Bind = require("UI.Bind")
local Data = require("Game.Data")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local Travel = require("Features.Travel")
local World = require("Game.World")

return function(Window, ui)
    local tab = Window:AddTab({ Title = "Shop", Icon = "shopping-cart" })

    local function notify(text, detail)
        ui.Library:Notify({ Title = "Shop", Content = text, SubContent = detail, Duration = 5 })
    end

    -- One CommF_ call, result shown to the player.
    local function buy(label, ...)
        local result = Services.invoke(...)
        notify(label, result ~= nil and tostring(result) or "No answer from the server")
    end

    local function confirm(title, text, action)
        Window:Dialog({
            Title = title,
            Content = text,
            Buttons = {
                { Title = "Confirm", Callback = action },
                { Title = "Cancel" },
            },
        })
    end

    local abilities = tab:AddSection("Abilities")
    abilities:AddButton({ Title = "Skyjump (Geppo)", Description = "$10,000",
        Callback = function() buy("Skyjump", "BuyHaki", "Geppo") end })
    abilities:AddButton({ Title = "Buso Haki", Description = "$25,000",
        Callback = function() buy("Buso Haki", "BuyHaki", "Buso") end })
    abilities:AddButton({ Title = "Soru", Description = "$100,000",
        Callback = function() buy("Soru", "BuyHaki", "Soru") end })
    abilities:AddButton({ Title = "Observation Haki", Description = "$750,000",
        Callback = function() buy("Observation Haki", "KenTalk", "Buy") end })

    local styles = tab:AddSection("Fighting Styles")
    Bind.dropdown(styles, "FightingStyle", "Fighting style", Data.fightingStyleNames(),
        "Flies to the teacher of the current sea and buys it there.")
    styles:AddButton({
        Title = "Buy fighting style",
        Callback = function()
            local style = Data.fightingStyle(Settings.get("FightingStyle"))
            if not style then return notify("Choose a fighting style first") end
            Travel.go(style.npc, function() return World.npcPosition(style.npc) end, function()
                local result
                for _, call in ipairs(style.calls) do
                    result = Services.invoke((table.unpack or unpack)(call))
                end
                notify(style.name, result ~= nil and tostring(result) or "No answer from the server")
            end)
        end,
    })

    local buys = tab:AddSection("Auto Buy")
    Bind.toggle(buys, "ItemTradeBones", "Auto Trade Bones", "The Death King's gacha, with your bones.")
    Bind.toggle(buys, "ItemLegendarySword", "Auto Buy Legendary Sword")
    Bind.toggle(buys, "ItemHakiColour", "Auto Buy Haki Colour")
    Bind.toggle(buys, "ItemDealerHop", "Hop For The Dealers", "Changes server every minute while buying.")

    local misc = tab:AddSection("Misc")
    misc:AddButton({ Title = "Buy Dual Flintlock",
        Callback = function() buy("Dual Flintlock", "BuyItem", "Dual Flintlock") end })
    misc:AddButton({ Title = "Buy Cyborg race",
        Callback = function() buy("Cyborg race", "CyborgTrainer", "Buy") end })
    misc:AddButton({ Title = "Buy Ghoul race", Callback = function()
        Services.invoke("Ectoplasm", "BuyCheck", 4)
        buy("Ghoul race", "Ectoplasm", "Change", 4)
    end })
    misc:AddButton({ Title = "Reroll race", Description = "Costs fragments.", Callback = function()
        confirm("Reroll your race?", "This spends fragments.", function()
            buy("Reroll race", "BlackbeardReward", "Reroll", "2")
        end)
    end })
    misc:AddButton({ Title = "Reset stats", Description = "Costs fragments.", Callback = function()
        confirm("Reset your stats?", "Every stat point is refunded, for fragments.", function()
            Services.invoke("BlackbeardReward", "Refund", "1")
            buy("Reset stats", "BlackbeardReward", "Refund", "2")
        end)
    end })
    misc:AddButton({ Title = "Redeem all codes", Callback = function()
        local remote = Services.find(Services.replicated(), "Remotes.Redeem")
        if not remote then return notify("Redeem remote not found") end
        task.spawn(function()
            for _, code in ipairs(Data.CODES) do
                pcall(remote.InvokeServer, remote, code)
            end
            notify("Codes", #Data.CODES .. " codes tried")
        end)
    end })

    return tab
end
