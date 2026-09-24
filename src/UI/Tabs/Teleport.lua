--=============================================================================
-- TELEPORT TAB — islands, NPCs, seas
--=============================================================================

local Bind = require("UI.Bind")
local Data = require("Game.Data")
local Router = require("Game.Router")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local Travel = require("Features.Travel")
local World = require("Game.World")

return function(Window, ui)
    local tab = Window:AddTab({ Title = "Teleport", Icon = "map-pin" })

    local islands = tab:AddSection("Islands")
    local islandList = Bind.dropdown(islands, "Island", "Island", World.islandNames())
    islands:AddButton({
        Title = "Go to island",
        Description = "Flies there. A running farm pauses until you arrive.",
        Callback = function()
            local name = Settings.get("Island")
            local position = World.islands()[name]
            if position then Travel.go(name, position) end
        end,
    })
    islands:AddButton({
        Title = "Refresh islands",
        Callback = function() islandList:SetValues(World.islandNames()) end,
    })

    local npcs = tab:AddSection("NPCs")
    local npcList = Bind.dropdown(npcs, "Npc", "NPC", World.npcNames())
    npcs:AddButton({
        Title = "Go to NPC",
        Callback = function()
            local name = Settings.get("Npc")
            if name ~= "" then
                Travel.go(name, function() return World.npcPosition(name) end)
            end
        end,
    })
    npcs:AddButton({
        Title = "Refresh NPCs",
        Callback = function() npcList:SetValues(World.npcNames()) end,
    })

    islands:AddButton({
        Title = "Banana portal test",
        Description = "Banana Cat Hub's exact portal code, from where you stand, to the portal nearest the "
            .. "chosen island: requestEntrance every 0.1 s for up to 15 s.",
        Callback = function()
            local name = Settings.get("Island")
            local position = World.islands()[name]
            if not position then
                ui.Library:Notify({ Title = "Banana portal test", Content = "Choose an island first", Duration = 5 })
                return
            end
            local started, info = Router.bananaTest(position, function(text)
                ui.Library:Notify({ Title = "Banana portal test", Content = text, Duration = 15 })
            end)
            ui.Library:Notify({
                Title = "Banana portal test",
                Content = started and ("Calling " .. info .. "... stay still") or ("Cannot test: " .. info),
                Duration = 6,
            })
        end,
    })

    local control = tab:AddSection("Control")
    control:AddButton({ Title = "Stop travelling", Callback = Travel.cancel })
    control:AddButton({
        Title = "Test portals",
        Description = "Tries every unlocked portal of this sea once, from where you are. Results in Settings > Movement.",
        Callback = function()
            local started = Router.testAll(function()
                ui.Library:Notify({ Title = "Portals", Content = "Test finished",
                    SubContent = "See Settings > Movement > Portals", Duration = 6 })
            end)
            if not started then
                ui.Library:Notify({ Title = "Portals", Content = "A teleport is already running", Duration = 4 })
            end
        end,
    })

    local seas = tab:AddSection("Seas")
    local labels = { "First Sea", "Second Sea", "Third Sea" }
    for sea, label in ipairs(labels) do
        seas:AddButton({
            Title = label,
            Callback = function()
                require("Game.Server").queueReload()
                Services.invoke(Data.TRAVEL[sea])
            end,
        })
    end

    return tab
end
