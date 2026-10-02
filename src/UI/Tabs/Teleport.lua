--=============================================================================
-- TELEPORT TAB — islands, NPCs, travel (portals, reset teleport), seas
--=============================================================================

local Bind = require("UI.Bind")
local Data = require("Game.Data")
local Loop = require("Core.Loop")
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

    local travel = tab:AddSection("Travel")
    Bind.slider(travel, "TweenSpeed", "Fly Speed", 100, 350, 0,
        "Studs per second. Lower it if the server keeps pulling you back.")
    Bind.toggle(travel, "SmartTravel", "Smart travel (portals and shortcuts)",
        "Far goals: the game's portal doors (flies to the door, stands on it until it sends you on), "
            .. "or the reset teleport, whichever arrives first. Castle <-> Mansion / Hydra need the Valkyrie "
            .. "Helm, Castle <-> Tiki the Feathered Visage. Also the Temple of Time, the submarine, the Cake "
            .. "mirror and the Celestial Domain.")
    Bind.toggle(travel, "PortalFruit", "Use Portal fruit (Gateway)",
        "Portal fruit level 200+: opens the Gateway to the island nearest the goal when C is ready.")
    Bind.slider(travel, "TeleportDistance", "Teleport when farther than", 1000, 5000, 0,
        "Studs. A farther goal is reached through portal doors or the reset teleport, whichever arrives first; "
            .. "a closer one is flown to.")
    Bind.toggle(travel, "ResetTeleport", "Reset teleport (respawn near the goal)",
        "Moves your spawn point to the goal's island and resets your character. Never while you hold a "
            .. "Fist of Darkness, a Chalice, a Hallow Essence, a Microchip, a flower, the Red Key or an unstored "
            .. "fruit, nor in a raid, a dungeon or on the Submerged Island.")
    Bind.toggle(travel, "LoadIslands", "Load every island",
        "Keeps every island loaded, like Banana Cat Hub. Uses more memory. Off, only the place a farm is "
            .. "looking for mobs in is loaded, when it finds none (enough on low graphics).")
    local portals = travel:AddParagraph({ Title = "Portal doors in this sea", Content = Router.describe() })
    local log = travel:AddParagraph({ Title = "Travel log", Content = Router.logText() })
    Loop.start("PortalPanel", 2, function()
        portals:SetDesc(Router.describe())
        log:SetDesc(Router.logText())
    end)
    travel:AddButton({
        Title = "Copy travel log",
        Description = "Copies the last far trips (plan, doors and their answers, resets) to paste them elsewhere.",
        Callback = function()
            local copy = setclipboard or toclipboard or (syn and syn.write_clipboard)
            local ok = copy ~= nil and pcall(copy, Router.logText())
            ui.Library:Notify({ Title = "Travel log", Content = ok and "Copied" or "Your executor cannot copy", Duration = 4 })
        end,
    })

    travel:AddButton({
        Title = "Show route",
        Description = "For the island chosen above: the doors, reset or flight the hub would take from here. "
            .. "Nothing moves.",
        Callback = function()
            local name = Settings.get("Island")
            local position = World.islands()[name]
            if not position then
                ui.Library:Notify({ Title = "Route", Content = "Choose an island first", Duration = 5 })
                return
            end
            ui.Library:Notify({ Title = "Route to " .. tostring(name), Content = Router.routeText(position), Duration = 12 })
        end,
    })

    travel:AddButton({ Title = "Stop travelling", Callback = Travel.cancel })

    travel:AddButton({
        Title = "Clear portal pauses",
        Description = "Forgets the doors' pauses, so they are tried again at once.",
        Callback = function()
            Router.clearPauses()
            portals:SetDesc(Router.describe())
            ui.Library:Notify({ Title = "Portals", Content = "Pauses cleared", Duration = 4 })
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
