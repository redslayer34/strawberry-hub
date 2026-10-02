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
    Bind.toggle(stats, "AutoStats", "Auto Stats", "Spends your stat points automatically (max 2800 per stat).")
    Bind.dropdown(stats, "StatMode", "Stat Mode", { "Teddy", "Even" },
        "Teddy: Melee first, Defense 15/100, then Melee and Defense to the max, Sword 600 and Demon Fruit "
            .. "1950 from level 400. Even: split over the stats below.")
    Bind.multiDropdown(stats, "StatTargets", "Stats (Even mode)", Data.STATS)

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
    Bind.toggle(movement, "PvpWaterWalk", "Walk On Water")

    return tab
end
