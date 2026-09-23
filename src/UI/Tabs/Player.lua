--=============================================================================
-- PLAYER TAB — auto stats, team, movement tweaks
--=============================================================================

local Bind = require("UI.Bind")
local Data = require("Game.Data")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

return function(Window, ui)
    local tab = Window:AddTab({ Title = "Player", Icon = "user" })

    local stats = tab:AddSection("Stats")
    Bind.toggle(stats, "AutoStats", "Auto Stats", "Spends your points evenly on the chosen stats (max 2800).")
    Bind.multiDropdown(stats, "StatTargets", "Stats", Data.STATS)

    local team = tab:AddSection("Team")
    Bind.dropdown(team, "Team", "Team", { "Pirates", "Marines" })
    team:AddButton({
        Title = "Switch team",
        Callback = function()
            local result = Services.invoke("SetTeam", Settings.get("Team"))
            ui.Library:Notify({ Title = "Team", Content = Settings.get("Team"),
                SubContent = result ~= nil and tostring(result) or nil, Duration = 4 })
        end,
    })

    local movement = tab:AddSection("Movement")
    Bind.toggle(movement, "WalkSpeedOn", "Custom Walk Speed")
    Bind.slider(movement, "WalkSpeed", "Walk Speed", 16, 300, 0)
    Bind.toggle(movement, "JumpPowerOn", "Custom Jump Power")
    Bind.slider(movement, "JumpPower", "Jump Power", 50, 300, 0)
    Bind.toggle(movement, "Noclip", "Noclip", "Walk through walls.")

    return tab
end
