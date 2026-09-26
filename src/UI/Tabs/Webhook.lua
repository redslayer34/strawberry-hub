--=============================================================================
-- WEBHOOK TAB
--=============================================================================

local Bind = require("UI.Bind")
local Scout = require("Features.Scout")
local Webhook = require("Features.Webhook")

return function(Window, ui)
    local tab = Window:AddTab({ Title = "Webhook", Icon = "bell" })

    local setup = tab:AddSection("Discord")
    Bind.input(setup, "WebhookUrl", "Webhook URL", "https://discord.com/api/webhooks/...")
    Bind.input(setup, "WebhookPingId", "Ping ID", "Your Discord ID (empty = @everyone)")
    Bind.toggle(setup, "WebhookPing", "Ping")
    setup:AddButton({
        Title = "Test webhook",
        Callback = function()
            local sent = Webhook.send("Test", "Strawberry Hub is connected")
            ui.Library:Notify({
                Title = "Webhook",
                Content = sent and "Test sent" or "Not sent: check the URL (and that your executor can post)",
                Duration = 5,
            })
        end,
    })

    local reports = tab:AddSection("Reports")
    Bind.toggle(reports, "WebhookProfile", "Send Profile Every 5 Minutes",
        "Level, race, fruit, melees, valuable fruits and rare items.")
    Bind.toggle(reports, "WebhookStoreFruit", "Report Stored Fruits", "Needs Auto Store Fruit (Fruit & Raid tab).")
    Bind.multiDropdown(reports, "WebhookFruitRarities", "Fruit Rarities To Report",
        { "Mythical", "Legendary", "Rare", "Uncommon", "Common" })
    Bind.toggle(reports, "WebhookMirage", "Report Mirage Island")
    Bind.toggle(reports, "WebhookPrehistoric", "Report Prehistoric Island")
    Bind.toggle(reports, "WebhookLeviathan", "Report Frozen Dimension (Leviathan)")
    Bind.toggle(reports, "WebhookIdk", "Report Destroy IDK Done")

    local scout = tab:AddSection("Server scout")
    Bind.toggle(scout, "WebhookScout", "Server Scout",
        "Every 30 s, sends to your webhook above what this server has, once each, with the JobId and a line "
            .. "to paste to join.")
    Bind.multiDropdown(scout, "WebhookScoutEvents", "Events To Report", Scout.EVENTS)
    return tab
end
