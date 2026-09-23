--=============================================================================
-- CHEST HUNT — collects the chests around, touring spawns to find more
--=============================================================================
--  Shared by the Stack's Chalice/Fist collection and the Auto Chest farm.
--  Chests are the parts tagged "_ChestTagged" that are not disabled; the
--  nearest one is flown to (or teleported to), touched, and given up after
--  GIVE_UP seconds. With no chest in range the player spawns are toured,
--  which streams more of the map in.
--=============================================================================

local Common = require("Features.Stack.Common")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")

local ChestHunt = {}
ChestHunt.__index = ChestHunt

ChestHunt.GIVE_UP = 5          -- seconds on a chest before giving up on it
ChestHunt.SPAWN_REACHED = 100  -- studs from a spawn point to count it visited

function ChestHunt.new()
    return setmetatable({ collected = 0, ignored = {}, visited = {} }, ChestHunt)
end

function ChestHunt:reset()
    self.collected, self.current, self.reachedAt = 0, nil, nil
    self.ignored, self.visited = {}, {}
end

function ChestHunt:usable(chest)
    return chest ~= nil and chest.Parent ~= nil and not self.ignored[chest]
        and not chest:GetAttribute("IsDisabled")
end

function ChestHunt:nearest()
    local here = Player.position()
    if not here then return nil end
    local ok, tagged = pcall(function()
        return Services.get("CollectionService"):GetTagged("_ChestTagged")
    end)
    local best, bestDistance
    for _, chest in ipairs(ok and tagged or {}) do
        if self:usable(chest) then
            local distance = (chest.Position - here).Magnitude
            if not bestDistance or distance < bestDistance then best, bestDistance = chest, distance end
        end
    end
    return best
end

local function nextSpawn(visited)
    local spawns = Services.find(workspace, "_WorldOrigin.PlayerSpawns.Pirates")
    if not spawns then return nil end
    for _, model in ipairs(spawns:GetChildren()) do
        local part = model:FindFirstChild("Part")
        if part and not visited[model] then return model, part end
    end
    return nil
end

-- One step. `teleport` sets the character on the chest instead of flying
-- (faster, riskier). Returns "chest", "searching" or "none".
function ChestHunt:step(teleport)
    if not self:usable(self.current) then
        self.current, self.reachedAt = self:nearest(), nil
        if self.current then self.collected = self.collected + 1 end
    end

    local chest = self.current
    if chest then
        if teleport then
            Movement.stop()
            local hrp = Player.hrp()
            if hrp then hrp.CFrame = chest.CFrame end
        else
            Common.goTo(chest.CFrame)
        end
        if Common.near(chest.Position, 5) then
            Common.touch(chest)
            self.reachedAt = self.reachedAt or os.clock()
            if os.clock() - self.reachedAt >= ChestHunt.GIVE_UP then self.ignored[chest] = true end
        end
        return "chest"
    end

    local model, part = nextSpawn(self.visited)
    if not model then
        -- Every spawn visited: start the tour again next time.
        self.visited = {}
        return "none"
    end
    Common.goTo(part.CFrame)
    if Common.near(part.Position, ChestHunt.SPAWN_REACHED) then self.visited[model] = true end
    return "searching"
end

return ChestHunt
