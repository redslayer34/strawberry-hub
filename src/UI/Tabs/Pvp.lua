--=============================================================================
-- PVP TAB
--=============================================================================

local Bind = require("UI.Bind")
local Pvp = require("Features.Pvp")

return function(Window)
    local tab = Window:AddTab({ Title = "PVP", Icon = "crosshair" })

    local target = tab:AddSection("Target")
    local list = Bind.dropdown(target, "PvpPlayer", "Player", Pvp.playerNames())
    target:AddButton({
        Title = "Refresh players",
        Callback = function() list:SetValues(Pvp.playerNames()) end,
    })
    Bind.dropdown(target, "PvpMethod", "Aim at", Pvp.METHODS)

    local actions = tab:AddSection("PVP")
    Bind.toggle(actions, "PvpFollow", "Teleport To Player", "Flies onto the target and stays on it.")
    Bind.toggle(actions, "PvpAimbot", "Skill Aimbot", "Every skill goes to the target.")
    Bind.toggle(actions, "PvpGunAimbot", "Gun Aimbot", "Gun shots go to the target.")

    local misc = tab:AddSection("Misc")
    Bind.toggle(misc, "PvpWaterWalk", "Walk On Water")
    misc:AddParagraph({ Title = "Speed and jump", Content = "Walk Speed and Jump Power are in the Player tab." })
    return tab
end
