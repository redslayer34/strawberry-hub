--=============================================================================
-- MOB FARM — builds a farm mode that kills a list of mobs
--=============================================================================
--  Most modes are the same loop with a different mob list: fight the nearest
--  wanted mob, otherwise tour their spawn points. A spec only says what
--  differs:
--
--    name        shown in the status
--    key         the setting that enables the mode
--    sea         optional: the sea the mobs live in
--    mobs()      the mob names to farm (nil or empty: nothing to do)
--    before(m)   optional: runs first each tick; return true if it acted
--    idle        optional: status when the list is empty
--    quest       optional: { name, id, level } -- with "Take the farm's
--                quest" on, this quest is taken first (the reference's
--                "Auto Quest [Katakuri/Bone/Tyrant]")
--=============================================================================

local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Quests = require("Game.Quests")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local QUEST_REACHED = 8       -- studs from the giver to ask
local QUEST_EVERY = 0.5       -- seconds between two StartQuest

-- Takes `quest` when it should be taken now. Returns the status, or nil
-- when there is nothing to do.
local lastAsk = -math.huge
local function takeQuest(quest)
    if not Settings.get("FarmSpecialQuest") or Player.level() < quest.level or Quests.panelVisible() then
        return nil
    end
    local giver, name = Quests.giver(quest.name)
    if not giver then return nil end
    local spot = CFrame.new(giver) * CFrame.new(0, 4, 2)
    Movement.to(spot)
    if Player.distanceTo(giver) <= QUEST_REACHED and os.clock() - lastAsk >= QUEST_EVERY then
        lastAsk = os.clock()
        Services.invoke("StartQuest", quest.name, quest.id)
    end
    return "Taking the quest from " .. tostring(name or quest.name)
end

return function(spec)
    local mode = { name = spec.name, status = "Idle", target = nil }
    local search = Fight.newSearch()

    function mode.enabled()
        return Settings.get(spec.key) == true
    end

    function mode.tick()
        if not Player.alive() then
            mode.target = nil
            mode.status = "Waiting for respawn"
            return
        end

        if spec.sea and Player.sea() ~= spec.sea then
            mode.target = nil
            mode.status = "Only in Sea " .. spec.sea
            Movement.stop()
            return
        end

        if spec.quest then
            local status = takeQuest(spec.quest)
            if status then
                mode.target = nil
                mode.status = status
                return
            end
        end

        if spec.before and spec.before(mode) then return end

        local names = spec.mobs()
        if not names or #names == 0 then
            mode.target = nil
            mode.status = spec.idle or "Nothing selected"
            Movement.stop()
            return
        end

        local mob = Enemies.nearest(names)
        if mob then
            mode.status = Fight.status(mob, Fight.engage(mode, mob))
            return
        end

        if search:run(mode, names) then
            mode.status = "Looking for " .. table.concat(names, ", ")
        else
            mode.status = "Waiting for " .. table.concat(names, ", ") .. " (no spawn point loaded)"
        end
    end

    function mode.stop()
        mode.target = nil
        mode.status = "Idle"
        search:reset()
    end

    return mode
end
