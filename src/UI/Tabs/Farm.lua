--=============================================================================
-- FARM TAB
--=============================================================================

local Bind = require("UI.Bind")
local Farm = require("Features.Farm")
local Loop = require("Core.Loop")
local Player = require("Core.Player")
local Quests = require("Game.Quests")
local Settings = require("Core.Settings")

local function statusText()
    local lines = {
        "Level " .. tostring(Player.level()) .. "  |  Sea " .. tostring(Player.sea() or "?"),
    }

    local quest = Quests.active() and Quests.target()
    if quest then
        local current, required = Quests.progress()
        local progress = current and (current .. "/" .. required) or ("x" .. tostring(quest.count))
        lines[#lines + 1] = "Quest: " .. quest.mob .. "  " .. progress
    else
        lines[#lines + 1] = "Quest: none"
    end

    lines[#lines + 1] = Farm.status()
    return table.concat(lines, "\n")
end

return function(Window)
    local tab = Window:AddTab({ Title = "Farm", Icon = "swords" })

    local level = tab:AddSection("Level Farm")
    Bind.toggle(level, "AutoFarmLevel", "Auto Farm Level",
        "Takes the best quest for your level and farms its mobs.")
    Bind.dropdown(level, "Weapon", "Weapon", Settings.WEAPONS,
        "Equipped automatically while farming.")
    Bind.toggle(level, "BringMob", "Bring Mob",
        "Gathers the quest's mobs on one spot.")
    Bind.slider(level, "BringCount", "Bring Count", 1, 5, 0,
        "How many mobs are gathered at once.")
    Bind.slider(level, "FarmHeight", "Farm Height", 5, 25, 0,
        "Studs above the mob. Too high and hits stop landing.")

    local status = tab:AddSection("Status")
    local panel = status:AddParagraph({ Title = "Status", Content = statusText() })
    Loop.start("StatusPanel", 0.5, function()
        panel:SetDesc(statusText())
    end)

    return tab
end
