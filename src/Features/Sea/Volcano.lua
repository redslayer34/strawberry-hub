--=============================================================================
-- VOLCANO — Prehistoric Island (Sea 3)
--=============================================================================
--    Volcanic Magnet  10 Scrap Metal (Jungle / Musketeer Pirates) and 15
--                     Blaze Ember (the Dragon Hunter's tasks), then crafted
--    Find             sails out to sea until the Prehistoric Island spawns
--    Event            Fossil Expert, the activation prompt, then kill the
--                     Lava Golems and plug the erupting rocks with skills;
--                     the lava's touch damage is removed on the way
--    Collect          dragon eggs and dino bones
--    Fully            all of it in a row, and a reset once the island is
--                     done so the next one can be found
--=============================================================================

local Boat = require("Game.Boat")
local Common = require("Features.Stack.Common")
local Dragon = require("Features.Other.Dragon")
local Enemies = require("Game.Enemies")
local Events = require("Features.Sea.Events")
local Fight = require("Features.Fight")
local Islands = require("Features.Sea.Islands")
local Mastery = require("Game.Mastery")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local World = require("Game.World")

local Volcano = {}

Volcano.SCRAP_MOBS = { "Jungle Pirate", "Musketeer Pirate" }
Volcano.SCRAP = 10
Volcano.EMBERS = 15
Volcano.GOLEM_RADIUS = 1500
Volcano.RESET_AFTER = 10       -- seconds idle on a finished island before resetting
-- Where to stand next to an erupting rock, by the rock's height (floored):
-- the reference's table.
Volcano.ROCK_OFFSETS = {
    [273] = CFrame.new(40, 0, 0), [286] = CFrame.new(40, 0, 0), [246] = CFrame.new(0, -40, 0),
    [486] = CFrame.new(40, 0, 0), [364] = CFrame.new(40, 0, 0), [682] = CFrame.new(0, 0, -40),
    [490] = CFrame.new(0, 40, 0), [691] = CFrame.new(40, 0, 0), [502] = CFrame.new(-40, 0, 0),
    [256] = CFrame.new(-40, 0, 0), [290] = CFrame.new(0, 40, 0), [427] = CFrame.new(0, 40, 0),
    [692] = CFrame.new(0, 0, 40), [316] = CFrame.new(0, 40, 0), [481] = CFrame.new(0, 40, 0),
    [594] = CFrame.new(0, 40, 0), [649] = CFrame.new(40, 0, 0), [285] = CFrame.new(0, -40, 0),
    [250] = CFrame.new(0, 40, 0), [454] = CFrame.new(-40, 0, 0),
}
Volcano.DEFAULT_OFFSET = CFrame.new(0, 40, 0)
Volcano.LOCATION = "Prehistoric Island"
Volcano.APPROACH_BACK = 40       -- studs behind the marker's head teleport
Volcano.APPROACH_UP = 20
Volcano.APPROACH_SHORT = 250     -- no head teleport: this far short of the marker
Volcano.APPROACH_HIGH = 60
-- The two ways the magnet craft has been sent: this hub's, then the one
-- the newer sources use. Tried in turn while the magnet does not show up.
-- The game's own calls (decompiled CraftWindow / DragonHunter dialogue):
-- RF/Craft "Craft" crafts; "PossibleHardcode" only asks whether the recipe
-- is unlocked -- the Volcanic Magnet needs the Dojo's Yellow belt
-- (CraftUtil.PossibleHardcode: DragonQuest.Belts.Yellow).
Volcano.CRAFT_ARGS = { "Craft", "Volcanic Magnet", 1, {} }
Volcano.UNLOCK_EVERY = 30

local search = Fight.newSearch()
local eventRan, idleSince, resetDone = false, nil, false
local unlocked, unlockedAt = nil, -math.huge

---------------------------------------------------------------------------
-- The island
---------------------------------------------------------------------------

function Volcano.island()
    local map = workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("PrehistoricIsland")
end

-- The island's marker in _WorldOrigin.Locations: there as soon as the
-- island spawns, while Map.PrehistoricIsland only streams in up close.
function Volcano.location()
    local locations = Services.find(workspace, "_WorldOrigin.Locations")
    return locations and locations:FindFirstChild(Volcano.LOCATION) or nil
end

-- Spawned, but not streamed in yet.
function Volcano.spotted()
    return Volcano.island() == nil and Volcano.location() ~= nil
end

-- A part's own CFrame, a model's pivot.
local function frameOf(node)
    if node:IsA("BasePart") then return node.CFrame end
    return Common.pivot(node)
end

-- Where to fly to reach the marker: behind its head teleport, or short of
-- the marker itself and above it (the newer sources' approach).
function Volcano.approachSpot(marker)
    local head = marker:FindFirstChild("HeadTeleport", true) or marker:FindFirstChild("Teleport_Head", true)
        or marker:FindFirstChild("Head", true)
    local headPivot = head and frameOf(head)
    if headPivot then
        return CFrame.new(headPivot.Position - headPivot.LookVector * Volcano.APPROACH_BACK
            + Vector3.new(0, Volcano.APPROACH_UP, 0))
    end
    local pivot = frameOf(marker)
    if not pivot then return nil end
    local root = Player.hrp()
    local position = pivot.Position
    local away = root and (position - root.Position) or Vector3.new(0, 0, 0)
    if away.Magnitude > Volcano.APPROACH_SHORT then
        position = position - away.Unit * Volcano.APPROACH_SHORT
    end
    return CFrame.new(position + Vector3.new(0, Volcano.APPROACH_HIGH, 0))
end

local function core()
    local island = Volcano.island()
    return island and island:FindFirstChild("Core")
end

-- The event is running (its timer is shown).
function Volcano.running()
    local player = Services.player()
    local hud = player and Services.find(player, "PlayerGui.Main.TopHUDList")
    if not hud then return false end
    local prehistoric = hud:FindFirstChild("PrehistoricRaidTimer")
    return (prehistoric ~= nil and prehistoric.Visible == true) or Islands.raidTimer()
end

local function onIsland()
    local player = Services.player()
    return player ~= nil and player:GetAttribute("CurrentLocation") == "Prehistoric Island"
end

-- Removes the lava's touch damage and the lava parts themselves (the
-- trial teleport keeps working).
function Volcano.stripLava()
    local island = Volcano.island()
    if not island then return end
    local trial = island:FindFirstChild("TrialTeleport")
    for _, node in ipairs(island:GetDescendants()) do
        local keep = trial and (node == trial or node:IsDescendantOf(trial))
        if not keep and node.Name == "TouchInterest" and node.Parent then
            pcall(function() node:Destroy() end)
        elseif not keep and node:IsA("BasePart") and node.Name:lower():find("lava", 1, true) then
            pcall(function() node:Destroy() end)
        end
    end
    local lava = core() and core():FindFirstChild("InteriorLava")
    for _, part in ipairs(lava and lava:GetChildren() or {}) do
        pcall(function() part:Destroy() end)
    end
end

function Volcano.golem()
    local enemies = workspace:FindFirstChild("Enemies")
    for _, mob in ipairs(enemies and enemies:GetChildren() or {}) do
        local root = mob:FindFirstChild("HumanoidRootPart")
        if mob.Name == "Lava Golem" and root and Enemies.isAlive(mob)
            and Player.distanceTo(root.Position) <= Volcano.GOLEM_RADIUS then
            return mob
        end
    end
    return nil
end

-- The nearest rock that is erupting.
function Volcano.rock()
    local rocks = core() and core():FindFirstChild("VolcanoRocks")
    local best, bestDistance = nil, math.huge
    for _, rock in ipairs(rocks and rocks:GetChildren() or {}) do
        -- Erupting: VFXLayer.Specs (Banana) or VFXLayer.At0.Glow (newer).
        local specs = rock.Name == "Rock" and Services.find(rock, "VFXLayer.Specs")
        local glow = rock.Name == "Rock" and Services.find(rock, "VFXLayer.At0.Glow")
        local erupting = (specs and specs.Enabled) or (glow and glow.Enabled)
        local pivot = erupting and Common.pivot(rock)
        if pivot then
            local distance = Player.distanceTo(pivot.Position)
            if distance < bestDistance then best, bestDistance = rock, distance end
        end
    end
    return best
end

function Volcano.rockSpot(rock)
    local pivot = Common.pivot(rock)
    local offset = Volcano.ROCK_OFFSETS[math.floor(pivot.Position.Y)] or Volcano.DEFAULT_OFFSET
    return pivot * offset, pivot
end

function Volcano.egg()
    local eggs = core() and core():FindFirstChild("SpawnedDragonEggs")
    for _, egg in ipairs(eggs and eggs:GetChildren() or {}) do
        local molten = egg.Name == "DragonEgg" and egg:FindFirstChild("Molten")
        if molten and molten:FindFirstChild("ProximityPrompt") then return molten end
    end
    return nil
end

function Volcano.bone()
    for _, child in ipairs(workspace:GetChildren()) do
        if child.Name == "DinoBone" then return child end
    end
    return nil
end

local function fossilExpert(label)
    local expert = World.npcPosition("Fossil Expert")
    if expert then
        Common.goTo(expert)
        return label or "Going to the Fossil Expert"
    end
    local pivot = Common.pivot(core())
    if pivot then Common.goTo(pivot) else Movement.stop() end
    return "Going to the Prehistoric Island"
end

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------

local function collectEgg(molten)
    Common.goTo(molten.CFrame)
    if fireproximityprompt and Common.near(molten.Position, 8) and Common.every("DragonEgg", 1) then
        pcall(fireproximityprompt, molten.ProximityPrompt)
    end
    return "Collecting a dragon egg"
end

-- Eggs and bones, when wanted. Returns the status, or nil.
function Volcano.collectStep(eggs, bones)
    local molten = eggs and Volcano.egg()
    if molten then return collectEgg(molten) end
    local bone = bones and not Volcano.running() and Volcano.bone()
    if bone then
        Common.goTo(bone.CFrame)
        return "Collecting a dino bone"
    end
    return nil
end

-- One step of the island's event. Returns the status.
function Volcano.eventStep(mode)
    if not onIsland() and not Volcano.running() then return fossilExpert() end
    if Common.every("StripLava", 1) then Volcano.stripLava() end

    local center = core()
    if not Volcano.running() then
        local prompt = center and center:FindFirstChild("ActivationPrompt")
        if prompt and prompt:FindFirstChild("ProximityPrompt") then
            Common.goTo(prompt.CFrame)
            if fireproximityprompt and Common.near(prompt.Position, 8) and Common.every("VolcanoStart", 3) then
                pcall(fireproximityprompt, prompt.ProximityPrompt, 1)
            end
            return "Starting the volcano"
        end
        if center and not center:FindFirstChild("FossilExpertSpawn") then
            return fossilExpert("Waiting for the Fossil Expert")
        end
        Movement.stop()
        return "Volcano done: waiting"
    end

    eventRan = true
    local golem = Volcano.golem()
    if golem then
        return Common.fight(mode, golem, true, Settings.get("VolcanoGolemWeapon"))
    end
    local rock = Volcano.rock()
    if rock then
        local spot, pivot = Volcano.rockSpot(rock)
        Common.goTo(spot)
        if Common.near(pivot, 100) then Mastery.fireAt(pivot, Events.weapons()) end
        return "Plugging an erupting rock"
    end
    local skull = center and Services.find(center, "PrehistoricRelic.Skull")
    if skull then
        Common.goTo(skull.CFrame)
        return "Waiting at the skull"
    end
    Movement.stop()
    return "Waiting for golems or rocks"
end

-- One step of crafting the magnet. Returns the status.
-- false only when the game says the recipe is locked; true or nil (no
-- answer, an older game) let the crafting go on.
function Volcano.magnetUnlocked()
    local now = os.clock()
    if now - unlockedAt < Volcano.UNLOCK_EVERY then return unlocked end
    unlockedAt = now
    local remote = Common.net("RF/Craft")
    if not remote then unlocked = nil return nil end
    local ok, answer = pcall(function() return remote:InvokeServer("PossibleHardcode", "Volcanic Magnet") end)
    if ok and type(answer) == "boolean" then unlocked = answer else unlocked = nil end
    return unlocked
end

function Volcano.magnetStep(mode)
    if Volcano.magnetUnlocked() == false then
        return "Magnet locked (Dojo Yellow belt needed): " .. Dragon.dojoStep(mode)
    end
    local scrap = Common.itemCount("Scrap Metal")
    if scrap < Volcano.SCRAP then
        return string.format("Scrap Metal %d/%d: %s", scrap, Volcano.SCRAP,
            Common.farm(mode, Volcano.SCRAP_MOBS, search))
    end
    local embers = Common.itemCount("Blaze Ember")
    if embers < Volcano.EMBERS then
        return string.format("Blaze Ember %d/%d: %s", embers, Volcano.EMBERS, Dragon.hunterStep(mode))
    end
    Movement.stop()
    if Common.every("CraftMagnet", 2) then
        Common.netInvoke("RF/Craft", (table.unpack or unpack)(Volcano.CRAFT_ARGS))
        Common.forget()
    end
    return "Crafting the Volcanic Magnet"
end

-- One step of finding the island, nil once it is here.
function Volcano.findStep()
    if Volcano.island() then return nil end
    local marker = Volcano.location()
    local spot = marker and Volcano.approachSpot(marker)
    if spot then
        -- Spawned out of streaming range: off the boat and straight there,
        -- instead of sailing past it.
        Boat.stop()
        Common.goTo(spot)
        return "Prehistoric Island spotted: going there"
    end
    return "Prehistoric: " .. Islands.sailOut()
end

---------------------------------------------------------------------------
-- Modes
---------------------------------------------------------------------------

Volcano.magnet = Mode({
    name = "Volcanic Magnet",
    key = "VolcanoMagnet",
    sea = 3,
    want = function() return Common.item("Volcanic Magnet") == nil end,
    idleStatus = "You have a Volcanic Magnet",
    tick = Volcano.magnetStep,
    stop = function() search:reset() end,
})

Volcano.find = Mode({
    name = "Find Prehistoric",
    key = "VolcanoFind",
    sea = 3,
    want = function() return Volcano.island() == nil and not Volcano.running() end,
    idleStatus = "The Prehistoric Island is here",
    tick = function() return Volcano.findStep() or "Island found" end,
    stop = Boat.stop,
})

Volcano.event = Mode({
    name = "Prehistoric Event",
    key = "VolcanoEvent",
    sea = 3,
    want = function() return Volcano.island() ~= nil end,
    idleStatus = "No Prehistoric Island",
    tick = function(mode)
        return Volcano.collectStep(Settings.get("VolcanoEggs"), Settings.get("VolcanoBones"))
            or Volcano.eventStep(mode)
    end,
})

-- The trial door opened: the newer sources' sign the volcano is done. Only
-- with no event running and nothing left to start.
function Volcano.trialOpen()
    local island = Volcano.island()
    local trial = island and island:FindFirstChild("TrialTeleport")
    if not (trial and trial:FindFirstChild("TouchInterest")) or Volcano.running() then return false end
    local prompt = core() and core():FindFirstChild("ActivationPrompt")
    return not (prompt and prompt:FindFirstChild("ProximityPrompt"))
end

-- Once the event is over and nothing is left to collect, the character is
-- reset (the reference's way to leave the island and look for the next one).
local function resetWhenDone()
    if not (eventRan or Volcano.trialOpen()) or Volcano.running() or not onIsland() then
        idleSince = nil
        return false
    end
    idleSince = idleSince or os.clock()
    if os.clock() - idleSince < Volcano.RESET_AFTER or resetDone then return false end
    resetDone, eventRan = true, false
    local humanoid = Player.humanoid()
    if humanoid then humanoid.Health = 0 end
    return true
end

Volcano.fully = Mode({
    name = "Fully Prehistoric",
    key = "VolcanoFully",
    sea = 3,
    tick = function(mode)
        if not Volcano.island() then
            resetDone = false
            -- Once it has spawned, the magnet is spent: no crafting then.
            if not Volcano.location() and not Settings.get("VolcanoSkipMagnet")
                and not Common.item("Volcanic Magnet") then
                return Volcano.magnetStep(mode)
            end
            return Volcano.findStep() or "Island found"
        end
        Boat.stop()
        local collected = Volcano.collectStep(not Settings.get("VolcanoSkipEggs"), not Settings.get("VolcanoSkipBones"))
        if collected then return collected end
        if resetWhenDone() then return "Island done: resetting" end
        return Volcano.eventStep(mode)
    end,
    stop = function()
        Boat.stop()
        search:reset()
    end,
})

function Volcano.reset()
    search:reset()
    eventRan, idleSince, resetDone = false, nil, false
    unlocked, unlockedAt = nil, -math.huge
end

return Volcano
