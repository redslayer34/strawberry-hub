--=============================================================================
-- STACK: EVENTS — Factory (Sea 2), Pirate Raid (Sea 3), fruits on the ground
--=============================================================================

local Common = require("Features.Stack.Common")
local Enemies = require("Game.Enemies")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Events = {}

---------------------------------------------------------------------------
-- Factory: the Core boss spawns in the Sea 2 factory
---------------------------------------------------------------------------

local factory = { name = "Factory" }
Events.factory = factory

function factory.enabled()
    return Settings.get("StackFactory") == true and Player.sea() == 2
end

function factory.want()
    return Enemies.findBoss("Core") ~= nil
end

function factory.tick(mode)
    local core, inWorld = Enemies.findBoss("Core")
    if not core then return "No Core" end
    return Common.fight(mode, core, inWorld)
end

---------------------------------------------------------------------------
-- Pirate Raid: waves of pirates attack the Castle on the Sea
---------------------------------------------------------------------------

local raid = { name = "Pirate Raid" }
Events.raid = raid

Events.CASTLE = Vector3.new(-5543, 313, -2964)
Events.RAID_RADIUS = 1000
Events.RAID_LINGER = 10   -- seconds to wait for the next wave

local lastRaidMob

-- Not raiders: the reference's exclusions (bosses, friends, wraiths).
function Events.isRaider(model)
    local name = model.Name
    if name == "Oni2" or name == "rip_indra True Form" then return false end
    if name:find("Boss", 1, true) or name:find("Friend", 1, true) or name:find("Wraith", 1, true) then
        return false
    end
    if not model:IsA("Model") or not Enemies.isAlive(model) then return false end
    return (model.HumanoidRootPart.Position - Events.CASTLE).Magnitude < Events.RAID_RADIUS
end

function Events.raider()
    local enemies = workspace:FindFirstChild("Enemies")
    for _, model in ipairs(enemies and enemies:GetChildren() or {}) do
        if Events.isRaider(model) then return model, true end
    end
    for _, model in ipairs(Services.replicated():GetChildren()) do
        if Events.isRaider(model) then return model, false end
    end
    return nil
end

function raid.enabled()
    return Settings.get("StackPirateRaid") == true and Player.sea() == 3
end

function raid.want()
    if Events.raider() then
        lastRaidMob = os.clock()
        return true
    end
    return lastRaidMob ~= nil and os.clock() - lastRaidMob < Events.RAID_LINGER
end

function raid.tick(mode)
    local pirate, inWorld = Events.raider()
    if pirate then return Common.fight(mode, pirate, inWorld) end
    mode.target = nil
    Common.goTo(Events.CASTLE + Vector3.new(0, 60, 0))
    return "Waiting for the next wave"
end

---------------------------------------------------------------------------
-- Fruits on the ground
---------------------------------------------------------------------------

local fruit = { name = "Fruit" }
Events.fruit = fruit

function Events.groundFruit()
    for _, child in ipairs(workspace:GetChildren()) do
        if (child:IsA("Tool") or child:IsA("Model")) and child.Name:find("Fruit", 1, true)
            and child:FindFirstChild("Handle") then
            return child
        end
    end
    return nil
end

function fruit.enabled()
    return Settings.get("StackFruit") == true
end

function fruit.want()
    return Events.groundFruit() ~= nil
end

function fruit.tick(mode)
    mode.target = nil
    local found = Events.groundFruit()
    if not found then return "No fruit" end
    local handle = found.Handle
    Common.goTo(handle.CFrame)
    if Common.near(handle.Position, 5) then
        Common.touch(handle)
        local humanoid = Player.humanoid()
        if humanoid then humanoid.Jump = true end
    end
    return "Picking up " .. found.Name
end

function fruit.hop()
    if Settings.get("StackHopFruit") and not Events.groundFruit() then return "no fruit" end
    return nil
end

function Events.reset()
    lastRaidMob = nil
end

return Events
