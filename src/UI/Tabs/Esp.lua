--=============================================================================
-- ESP TAB
--=============================================================================

local Bind = require("UI.Bind")

return function(Window)
    local tab = Window:AddTab({ Title = "ESP", Icon = "eye" })
    local esp = tab:AddSection("ESP")
    Bind.toggle(esp, "EspFruit", "ESP Fruit", "Fruits on the ground, with their name and distance.")
    Bind.toggle(esp, "EspBerry", "ESP Berry")
    Bind.toggle(esp, "EspIsland", "ESP Island")
    Bind.toggle(esp, "EspPlayer", "ESP Player", "Level, health and distance. Green = your team.")
    return tab
end
