--=============================================================================
-- DEMO — exemple complet et executable de la bibliotheque UI
--=============================================================================
--  Point d'entree alternatif du bundle :
--      python3 tools/pack.py --entry uidemo --bundle-only dist/StrawberryUI.lua
--
--  Tout ce qui suit est fonctionnel : les callbacks impriment reellement, les
--  composants gardent leur etat, et les references renvoyees permettent de
--  piloter l'interface depuis le reste du script.
--=============================================================================

local UI = require("UI")

local Window = UI:CreateWindow({
    Title = "Blox Fruits",
    Subtitle = "by strawberry",
    Size = UDim2.fromOffset(600, 400),
})

---------------------------------------------------------------------------
-- Farm
---------------------------------------------------------------------------

local Farm = Window:CreateTab({ Name = "Farm" })
local AutoFarm = Farm:CreateSection({ Name = "Auto Farm" })

local statusLabel

AutoFarm:CreateToggle({
    Name = "Auto Farm",
    Description = "Farm automatiquement les mobs de la quete active",
    Default = false,
    Callback = function(value)
        print("Auto Farm:", value)
        if statusLabel then
            statusLabel:SetText("Statut : " .. (value and "en cours" or "arrete"))
        end
        UI:Notify({
            Title = "Auto Farm",
            Content = value and "Farm demarre" or "Farm arrete",
            Duration = 3,
        })
    end,
})

AutoFarm:CreateDropdown({
    Name = "Farm Mode",
    Values = { "Level", "Mastery", "Boss", "Material" },
    Default = "Level",
    Callback = function(value) print("Mode:", value) end,
})

AutoFarm:CreateSlider({
    Name = "Distance",
    Min = 5,
    Max = 100,
    Default = 20,
    Rounding = 0,
    Callback = function(value) print("Distance:", value) end,
})

AutoFarm:CreateButton({
    Name = "Start Farm",
    Description = "Lance le cycle de farm immediatement",
    Arrow = true,
    Callback = function() print("Start") end,
})

local Status = Farm:CreateSection({ Name = "Status" })
statusLabel = Status:CreateLabel({ Name = "Statut : arrete" })

---------------------------------------------------------------------------
-- Teleport
---------------------------------------------------------------------------

local Teleport = Window:CreateTab({ Name = "Teleport" })
local Travel = Teleport:CreateSection({ Name = "Travel" })

Travel:CreateButton({
    Name = "Teleport to Sea 1",
    Description = "Main",
    Arrow = true,
    Callback = function() print("Sea 1") end,
})

Travel:CreateButton({
    Name = "Teleport to Sea 2",
    Description = "Dressrosa",
    Arrow = true,
    Callback = function() print("Sea 2") end,
})

Travel:CreateButton({
    Name = "Teleport to Sea 3",
    Description = "Zou",
    Arrow = true,
    Callback = function() print("Sea 3") end,
})

local Islands = Teleport:CreateSection({ Name = "Islands" })

local islandDropdown = Islands:CreateDropdown({
    Name = "Select Island",
    Values = {
        "Starter Island", "Jungle", "Pirate Village",
        "Desert", "Frozen Village", "Marine Fortress", "Skylands",
    },
    Default = "Starter Island",
    Callback = function(value) print("Island:", value) end,
})

Islands:CreateButton({
    Name = "Teleport to Island",
    Callback = function()
        print("Teleport ->", islandDropdown:GetValue())
    end,
})

---------------------------------------------------------------------------
-- Misc — montre SetTheme a chaud et le rafraichissement d'un dropdown
---------------------------------------------------------------------------

local Misc = Window:CreateTab({ Name = "Misc" })
local Interface = Misc:CreateSection({ Name = "Interface" })

Interface:CreateDropdown({
    Name = "Accent",
    Values = { "Rouge", "Bleu", "Vert", "Violet" },
    Default = "Rouge",
    Callback = function(value)
        local palettes = {
            Rouge  = Color3.fromRGB(196, 54, 54),
            Bleu   = Color3.fromRGB(66, 122, 210),
            Vert   = Color3.fromRGB(72, 172, 110),
            Violet = Color3.fromRGB(140, 96, 200),
        }
        -- Changement a chaud : rien n'est reconstruit, l'etat est conserve.
        UI:SetTheme({ Accent = palettes[value] })
    end,
})

Interface:CreateDivider()

Interface:CreateButton({
    Name = "Rafraichir la liste des iles",
    Description = "Demontre Dropdown:Refresh",
    Callback = function()
        islandDropdown:Refresh({ "Starter Island", "Jungle", "Desert" })
        UI:Notify({ Title = "Iles", Content = "Liste rafraichie", Duration = 2 })
    end,
})

Interface:CreateButton({
    Name = "Fermer l'interface",
    Arrow = true,
    Callback = function() Window:Hide() end,
})

UI:Notify({
    Title = "Strawberry UI",
    Content = "Interface chargee",
    Duration = 4,
})

return { UI = UI, Window = Window }
