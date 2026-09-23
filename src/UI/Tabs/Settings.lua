--=============================================================================
-- SETTINGS TAB — hub options, then Fluent's own theme and config sections
--=============================================================================

local Bind = require("UI.Bind")
local Loop = require("Core.Loop")
local Router = require("Game.Router")

return function(Window, ui)
    local tab = Window:AddTab({ Title = "Settings", Icon = "settings" })

    local combat = tab:AddSection("Combat")
    Bind.slider(combat, "AttackDelay", "Attack Delay", 0, 0.5, 2,
        "Seconds between two attacks. 0 = every frame.")

    local movement = tab:AddSection("Movement")
    Bind.slider(movement, "TweenSpeed", "Fly Speed", 100, 350, 0,
        "Studs per second. Lower it if the server keeps pulling you back.")
    Bind.toggle(movement, "SmartTravel", "Smart travel (Banana Cat Hub portals)",
        "Goal 3000+ studs away: requestEntrance to the unlocked portal nearest it (Rip Indra, Cursed Ship, "
            .. "Doflamingo, Temple of Time...). Also the temple exit, the submarine, the Cake mirror and the "
            .. "Celestial Domain.")
    Bind.toggle(movement, "PortalFruit", "Use Portal fruit (Gateway)",
        "Portal fruit level 200+: opens the Gateway to the island nearest the goal when C is ready.")
    Bind.toggle(movement, "RespawnShortcut", "Reset teleport (respawn near the goal)",
        "Moves your spawn point to the goal's island and resets. Kills your character -- off by default.")
    Bind.toggle(movement, "LoadIslands", "Load every island",
        "Keeps every island loaded, like Banana Cat Hub. Uses more memory: turn it off if the game lags.")
    local portals = movement:AddParagraph({ Title = "Portals in this server", Content = Router.describe() })
    Loop.start("PortalPanel", 2, function() portals:SetDesc(Router.describe()) end)

    local screen = tab:AddSection("Screen & Performance")
    Bind.toggle(screen, "ScreenWhite", "White Screen", "Stops drawing the 3D world: less heat, less battery.")
    Bind.toggle(screen, "ScreenBlack", "Black Screen", "Same, with a black screen on top.")
    Bind.toggle(screen, "ScreenBoostFps", "Boost FPS",
        "Plain materials, no effects. Rejoin to get the normal look back.")
    Bind.toggle(screen, "ScreenNoNotifications", "Remove Game Notifications")
    Bind.toggle(screen, "ScreenAutoRejoin", "Auto Rejoin On Disconnect",
        "Rejoins the game when Roblox shows a disconnection message.")

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
