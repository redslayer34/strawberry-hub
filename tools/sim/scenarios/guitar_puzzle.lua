--=============================================================================
-- SCENARIO guitar_puzzle — an account ready for the Soul Guitar, full puzzle
--=============================================================================
--  Profile: Sea 3, level 2550, every material (Dark Fragment, 250 Ectoplasm,
--  500 Bones), 6000 fragments, a full moon at night, standing at the
--  Haunted Castle gravestone.
--
--  The fake server only moves the puzzle forward when a step is really done
--  (facts from Banana / Meyy / Vxeze and the wiki):
--    gravestoneEvent 2      starts it (full moon night only)
--    Swamp                  6 Living Zombies; done only if all 6 die within
--                           SYNC_WINDOW s of each other, otherwise the dead
--                           ones come back at full health
--    Gravestones            the 7 placards clicked on the right side
--    Ghost                  GuitarPuzzleProgress "Ghost"
--    Trophies               the 5 blank tablets back to their rest position,
--                           the 5 trophy tablets turned to 180
--    Pipes                  the 10 floor tiles painted with the answer
--    soulGuitarBuy          gives the guitar once all of it is done
--=============================================================================

local Settings = require("Core.Settings")
local Guitar = require("Features.Items.Guitar")

local SYNC_WINDOW = 1.5
local OWNED = "[You already own this item.]"

SIM.world({
    sea = 3, level = 2550, fragments = 6000,
    clock = 22, moon = 5,
    position = Guitar.GRAVESTONE + Vector3.new(0, 5, 0),
    inventory = {
        { Name = "Dark Fragment", Type = "Material", Count = 1 },
        { Name = "Ectoplasm", Type = "Material", Count = 250 },
        { Name = "Bones", Type = "Material", Count = 500 },
    },
    settings = { ItemSoulGuitar = true, Weapon = "Melee", BringMob = true },
})
local melee = newInstance("Tool", "Combat", game:GetService("Players").LocalPlayer.Backpack)
melee.ToolTip = "Melee"

-- Server state.
local started, owned = false, false
local progress = { Swamp = false, Gravestones = false, Ghost = false, Trophies = false, Pipes = false }
local castle = SIM.path(workspace, "Map.Haunted Castle")

SIM.on("gravestoneEvent", function(step)
    if step == 2 and not started then
        started = true
        SIM.note("server: puzzle started")
    end
end)
SIM.on("GuitarPuzzleProgress", function(what)
    if what == "Check" then return started and progress or nil end
    if what == "Ghost" and progress.Gravestones then
        progress.Ghost = true
        SIM.note("server: ghost talked to")
    end
end)
SIM.on("soulGuitarBuy", function(check)
    if owned then return OWNED end
    local all = progress.Swamp and progress.Gravestones and progress.Ghost and progress.Trophies and progress.Pipes
    if not check and all then
        owned = true
        SIM.note("server: Soul Guitar given")
        return "Soul Guitar obtained"
    end
    return "Complete the puzzle"
end)

-- Swamp: 6 zombies, all must die together.
local zombies, deaths = {}, {}
local function spawnZombies()
    for index = 1, 6 do
        if not (zombies[index] and zombies[index].Parent) then
            local offset = Vector3.new(math.cos(index) * 25, 0, math.sin(index) * 25)
            zombies[index] = SIM.spawn("Living Zombie", Guitar.SWAMP + offset, 400)
        end
    end
end
SIM.hooks.died = function(rig)
    if rig.Name ~= "Living Zombie" or progress.Swamp then return end
    deaths[#deaths + 1] = SIM.now
    if #deaths >= 6 then
        local first, last = math.huge, -math.huge
        for index = #deaths - 5, #deaths do
            first, last = math.min(first, deaths[index]), math.max(last, deaths[index])
        end
        if last - first <= SYNC_WINDOW then
            progress.Swamp = true
            SIM.note("server: swamp done (6 zombies within " .. string.format("%.2f", last - first) .. "s)")
        end
    end
end

-- Placards: Left / Right click detectors, the right answer from the sources.
local ANSWER = { "Right", "Right", "Left", "Right", "Left", "Left", "Left" }
local placards = {}
for index, side in ipairs(ANSWER) do
    local placard = SIM.folder("Placard" .. index, castle)
    for _, name in ipairs({ "Left", "Right" }) do
        local button = SIM.part(name, Guitar.PLACARDS_SPOT + Vector3.new(index * 3, 0, 0), placard)
        newInstance("ClickDetector", "ClickDetector", button)
    end
    placards[index] = { want = side, got = nil }
end

-- Tablets and trophies.
local tablet = SIM.folder("Tablet", castle)
local BLANK = { Segment6 = true, Segment2 = true, Segment8 = true, Segment9 = true, Segment5 = true }
local segments = {}
for index = 1, 10 do
    local name = "Segment" .. index
    local segment = SIM.folder(name, tablet)
    local line = SIM.part("Line", Vector3.new(Guitar.BLANK_X + (BLANK[name] and 3 or 0), 6, 6054 + index), segment)
    line.Rotation = Vector3.new(0, 0, 90)
    newInstance("ClickDetector", "ClickDetector", segment)
    segments[name] = { line = line, blankStep = 1 }
end
for index = 1, 5 do
    local trophy = SIM.path(castle, "Trophies.Quest.Trophy" .. index)
    SIM.part("Handle", Vector3.new(-9530, 10, 6050 + index), trophy)
end

-- Lab floor.
local floor = SIM.path(castle, "Lab Puzzle.ColorFloor.Model")
local COLOURS = { "Really black", "Dusty Rose", "Storm blue", "Parsley green" }
local PIPES = {
    Part1 = "Really black", Part2 = "Really black", Part3 = "Dusty Rose", Part4 = "Storm blue",
    Part5 = "Really black", Part6 = "Parsley green", Part7 = "Really black", Part8 = "Dusty Rose",
    Part9 = "Really black", Part10 = "Storm blue",
}
local tiles = {}
for index = 1, 10 do
    local tile = SIM.part("Part" .. index, Guitar.TABLETS_SPOT + Vector3.new(index * 4, -2, 30), floor)
    newInstance("ClickDetector", "ClickDetector", tile)
    tiles[tile] = 2
    tile.BrickColor = { Name = COLOURS[2] }
end

local function checkTrophies()
    for name, state in pairs(segments) do
        if BLANK[name] then
            if state.line.Position.X ~= Guitar.BLANK_X then return false end
        elseif name ~= "Segment" and state.line.Rotation.Z ~= 180 then
            return false
        end
    end
    return true
end

SIM.hooks.click = function(detector)
    local button = detector.Parent
    local parent = button and button.Parent
    if not parent then return end
    -- Placards
    local index = tonumber(tostring(parent.Name):match("^Placard(%d+)$"))
    if index and started and progress.Swamp then
        placards[index].got = button.Name
        local all = true
        for _, placard in ipairs(placards) do if placard.got ~= placard.want then all = false end end
        if all and not progress.Gravestones then
            progress.Gravestones = true
            SIM.note("server: placards done")
        end
        return
    end
    -- Tablets (the detector sits on the segment)
    if parent == tablet then
        local state = segments[button.Name]
        if BLANK[button.Name] then
            state.blankStep = state.blankStep % 4 + 1
            state.line.Position = Vector3.new(Guitar.BLANK_X + (state.blankStep - 1), 6, state.line.Position.Z)
        else
            state.line.Rotation = Vector3.new(0, 0, (state.line.Rotation.Z + 90) % 360)
        end
        if progress.Ghost and not progress.Trophies and checkTrophies() then
            progress.Trophies = true
            SIM.note("server: trophies done")
        end
        return
    end
    -- Floor tiles
    if tiles[button] then
        tiles[button] = tiles[button] % #COLOURS + 1
        button.BrickColor = { Name = COLOURS[tiles[button]] }
        if progress.Trophies and not progress.Pipes then
            local all = true
            for tile in pairs(tiles) do
                if tile.BrickColor.Name ~= PIPES[tile.Name] then all = false end
            end
            if all then
                progress.Pipes = true
                SIM.note("server: pipes done")
            end
        end
    end
end

SIM.start()
local done = SIM.run({
    seconds = 900,
    every = function()
        -- The zombies are up once the puzzle started and until the swamp is done.
        if started and not progress.Swamp then spawnZombies() end
    end,
    untilFn = function() return owned end,
})

SIM.expect("puzzle started", started)
SIM.expect("swamp done (zombies killed together)", progress.Swamp)
SIM.expect("placards done", progress.Gravestones)
SIM.expect("ghost done", progress.Ghost)
SIM.expect("trophies done", progress.Trophies)
SIM.expect("pipes done", progress.Pipes)
SIM.expect("guitar obtained", done and owned)
SIM.finish("guitar_puzzle")
