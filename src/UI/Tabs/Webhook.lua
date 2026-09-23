--=============================================================================
-- WEBHOOK TAB
--=============================================================================

local Bind = require("UI.Bind")
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
    reports:AddParagraph({
        Title = "More reports",
        Content = "Stored fruits, Prehistoric Island, Leviathan and Mirage reports come with their features.",
    })
    return tab
end
