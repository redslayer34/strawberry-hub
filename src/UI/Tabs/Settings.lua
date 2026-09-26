--=============================================================================
-- SETTINGS TAB — screen, hub options, then Fluent's own theme and config
--=============================================================================

local Bind = require("UI.Bind")

return function(Window, ui)
    local tab = Window:AddTab({ Title = "Settings", Icon = "settings" })

    local screen = tab:AddSection("Screen & Performance")
    Bind.toggle(screen, "ScreenWhite", "White Screen", "Stops drawing the 3D world: less heat, less battery.")
    Bind.toggle(screen, "ScreenBlack", "Black Screen", "Same, with a black screen on top.")
    Bind.toggle(screen, "ScreenBoostFps", "Boost FPS",
        "Plain materials, no effects. Rejoin to get the normal look back.")
    Bind.toggle(screen, "ScreenNoNotifications", "Remove Game Notifications")

    local hub = tab:AddSection("Hub")
    hub:AddParagraph({
        Title = "Saving",
        Content = "Every change is saved to the \"autosave\" config and loaded on the next run. "
            .. "Reload after teleport (Server tab) re-runs the hub after a hop. "
            .. "LeftControl (or the phone button) shows and hides this window.",
    })
    hub:AddButton({
        Title = "Copy Config",
        Description = "Copies your saved settings to the clipboard.",
        Callback = function()
            local _, message = require("Features.Screen").copyConfig()
            ui.Library:Notify({ Title = "Config", Content = message, Duration = 4 })
        end,
    })
    hub:AddButton({
        Title = "Unload",
        Description = "Stops every feature and closes the window.",
        Callback = function()
            Window:Dialog({
                Title = "Unload Strawberry Hub?",
                Content = "Every feature stops and the window closes.",
                Buttons = {
                    { Title = "Unload", Callback = function() ui.unload() end },
                    { Title = "Cancel" },
                },
            })
        end,
    })

    if ui.InterfaceManager then ui.InterfaceManager:BuildInterfaceSection(tab) end
    if ui.SaveManager then ui.SaveManager:BuildConfigSection(tab) end

    return tab
end
