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
        Title = "Portal test",
        Description = "Calls the portal nearest the chosen island from where you stand, three ways in turn: "
            .. "Banana Cat Hub's (5 s of calls), Teddy Hub's (placed on the point), then Teddy's position. "
            .. "Tells which one works; travel then uses it first.",
        Callback = function()
            local name = Settings.get("Island")
            local position = World.islands()[name]
            if not position then
                ui.Library:Notify({ Title = "Portal test", Content = "Choose an island first", Duration = 5 })
                return
            end
            local started, info = Router.portalTest(position, function(text)
                ui.Library:Notify({ Title = "Portal test", Content = text, Duration = 15 })
            end)
            ui.Library:Notify({
                Title = "Portal test",
                Content = started and ("Calling " .. info .. "... stay still") or ("Cannot test: " .. info),
                Duration = 6,
            })
        end,
    })

    local events = tab:AddSection("Event Islands")
    local function goToNpc(place, npc)
        return function()
            if not World.npcPosition(npc) then
                ui.Library:Notify({ Title = "Teleport", Content = "No " .. place .. " in this server", Duration = 5 })
                return
            end
            Travel.go(place, function() return World.npcPosition(npc) end)
        end
    end
    events:AddButton({ Title = "Go to Mirage Island", Description = "Its Advanced Fruit Dealer.",
        Callback = goToNpc("Mirage Island", "Advanced Fruit Dealer") })
    events:AddButton({ Title = "Go to Prehistoric Island", Description = "Its Fossil Expert.",
        Callback = goToNpc("Prehistoric Island", "Fossil Expert") })

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
