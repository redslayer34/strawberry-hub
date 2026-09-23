--=============================================================================
-- STACK: ELITE HUNTER — Sea 3 elites (Deandre, Urban, Diablo)
--=============================================================================
--  The elite only counts with its quest, so the quest is asked first: when
--  the quest panel does not name the elite, the current quest is abandoned
--  and EliteHunter asked. Also used by Dough King's summon, which needs the
--  God's Chalice an elite drops.
--=============================================================================

local Common = require("Features.Stack.Common")
local Data = require("Game.Data")
local Enemies = require("Game.Enemies")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local EliteHunter = { name = "Elite Hunter" }

EliteHunter.ASK_EVERY = 3
EliteHunter.MAX_ASKS = 3   -- after this many asks, fight anyway (the title may not read)

local asked = {}

function EliteHunter.find()
    return Enemies.findBoss(Data.ELITE_HUNTERS)
end

local function questTitle()
    local player = Services.player()
    local quest = player and Services.find(player, "PlayerGui.Main.Quest")
    if not quest or not quest.Visible then return "" end
    local title = Services.find(quest, "Container.QuestTitle.Title")
    return title and tostring(title.Text) or ""
end

-- Takes the elite's quest if needed, then fights it. Returns the status.
function EliteHunter.run(mode, elite, inWorld)
    local hasQuest = questTitle():find(elite.Name, 1, true) ~= nil
    if not hasQuest and (asked[elite] or 0) < EliteHunter.MAX_ASKS then
        mode.target = nil
        if Common.every("EliteHunterQuest", EliteHunter.ASK_EVERY) then
            asked[elite] = (asked[elite] or 0) + 1
            Services.invoke("AbandonQuest")
            Services.invoke("EliteHunter")
        end
        return "Taking the quest for " .. elite.Name
    end
    return Common.fight(mode, elite, inWorld)
end

function EliteHunter.enabled()
    return Settings.get("StackEliteHunter") == true and Player.sea() == 3
end

function EliteHunter.want()
    return EliteHunter.find() ~= nil
end

function EliteHunter.tick(mode)
    local elite, inWorld = EliteHunter.find()
    if not elite then return "No elite" end
    return EliteHunter.run(mode, elite, inWorld)
end

-- No elite on this server: hop, unless a God's Chalice is held (the
-- reference then keeps it on this server).
function EliteHunter.hop()
    if Settings.get("StackHopElite") and not Common.has("God's Chalice") and not EliteHunter.find() then
        return "no Elite Hunter"
    end
    return nil
end

function EliteHunter.reset()
    asked = {}
end

return EliteHunter
