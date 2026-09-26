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

    local helpers = tab:AddSection("Farm helpers")
    Bind.toggle(helpers, "AutoClick", "Auto Click", "Hits whatever is within 80 studs when no farm is fighting.")
    Bind.toggle(helpers, "AutoKen", "Auto Observation", "Turns Ken (E) back on whenever it is off.")
    Bind.toggle(helpers, "AutoV3", "Auto Race V3", "Uses your race's V3 ability every 3 seconds.")
    Bind.toggle(helpers, "DodgeSkills", "Dodge Mob Skills", "Flies 200 studs up while the fought mob casts a skill.")
    Bind.toggle(helpers, "LowHpEscape", "Fly Up When Low HP", "Stays high above the fight until your health is over 80 %.")
    Bind.slider(helpers, "LowHpPercent", "Low HP %", 5, 90, 0)
    Bind.slider(helpers, "LowHpHeight", "Escape Height", 100, 5000, 0)
    Bind.toggle(helpers, "SafeWithItems", "Safe Spot With Fist / Chalice",
        "Waits at the Café (Sea 2) or the Mansion (Sea 3) while holding one, unless a feature on needs it.")

    local skills = tab:AddSection("Skills")
    skills:AddParagraph({ Title = "Which skills", Content = "Used by the mastery farm, the sea events, the trees and the trials." })
    Bind.multiDropdown(skills, "SkillsMelee", "Melee Skills", { "Z", "X", "C" })
    Bind.multiDropdown(skills, "SkillsSword", "Sword Skills", { "Z", "X" })
    Bind.multiDropdown(skills, "SkillsGun", "Gun Skills", { "Z", "X" })
    Bind.multiDropdown(skills, "SkillsFruit", "Blox Fruit Skills", { "Z", "X", "C", "V", "F" })
    Bind.slider(skills, "SkillHoldMelee", "Melee Hold Time", 0, 5, 1)
    Bind.slider(skills, "SkillHoldSword", "Sword Hold Time", 0, 5, 1)
    Bind.slider(skills, "SkillHoldGun", "Gun Hold Time", 0, 5, 1)
    Bind.slider(skills, "SkillHoldFruit", "Blox Fruit Hold Time", 0, 5, 1)
    Bind.toggle(skills, "SkillFast", "Use Skills Fast", "Taps the keys instead of holding them.")

    local movement = tab:AddSection("Movement")
    Bind.slider(movement, "TweenSpeed", "Fly Speed", 100, 350, 0,
        "Studs per second. Lower it if the server keeps pulling you back.")
    Bind.toggle(movement, "SmartTravel", "Smart travel (portals and shortcuts)",
        "Far goals: the unlocked portal nearest it (Rip Indra, Cursed Ship, Doflamingo, Temple of Time...), "
            .. "called Banana's way or Teddy's, or the reset teleport. Also the temple exit, the submarine, "
            .. "the Underwater City and Cursed Ship exits, the Cake mirror and the Celestial Domain.")
    Bind.toggle(movement, "PortalFruit", "Use Portal fruit (Gateway)",
        "Portal fruit level 200+: opens the Gateway to the island nearest the goal when C is ready.")
    Bind.slider(movement, "TeleportDistance", "Teleport when farther than", 1000, 5000, 0,
        "Studs. A farther goal is reached by a portal or the reset teleport, whichever arrives first; "
            .. "a closer one is flown to.")
    Bind.toggle(movement, "ResetTeleport", "Reset teleport (respawn near the goal)",
        "Moves your spawn point to the goal's island and resets your character. Never while you hold a "
            .. "Fist of Darkness, a Chalice, a Hallow Essence, a Microchip, a flower, the Red Key or an unstored "
            .. "fruit, nor in a raid, a dungeon or on the Submerged Island.")
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
