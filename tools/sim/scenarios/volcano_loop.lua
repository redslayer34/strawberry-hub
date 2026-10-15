--=============================================================================
-- SCENARIO volcano_loop — one full Prehistoric Island round (Volcano.fully)
--=============================================================================
--  Profile: Sea 3, the magnet's materials in hand (10 Scrap Metal, 15 Blaze
--  Ember), a melee with Z/X/C, at the Tiki boat dealer.
--
--  The fake server (facts from Banana's FullyEventVolcano and the newer
--  "Banana Hub" copy):
--    RF/Craft            takes the materials, gives the Volcanic Magnet
--    BuyBoat             a boat at the dealer
--    island spawn        2000 studs out with the magnet: the magnet is spent
--                        and the island's marker appears in
--                        _WorldOrigin.Locations 4000 studs ahead; the Map
--                        island only streams in within 1500 studs
--    ActivationPrompt    starts the event: PrehistoricRaidTimer shown, 2
--                        Lava Golems, 3 rocks erupting one after another
--    a rock              calms after 3 skills aimed at it (within 40 studs)
--                        from 150 studs or closer
--    event end           golems dead and rocks calm: timer hidden, 2 dragon
--                        eggs (prompt) and a dino bone (touched)
--    CurrentLocation     "Prehistoric Island" within 600 studs of it
--  Expected: magnet crafted, island found, event done, 2 eggs, 1 bone, reset.
--=============================================================================

local Boat = require("Game.Boat")
local Volcano = require("Features.Sea.Volcano")
local Players = game:GetService("Players")

local DEALER = Boat.DEALERS[3]

SIM.world({
    sea = 3, level = 2550,
    position = DEALER + Vector3.new(0, 5, 0),
    inventory = {
        { Name = "Scrap Metal", Type = "Material", Count = 10 },
        { Name = "Blaze Ember", Type = "Material", Count = 15 },
    },
    settings = {
        VolcanoFully = true, VolcanoGolemWeapon = "Melee", Weapon = "Melee",
        SeaSkillWeapons = { Melee = true },
    },
})
SIM.tool("Combat", "Melee", { "Z", "X", "C" })
SIM.enableBoats()

local state = { crafted = false, spawned = false, streamed = false, started = false, over = false,
    eggs = 0, bones = 0, resets = 0, yellowBelt = true }
local islandAt, island, core
local golems, rocks = {}, {}

SIM.onNet("RF/Craft", function(...)
    local args = { ... }
    SIM.note("server: RF/Craft " .. tostring(args[1]) .. " " .. tostring(args[2]))
    -- Decompiled CraftUtil: "PossibleHardcode" only says whether the recipe
    -- is unlocked (the Dojo's Yellow belt); "Craft" crafts.
    if args[1] == "PossibleHardcode" then return state.yellowBelt end
    if args[1] ~= "Craft" or args[2] ~= "Volcanic Magnet" or not state.yellowBelt then return nil end
    if state.crafted then return nil end
    local scrap, ember = 0, 0
    for _, item in ipairs(SIM.inventory) do
        if item.Name == "Scrap Metal" then scrap = item.Count end
        if item.Name == "Blaze Ember" then ember = item.Count end
    end
    if scrap >= 10 and ember >= 15 then
        SIM.take("Scrap Metal", 10)
        SIM.take("Blaze Ember", 15)
        SIM.give("Volcanic Magnet", 1)
        state.crafted = true
        SIM.note("server: Volcanic Magnet crafted")
    end
    return true
end)

local function hasMagnet()
    for _, item in ipairs(SIM.inventory) do
        if item.Name == "Volcanic Magnet" then return true end
    end
    return false
end

-- The island streams in.
local function streamIsland()
    island = SIM.folder("PrehistoricIsland", workspace.Map)
    core = SIM.part("Core", islandAt, island)
    local prompt = SIM.part("ActivationPrompt", islandAt + Vector3.new(0, 30, 0), core)
    newInstance("ProximityPrompt", "ProximityPrompt", prompt)
    SIM.part("FossilExpertSpawn", islandAt + Vector3.new(40, 10, 0), core)
    local relic = SIM.folder("PrehistoricRelic", core)
    SIM.part("Skull", islandAt + Vector3.new(0, 60, 0), relic)
    SIM.folder("VolcanoRocks", core)
    SIM.folder("SpawnedDragonEggs", core)
    SIM.folder("InteriorLava", core)
    SIM.npc("Fossil Expert", islandAt + Vector3.new(40, 10, 0))
    state.streamed = true
    SIM.note("server: island streamed in")
end

local function erupt(index)
    local rock = newInstance("Model", "Rock", core.VolcanoRocks)
    rock.WorldPivot = CFrame.new(islandAt + Vector3.new(index * 80, 273.5 - islandAt.Y, 0))
    local layer = newInstance("Folder", "VFXLayer", rock)
    newInstance("ParticleEmitter", "Specs", layer).Enabled = true
    rocks[#rocks + 1] = { model = rock, hits = 0 }
    SIM.note("server: rock " .. index .. " erupting")
end

SIM.hooks.prompt = function(prompt)
    local parent = prompt.Parent
    if parent and parent.Name == "ActivationPrompt" and not state.started then
        state.started = true
        state.startedAt = SIM.now
        parent.Parent = nil
        SIM.hud("PrehistoricRaidTimer", true)
        for index = 1, 2 do
            golems[index] = SIM.spawn("Lava Golem", islandAt + Vector3.new(30 * index, 5, 30), 300)
        end
        SIM.note("server: volcano event started")
    elseif parent and parent.Name == "Molten" then
        parent.Parent.Parent = nil
        SIM.give("Dragon Egg", 1)
        state.eggs = state.eggs + 1
        SIM.note("server: dragon egg collected")
    end
end

SIM.hooks.skill = function(key, aim)
    local hrp = SIM.hrp()
    for _, rock in ipairs(rocks) do
        local specs = rock.model.VFXLayer.Specs
        local pivot = rock.model.WorldPivot.Position
        if specs.Enabled and aim and hrp and (aim.Position - pivot).Magnitude <= 40
            and (hrp.Position - pivot).Magnitude <= 150 then
            rock.hits = rock.hits + 1
            if rock.hits >= 3 then
                specs.Enabled = false
                SIM.note("server: rock calmed")
            end
        end
    end
end

SIM.hooks.died = function(rig)
    if rig.Name == "Lava Golem" then SIM.note("server: golem down") end
end

local lastHealth = 100
SIM.start()
local done = SIM.run({
    seconds = 900,
    stuckAfter = 90,
    every = function()
        local hrp = SIM.hrp()
        if not hrp then return end
        local player = Players.LocalPlayer
        -- Death watch (the reset after the island).
        local humanoid = SIM.humanoid()
        if humanoid and humanoid.Health <= 0 and lastHealth > 0 and state.over then
            state.resets = state.resets + 1
            SIM.note("character reset after the island")
        end
        lastHealth = humanoid and humanoid.Health or 0
        -- Spawn: sailing 2000 studs out with the magnet.
        if not state.spawned and hasMagnet() and humanoid and humanoid.SeatPart
            and (hrp.Position - DEALER).Magnitude >= 2000 then
            SIM.take("Volcanic Magnet", 1)
            state.spawned = true
            local ahead = (hrp.Position - DEALER).Unit
            islandAt = Vector3.new(hrp.Position.X, 20, hrp.Position.Z) + Vector3.new(ahead.X, 0, ahead.Z) * 4000
            local marker = SIM.part("Prehistoric Island", islandAt, workspace._WorldOrigin.Locations)
            SIM.note("server: island spawned (marker 4000 studs ahead)")
            marker.CFrame = CFrame.new(islandAt)
        end
        if state.spawned and not state.streamed and (hrp.Position - islandAt).Magnitude <= 1500 then
            streamIsland()
        end
        if state.streamed then
            local near = (hrp.Position - islandAt).Magnitude <= 600
            player:SetAttribute("CurrentLocation", near and "Prehistoric Island" or "Sea")
        end
        -- Event script: rocks one after another, then the end.
        if state.started and not state.over then
            local t = SIM.now - state.startedAt
            if t >= 5 and #rocks == 0 then erupt(1) end
            if t >= 25 and #rocks == 1 then erupt(2) end
            if t >= 45 and #rocks == 2 then erupt(3) end
            local golemsLeft = false
            for _, golem in ipairs(golems) do
                if golem.Parent and golem.Humanoid.Health > 0 then golemsLeft = true end
            end
            local hot = false
            for _, rock in ipairs(rocks) do if rock.model.VFXLayer.Specs.Enabled then hot = true end end
            if t >= 50 and #rocks == 3 and not golemsLeft and not hot then
                state.over = true
                SIM.hud("PrehistoricRaidTimer", false)
                for index = 1, 2 do
                    local egg = newInstance("Model", "DragonEgg", core.SpawnedDragonEggs)
                    local molten = SIM.part("Molten", islandAt + Vector3.new(-30 * index, 15, 0), egg)
                    newInstance("ProximityPrompt", "ProximityPrompt", molten)
                end
                SIM.part("DinoBone", islandAt + Vector3.new(0, 10, -40), workspace)
                SIM.note("server: event over, 2 eggs and a bone")
            end
        end
        -- Bones are picked up by touch.
        local bone = workspace:FindFirstChild("DinoBone")
        if bone and (bone.Position - hrp.Position).Magnitude <= 6 then
            bone.Parent = nil
            SIM.give("Dinosaur Bones", 1)
            state.bones = state.bones + 1
            SIM.note("server: dino bone collected")
        end
    end,
    untilFn = function() return state.resets >= 1 end,
})

SIM.expect("magnet crafted", state.crafted)
SIM.expect("island spawned while sailing", state.spawned)
SIM.expect("island reached (streamed in)", state.streamed)
SIM.expect("event started", state.started)
SIM.expect("event finished (golems and rocks)", state.over)
SIM.expect("2 dragon eggs", state.eggs == 2, state.eggs)
SIM.expect("1 dino bone", state.bones == 1, state.bones)
SIM.expect("reset after the island", done)
SIM.finish("volcano_loop")
