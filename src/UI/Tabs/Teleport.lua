--=============================================================================
-- TELEPORT TAB — islands, NPCs, seas
--=============================================================================

local Bind = require("UI.Bind")
local Loop = require("Core.Loop")
local PortalRecorder = require("Game.PortalRecorder")
local Data = require("Game.Data")
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

    local control = tab:AddSection("Control")
    control:AddButton({ Title = "Stop travelling", Callback = Travel.cancel })
    control:AddButton({
        Title = "Test portals",
        Description = "Tries every portal of this sea once. Results in Settings > Portals.",
        Callback = function()
            local started = require("Game.Router").testAll(function()
                ui.Library:Notify({ Title = "Portals", Content = "Test finished",
                    SubContent = "See Settings > Movement > Portals", Duration = 6 })
            end)
            if not started then
                ui.Library:Notify({ Title = "Portals", Content = "A teleport is already running", Duration = 4 })
            end
        end,
    })

    local portals = tab:AddSection("Portals")
    portals:AddParagraph({
        Title = "How to teach a portal",
        Content = "Turn on Learn portals, stop the farm, then walk through the portal yourself once "
            .. "(Castle <-> Mansion, Castle <-> Hydra...). Smart travel uses it from then on. "
            .. "Then press Test portals far from them: the ones that work from anywhere skip the flight.",
    })
    Bind.toggle(portals, "LearnPortals", "Learn portals", "Watches you take portals and remembers them.")
    local learned = portals:AddParagraph({ Title = "Learned portals", Content = PortalRecorder.describe() })
    Loop.start("LearnedPanel", 2, function() learned:SetDesc(PortalRecorder.describe()) end)
    portals:AddButton({
        Title = "Copy log",
        Description = "Copies the learned portals and the game's last calls, to send them.",
        Callback = function()
            if setclipboard then
                setclipboard(PortalRecorder.log())
                ui.Library:Notify({ Title = "Portals", Content = "Log copied", Duration = 4 })
            else
                ui.Library:Notify({ Title = "Portals", Content = "Your executor cannot copy", Duration = 4 })
            end
        end,
    })
    portals:AddButton({
        Title = "Forget learned portals",
        Callback = function()
            Window:Dialog({
                Title = "Forget every learned portal?",
                Content = "You will have to walk through them again.",
                Buttons = { { Title = "Forget", Callback = PortalRecorder.forget }, { Title = "Cancel" } },
            })
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
