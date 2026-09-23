--=============================================================================
-- SETTINGS TAB — hub options, then Fluent's own theme and config sections
--=============================================================================

local Bind = require("UI.Bind")

return function(Window, ui)
    local tab = Window:AddTab({ Title = "Settings", Icon = "settings" })

    local combat = tab:AddSection("Combat")
    Bind.slider(combat, "AttackDelay", "Attack Delay", 0, 0.5, 2,
        "Seconds between two attacks. 0 = every frame.")

    local movement = tab:AddSection("Movement")
    Bind.slider(movement, "TweenSpeed", "Fly Speed", 100, 350, 0,
        "Studs per second. Lower it if the server keeps pulling you back.")

    local hub = tab:AddSection("Hub")
    hub:AddParagraph({
        Title = "Saving",
        Content = "Every change is saved to the \"autosave\" config and loaded on the next run.",
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
