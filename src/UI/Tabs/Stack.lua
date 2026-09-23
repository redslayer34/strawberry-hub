--=============================================================================
-- STACK TAB — events that interrupt the main farm
--=============================================================================
--  Everything here runs on top of the farm chosen in the Farm tab: when an
--  event is up the character leaves the farm for it, then comes back.
--=============================================================================

local Bind = require("UI.Bind")
local Chests = require("Features.Stack.Chests")
local EliteHunter = require("Features.Stack.EliteHunter")
local Farm = require("Features.Farm")
local Loop = require("Core.Loop")
local Player = require("Core.Player")
local StackFarm = require("Features.StackFarm")
local Summons = require("Features.Stack.Summons")

local function statusText()
    local lines = {}
    local task = StackFarm.current()
    if task and Farm.current() == StackFarm then
        lines[#lines + 1] = StackFarm.status
    else
        lines[#lines + 1] = "No event running: " .. Farm.status()
    end
    if StackFarm.hopNote then lines[#lines + 1] = StackFarm.hopNote end
    lines[#lines + 1] = Chests.describe()
    if Player.sea() == 3 then
        local elite = EliteHunter.find()
        lines[#lines + 1] = "Elite Hunter: " .. (elite and elite.Name or "none")
    end
    return table.concat(lines, "\n")
end

return function(Window)
    local tab = Window:AddTab({ Title = "Stack", Icon = "layers" })

    local status = tab:AddSection("Status")
    status:AddParagraph({
        Title = "How it works",
        Content = "Turn on a farm in the Farm tab, then the events you want here. When one is up "
            .. "the character leaves the farm for it, then goes back to farming.",
    })
    local panel = status:AddParagraph({ Title = "Now", Content = statusText() })
    Loop.start("StackPanel", 1, function() panel:SetDesc(statusText()) end)

    local world = tab:AddSection("Auto World")
    Bind.toggle(world, "StackNewWorld", "Auto Second Sea",
        "Sea 1, level 700: detective's key, Ice door, Ice Admiral, then travels.")
    Bind.toggle(world, "StackThirdWorld", "Auto Third Sea",
        "Sea 2, level 1500: Bartilo, Trevor, Don Swan, rip_indra, then travels. "
            .. "Trevor takes a fruit worth 1M or more: it is given away.")

    local fruit = tab:AddSection("Devil Fruit")
    Bind.toggle(fruit, "StackChests", "Collect Chests On Chalice / Fist Spawn",
        "Every 4 hours: collects up to 10 chests when God's Chalice or Fist of Darkness spawns.")
    Bind.toggle(fruit, "StackFruit", "Teleport To Fruit", "Picks up fruits lying on the ground.")
    Bind.toggle(fruit, "StackHopFruit", "Hop To Find Fruit", "Changes server when there is no fruit on the ground.")

    local events = tab:AddSection("Events")
    Bind.toggle(events, "StackFactory", "Auto Factory", "Sea 2: kills the Core when the factory opens.")
    Bind.toggle(events, "StackPirateRaid", "Auto Pirate Raid", "Sea 3: defends the Castle on the Sea.")

    local indra = tab:AddSection("Rip Indra")
    Bind.toggle(indra, "StackEliteHunter", "Auto Elite Hunter", "Sea 3: takes the quest and kills the elite.")
    Bind.toggle(indra, "StackHopElite", "Hop To Find Elite Hunter",
        "Changes server when no elite is up (not while holding God's Chalice).")
    Bind.toggle(indra, "StackHakiPads", "Auto Haki Pads",
        "Lights the Castle summoner's pads with the haki colour each one asks for.")
    Bind.toggle(indra, "StackSummonRipIndra", "Auto Summon Rip Indra", "Brings God's Chalice to the summoner.")
    Bind.toggle(indra, "StackRipIndra", "Attack Rip Indra")
    local colours = indra:AddParagraph({ Title = "Haki colours", Content = "Checking..." })
    Loop.start("HakiColours", 30, function()
        if Player.sea() ~= 3 then
            colours:SetDesc("Sea 3 only")
            return
        end
        local missing = Summons.missingColours()
        colours:SetDesc(#missing == 0 and "All three unlocked"
            or ("Locked: " .. table.concat(missing, ", ") .. " (buy them from the Barista)"))
    end)

    local reaper = tab:AddSection("Soul Reaper")
    Bind.toggle(reaper, "StackSoulReaper", "Attack Soul Reaper")
    Bind.toggle(reaper, "StackSummonSoulReaper", "Summon Soul Reaper", "Uses a Hallow Essence (needs Attack on).")

    local dough = tab:AddSection("Dough King")
    Bind.toggle(dough, "StackDoughKing", "Attack Dough King")
    Bind.toggle(dough, "StackSummonDoughKing", "Summon Dough King",
        "Needs Attack on: farms Conjured Cocoa and a God's Chalice for the Sweet Chalice, then summons.")
    Bind.toggle(dough, "StackHopDoughKing", "Hop To Find Dough King")

    local darkbeard = tab:AddSection("Darkbeard")
    Bind.toggle(darkbeard, "StackDarkbeard", "Attack Darkbeard", "Sea 2.")
    Bind.toggle(darkbeard, "StackSummonDarkbeard", "Summon Darkbeard", "Uses a Fist of Darkness (needs Attack on).")
    Bind.toggle(darkbeard, "StackHopDarkbeard", "Hop To Find Darkbeard")

    return tab
end
