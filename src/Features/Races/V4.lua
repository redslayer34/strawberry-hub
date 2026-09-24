--=============================================================================
-- RACES: V4 — gears, the lever, the trials
--=============================================================================
--  Loop "RaceV4" (does not move the character):
--    Turn On V4     the Awakening tool, when the energy bar is full
--    Buy Gear       the Ancient One's gear, when he offers one
--    Choose Gears   spends the temple points (Alpha or Omega)
--    No Fog         clears the Lighting fog
--    Reset          dies as soon as the trial's free-for-all starts
--  Farm modes:
--    Ancient Clock  stays at the temple's clock prompt
--    Train          the Ancient One's training: V4 on, bone mobs
--    Pull Lever     Valkyrie Helm + Mirror Fractal; the Mirage blue gear
--                   (night: look at the moon from the highest point), then
--                   the temple lever
--    Trial          goes to the race door; inside, finishes the race trial
--    Kill Players   after the trial, fights the players inside the border
--    Draco Trial    Trial of Flames: carries the three relics (finds the
--                   Prehistoric Island first, with a Volcanic Magnet)
--=============================================================================

local Boat = require("Game.Boat")
local Common = require("Features.Stack.Common")
local Data = require("Game.Data")
local Duel = require("Features.Races.Duel")
local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local Islands = require("Features.Sea.Islands")
local Loop = require("Core.Loop")
local Mastery = require("Game.Mastery")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local Volcano = require("Features.Sea.Volcano")
local World = require("Game.World")

local V4 = {}

V4.TEMPLE = Vector3.new(28282.5703125, 14896.8505859375, 105.1042709350586)
V4.LEVER_Z = 75.469101
V4.LEVER_TOLERANCE = 0.2
V4.MIRAGE_TOP = 211.88
V4.TOP_MESH = "rbxassetid://6745037796"
V4.GEAR_MESH = "rbxassetid://10153114969"
V4.CLOCK_DOOR = Vector3.new(3032.780029296875, 2280.85107421875, -7325.47802734375)
V4.TRIALS = {
    "Trial of the Machine", "Trial of Speed", "Trial of Strength", "Trial of Water",
    "Trial of the King", "Trial of Carnage", "Trial of Flames",
}
V4.TRIAL_RADIUS = 1000
V4.RELIC_COLOURS = {
    { 132, 203, 0 },
    { 232, 106, 110 },
    { 191, 153, 0 },
}
V4.GEAR_TYPES = { "Alpha", "Omega" }

local search = Fight.newSearch()

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------

local function isDraco()
    return Player.data("Race") == "Draco"
end

-- The Ancient One's answer, as the reference words it.
function V4.status()
    local character = Player.character()
    if not character or not character:FindFirstChild("RaceTransformed") then
        return "You have yet to achieve greatness"
    end
    local code, progress, price
    if isDraco() then
        code, progress, price = Common.invoke("UpgradeRace", "Check", 2)
    else
        code, progress, price = Common.invoke("UpgradeRace", "Check")
    end
    progress = tonumber(progress) or 0
    if code == 1 or code == 3 then return "Required Train More" end
    if code == 2 or code == 4 or code == 7 then return "Can Buy Gear With " .. tostring(price) .. " Fragments" end
    if code == 5 then return "You Are Done Your Race." end
    if code == 6 then return "Upgrades completed: " .. (progress - 2) .. "/3, Need Trains More" end
    if code == 8 then return "Remaining " .. (10 - progress) .. " training sessions." end
    if code == 0 then return "Ready For Trial" end
    return "You have yet to achieve greatness"
end

function V4.needsTraining()
    local status = V4.status()
    return status == "Required Train More" or status:find("Upgrades completed", 1, true) ~= nil
        or status:find("training sessions", 1, true) ~= nil or status:find("Can Buy Gear", 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Loop actions
---------------------------------------------------------------------------

function V4.turnOn()
    local character = Player.character()
    local energy = character and character:FindFirstChild("RaceEnergy")
    local transformed = character and character:FindFirstChild("RaceTransformed")
    if not energy or (tonumber(energy.Value) or 0) < 1 or not transformed or transformed.Value then return false end
    local player = Services.player()
    local tool = (player and Services.find(player, "Backpack.Awakening")) or character:FindFirstChild("Awakening")
    local remote = tool and tool:FindFirstChild("RemoteFunction")
    if not remote then return false end
    pcall(function() remote:InvokeServer(true) end)
    return true
end

function V4.buyGear()
    if not V4.status():find("Can Buy Gear", 1, true) then return false end
    if isDraco() then
        Services.invoke("UpgradeRace", "Buy", 2)
    else
        Services.invoke("UpgradeRace", "Buy")
    end
    Common.forget()
    return true
end

local function gearType(letter)
    if letter == "A" then return "Alpha" end
    if letter == "B" then return "Omega" end
    return "Blank"
end

-- The gear the temple lets you spend a point on (the reference's
-- DetectGearUp, without its UI module). `check` is TempleClock Check.
function V4.selectableGear(check)
    if type(check) ~= "table" or type(check.RaceDetails) ~= "table" then return nil end
    local details = check.RaceDetails
    local gears = type(details.Gears) == "table" and details.Gears or {}
    local hasLevel = (tonumber(check.RaceLevel) or 0) >= 2
    local hadPoint = check.HadPoint == true
    local spent = (tonumber(details.A) or 0) + (tonumber(details.B) or 0)
    local types = { [2] = gearType(gears[1]), [3] = gearType(gears[2]), [4] = gearType(gears[3]) }
    local can = {}
    if not hasLevel then
        can[1] = true
        hadPoint = true
    end
    if hadPoint and hasLevel then
        can[2] = spent == 0
        can[3] = spent == 1
        can[4] = spent >= 2
        if spent >= 3 then
            can[2], can[3], can[4] = true, true, true
            local key = types[2] .. types[3] .. types[4]
            if key == "AlphaAlphaOmega" or key == "OmegaOmegaAlpha" then
                can[4] = false
            elseif key == "AlphaOmegaOmega" or key == "OmegaAlphaAlpha" then
                can[4], can[2] = false, false
            elseif key == "OmegaAlphaOmega" or key == "AlphaOmegaAlpha" then
                can[4], can[3] = false, false
            end
        end
    end
    for index = 1, 5 do
        if can[index] then return "Gear" .. index end
    end
    return nil
end

function V4.chooseGear()
    local check = Services.invoke("TempleClock", "Check")
    if type(check) ~= "table" or not check.HadPoint then return false end
    local gear = V4.selectableGear(check)
    if not gear then return false end
    local wanted = Settings.get("RaceGearType") == "Alpha" and "Alpha" or "Omega"
    Services.invoke("TempleClock", "SpendPoint", gear, wanted)
    local after = Services.invoke("TempleClock", "Check")
    if type(after) == "table" and after.HadPoint and V4.selectableGear(after) == gear then
        Services.invoke("TempleClock", "SpendPoint", gear, wanted == "Alpha" and "Omega" or "Alpha")
    end
    return true
end

function V4.noFog()
    local lighting = Services.get("Lighting")
    pcall(function() lighting.FogEnd = 100000 end)
    for _, child in ipairs(lighting:GetChildren()) do
        if child:IsA("Atmosphere") then pcall(function() child:Destroy() end) end
    end
end

---------------------------------------------------------------------------
-- The temple
---------------------------------------------------------------------------

function V4.temple()
    local map = workspace:FindFirstChild("Map")
    local temple = map and map:FindFirstChild("Temple of Time")
    if temple and not temple:GetAttribute("ClientBorrowed") then return temple end
    return nil
end

local function forcefield()
    local temple = V4.temple()
    return temple and Services.find(temple, "FFABorder.Forcefield")
end

-- The free-for-all after a trial: the border is shown.
function V4.borderUp()
    local field = forcefield()
    return field ~= nil and field.Transparency ~= 1
end

local function location(name)
    local locations = Services.find(workspace, "_WorldOrigin.Locations")
    return locations and locations:FindFirstChild(name)
end

local function nearLocation(name, radius)
    local part = location(name)
    return part ~= nil and Player.distanceTo(part.Position) <= (radius or V4.TRIAL_RADIUS), part
end

function V4.nearTrial()
    for _, name in ipairs(V4.TRIALS) do
        if nearLocation(name, 1500) then return true end
    end
    return false
end

function V4.raidTimer()
    local player = Services.player()
    local timer = player and Services.find(player, "PlayerGui.Main.TopHUDList.RaidTimer")
    return timer ~= nil and timer.Visible == true
end

local function door(temple, race)
    local corridor = temple and temple:FindFirstChild(tostring(race) .. "Corridor")
    return corridor and Services.find(corridor, "Door.Door.RightDoor.Union")
end

local function raceOf(player)
    local race = Services.find(player, "Data.Race")
    return race and race.Value
end

local ABILITIES = { "Last Resort", "Agility", "Water Body", "Heavenly Blood", "Energy Core", "Heightened Senses" }

local function hasAbility(root)
    for _, name in ipairs(ABILITIES) do
        if root:FindFirstChild(name) then return true end
    end
    return false
end

-- Players standing at their own race's door: `accept(player)` filters.
function V4.playersAtDoors(accept)
    local temple = V4.temple()
    local count = 0
    for _, player in ipairs(Services.get("Players"):GetPlayers()) do
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        local union = root and door(temple, raceOf(player))
        if union and accept(player, root) and (root.Position - union.Position).Magnitude < 100 then
            count = count + 1
        end
    end
    return count
end

---------------------------------------------------------------------------
-- Train
---------------------------------------------------------------------------

V4.train = Mode({
    name = "V4 Training",
    key = "RaceTrain",
    sea = 3,
    want = V4.needsTraining,
    idleStatus = "No training asked (see the Ancient One)",
    tick = function(mode)
        V4.turnOn()
        V4.buyGear()
        return "Training: " .. Common.farm(mode, Data.BONE_MOBS, search)
    end,
    stop = function() search:reset() end,
})

---------------------------------------------------------------------------
-- Ancient Clock
---------------------------------------------------------------------------

V4.clock = Mode({
    name = "Ancient Clock",
    key = "RaceTeleportClock",
    sea = 3,
    tick = function()
        local prompt = V4.temple() and V4.temple():FindFirstChild("Prompt")
        if not prompt then
            Common.goTo(V4.TEMPLE)
            return "Going to the Temple of Time"
        end
        Common.goTo(prompt.CFrame)
        return "At the Ancient Clock"
    end,
})

---------------------------------------------------------------------------
-- Pull Lever
---------------------------------------------------------------------------

local function mirage()
    local map = workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("MysticIsland")
end

local function meshIn(root, mesh, deep)
    for _, part in ipairs(deep and root:GetDescendants() or root:GetChildren()) do
        if part:IsA("MeshPart") and part.MeshId == mesh then return part end
    end
    return nil
end

function V4.isNight()
    local time = Services.get("Lighting").ClockTime or 12
    return time >= 18 or time < 5
end

local function lookAtMoon()
    pcall(function()
        local camera = workspace.CurrentCamera
        local position = camera.CFrame.Position
        camera.CFrame = CFrame.new(position, position + Services.get("Lighting"):GetMoonDirection())
    end)
end

local function mirageTop(island)
    local top = meshIn(island, V4.TOP_MESH, true)
    if not top then
        local dealer = World.npcPosition("Advanced Fruit Dealer")
        if dealer then
            Common.goTo(dealer)
            return nil, "Going to the Mirage's dealer"
        end
        Movement.stop()
        return nil, "Mirage top not loaded"
    end
    local spot = top.CFrame * CFrame.new(0, V4.MIRAGE_TOP, 0)
    Common.goTo(spot)
    return Common.near(spot, 10), "Going to the Mirage's highest point"
end

local function blueGear(island)
    local gear = meshIn(island, V4.GEAR_MESH, false)
    if gear and not gear.CanCollide and gear.Transparency ~= 1 then
        Common.goTo(gear.CFrame)
        return "Collecting the blue gear"
    end
    local atTop, status = mirageTop(island)
    if not atTop then return status end
    lookAtMoon()
    if Common.every("MoonT", 5) then Common.press("T") end
    return "Looking at the moon"
end

local function leverStep(temple)
    local lever = temple:FindFirstChild("Lever")
    local handle = lever and lever:FindFirstChild("Lever")
    if not handle then
        Common.goTo(V4.TEMPLE)
        return "Looking for the lever"
    end
    if math.abs(handle.CFrame.Z - V4.LEVER_Z) <= V4.LEVER_TOLERANCE then
        Movement.stop()
        return "Lever pulled"
    end
    local part = lever:FindFirstChild("Part") or handle
    Common.goTo(part.CFrame)
    local prompt = Services.find(lever, "Prompt.ProximityPrompt")
    if prompt and fireproximityprompt and Common.near(part.Position, 10) and Common.every("Lever", 2) then
        pcall(fireproximityprompt, prompt, 1)
    end
    return "Pulling the lever"
end

V4.lever = Mode({
    name = "Pull Lever",
    key = "RacePullLever",
    sea = 3,
    tick = function()
        if not Common.item("Valkyrie Helm") or not Common.item("Mirror Fractal") then
            Movement.stop()
            return "Needs the Valkyrie Helm and the Mirror Fractal"
        end
        if Common.invoke("CheckTempleDoor") then
            local temple = V4.temple()
            if not temple then
                Common.goTo(V4.TEMPLE)
                return "Going to the Temple of Time"
            end
            return leverStep(temple)
        end
        local step = Common.invoke("RaceV4Progress", "Check")
        if step == 1 or step == 3 then
            Movement.stop()
            if Common.every("V4Progress", 3) then
                Services.invoke("RaceV4Progress", step == 1 and "Begin" or "Continue")
                Common.forget()
            end
            return "Talking to the Ancient One"
        end
        if step == 2 then
            Common.goTo(V4.CLOCK_DOOR)
            if Common.near(V4.CLOCK_DOOR, 8) and Common.every("V4Teleport", 3) then
                Services.invoke("RaceV4Progress", "Teleport")
                Common.forget()
            end
            return "Going through the Great Tree"
        end
        local island = mirage()
        if island then
            if V4.isNight() then return blueGear(island) end
            local _, status = mirageTop(island)
            return status .. " (waiting for the night)"
        end
        if Settings.get("RaceFindMirage") then return Islands.findMirageStep() or "Mirage found" end
        Movement.stop()
        if Settings.get("RaceHop") then Common.hop("no Mirage Island", true) end
        return "Needs a Mirage Island"
    end,
    stop = Boat.stop,
})

---------------------------------------------------------------------------
-- Trial
---------------------------------------------------------------------------

local function trialMob(name)
    local near, part = nearLocation(name)
    local enemies = workspace:FindFirstChild("Enemies")
    if not near or not enemies then return nil end
    for _, mob in ipairs(enemies:GetChildren()) do
        local root = mob:FindFirstChild("HumanoidRootPart")
        if root and Enemies.isAlive(mob) and (root.Position - part.Position).Magnitude <= V4.TRIAL_RADIUS then
            return mob
        end
    end
    return nil
end

local function seaBeast()
    local near, part = nearLocation("Trial of Water", 1500)
    local beasts = workspace:FindFirstChild("SeaBeasts")
    if not near or not beasts then return nil end
    for _, beast in ipairs(beasts:GetChildren()) do
        local root = beast:FindFirstChild("HumanoidRootPart")
        local health = beast:FindFirstChild("Health")
        if beast.Name:find("SeaBeast", 1, true) and root and (root.Position - part.Position).Magnitude <= 1500
            and health and health.Value > 0 then
            return beast
        end
    end
    return nil
end

local function insideTrial(mode, race)
    if race == "Human" or race == "Ghoul" then
        local mob = trialMob(race == "Human" and "Trial of Strength" or "Trial of Carnage")
        if mob then return Common.fight(mode, mob, true) end
        Movement.stop()
        return "Waiting for the trial's mobs"
    end
    if race == "Skypiea" then
        local finish = Services.find(workspace, "Map.SkyTrial.Model.FinishPart")
        if finish then
            Common.goTo(finish.CFrame)
            return "Flying to the finish"
        end
    elseif race == "Mink" then
        local start = workspace:FindFirstChild("StartPoint")
        if start and nearLocation("Trial of Speed") then
            Common.goTo(start.CFrame * CFrame.new(0, 2, 0))
            return "Running to the end"
        end
    elseif race == "Fishman" then
        local beast = seaBeast()
        if beast then
            local root = beast.HumanoidRootPart
            if math.abs(root.Position.Y + 60) <= 175 then
                Common.goTo(root.CFrame * CFrame.new(0, 200, 50))
            else
                Common.goTo(Vector3.new(root.Position.X, 140, root.Position.Z))
            end
            if Player.distanceTo(root.Position) < 400 then
                Mastery.fireAt(CFrame.new(root.Position.X, 40, root.Position.Z))
            end
            return "Fighting the sea beast"
        end
    elseif race == "Cyborg" then
        Common.goTo(V4.TEMPLE)
        return "Surviving the trial"
    end
    Movement.stop()
    return "In the trial"
end

local function hopForMoon()
    if not Settings.get("RaceHop") then return false end
    local moon = World.moon()
    local time = Services.get("Lighting").ClockTime or 12
    if (moon == "Full Moon" and not (time > 5 and time < 12)) or moon == "Next Night" then return false end
    return Common.hop("no full moon", true)
end

local function isMultiAccount(player)
    local accounts = Settings.get("RaceMultiAccounts")
    return type(accounts) == "table" and accounts[player.Name] == true
end

V4.trial = Mode({
    name = "Race Trial",
    key = "RaceTrial",
    sea = 3,
    -- The reference's "Stack Train With Trial Race": training comes first.
    want = function()
        return not (Settings.get("RaceTrainFirst") and Settings.get("RaceTrain") and V4.needsTraining())
    end,
    idleStatus = "Training first",
    tick = function(mode)
        if hopForMoon() then return "Hopping for a full moon" end
        local temple = V4.temple()
        if not temple and not V4.nearTrial() then
            Common.goTo(V4.TEMPLE)
            return "Going to the Temple of Time"
        end
        if V4.borderUp() and not V4.nearTrial() then
            Movement.stop()
            return "Trial over (free-for-all)"
        end
        if V4.raidTimer() then return insideTrial(mode, Player.data("Race")) end
        local union = door(temple, Player.data("Race"))
        if not union then
            Movement.stop()
            return "Waiting for the trial"
        end
        Common.goTo(union.CFrame)
        if not Common.near(union.Position, 8) then return "Going to the race door" end
        if Settings.get("RaceMultiTrial") and V4.playersAtDoors(isMultiAccount) >= 2 and Common.every("TrialT", 2) then
            Common.press("T")
            return "Starting the trial together"
        end
        if Settings.get("RaceV3AtDoor") and Common.every("TrialV3", 2)
            and V4.playersAtDoors(function(_, root) return hasAbility(root) end) >= 2 then
            Common.press("T")
        end
        return "At the race door"
    end,
})

---------------------------------------------------------------------------
-- Kill players after the trial
---------------------------------------------------------------------------

function V4.playerInBorder()
    local field = forcefield()
    if not field then return nil end
    local me = Services.player()
    local half = field.Size / 2
    for _, player in ipairs(Services.get("Players"):GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if player ~= me and root and humanoid and humanoid.Health > 0 then
            local offset = root.Position - field.Position
            if math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z then
                return player
            end
        end
    end
    return nil
end

V4.killPlayers = Mode({
    name = "Trial Players",
    key = "RaceKillPlayers",
    sea = 3,
    want = function() return V4.borderUp() and V4.raidTimer() and V4.playerInBorder() ~= nil end,
    idleStatus = "Waiting for the trial's free-for-all",
    tick = function(mode)
        local player = V4.playerInBorder()
        if not player then return "No player left" end
        local skills = Settings.get("RaceTrialSkills")
            and (not Settings.get("RaceTrialKenOnly") or player:GetAttribute("KenActive") == true)
        return Duel.fight(mode, player, Settings.get("RaceTrialWeapon"), skills) or "Next player"
    end,
    stop = function() Duel.reset() end,
})

---------------------------------------------------------------------------
-- Draco: Trial of Flames
---------------------------------------------------------------------------

local function colourMatches(color, rgb)
    return math.abs(color.R * 255 - rgb[1]) < 2 and math.abs(color.G * 255 - rgb[2]) < 2
        and math.abs(color.B * 255 - rgb[3]) < 2
end

-- A relic is still to do while one of its particles is on.
local function relicActive(model)
    for _, child in ipairs(model:GetDescendants()) do
        if child:IsA("ParticleEmitter") and child.Enabled then return true end
    end
    return false
end

-- { [index] = relic model } from the three colours.
function V4.relics()
    local found = {}
    local origin = workspace:FindFirstChild("_WorldOrigin")
    for _, model in ipairs(origin and origin:GetChildren() or {}) do
        if model:IsA("Model") and model.Name == "Relic" then
            local mesh = model:FindFirstChildWhichIsA("MeshPart")
            for index, rgb in ipairs(V4.RELIC_COLOURS) do
                if mesh and colourMatches(mesh.Color, rgb) then found[index] = model end
            end
        end
    end
    return found
end

local function usePrompt(node, label)
    local pivot = Common.pivot(node)
    if not pivot then return "Looking for " .. label end
    Common.goTo(pivot)
    local prompt = node:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and fireproximityprompt and Common.near(pivot, 8) and Common.every("Relic", 3) then
        pcall(fireproximityprompt, prompt)
    end
    return label
end

local function relicStep()
    local trial = Services.find(workspace, "Map.DracoTrial")
    if not trial then return "Trial not loaded" end
    local relics = V4.relics()
    for index = 1, 3 do
        local relic = relics[index]
        if relic and relicActive(relic) and relic.PrimaryPart and relic.PrimaryPart:FindFirstChild("AlignPosition") then
            local goal = trial:FindFirstChild("EndRelic" .. index, true)
            if goal then return usePrompt(goal, "Carrying relic " .. index) end
        end
    end
    for index = 1, 3 do
        local relic = relics[index]
        if relic and relicActive(relic) then
            local stand = trial:FindFirstChild("Relic" .. index, true)
            if stand then return usePrompt(stand, "Taking relic " .. index) end
        end
    end
    Movement.stop()
    return "Relics done"
end

V4.dracoTrial = Mode({
    name = "Trial of Flames",
    key = "RaceDracoTrial",
    sea = 3,
    want = isDraco,
    idleStatus = "Only for the Draco race",
    tick = function(mode)
        if nearLocation("Trial of Flames", 3000) then
            local exit = Services.find(workspace, "Map.DracoTrial.TrialDoor.DoorTouch")
            if exit and exit:FindFirstChild("TouchInterest") then
                Common.goTo(exit.CFrame)
                return "Trial done: leaving"
            end
            if V4.raidTimer() then return relicStep() end
            Movement.stop()
            local remote = Services.find(Services.replicated(), "Remotes.DracoTrial")
            if remote and Common.every("DracoTrial", 3) then pcall(function() remote:InvokeServer() end) end
            return "Starting the trial"
        end
        local teleport = Services.find(workspace, "Map.PrehistoricIsland.TrialTeleport")
        if teleport then
            Boat.stop()
            Common.goTo(teleport.CFrame)
            return "Going to the trial"
        end
        if Volcano.island() then
            Boat.stop()
            local expert = World.npcPosition("Fossil Expert")
            if expert then Common.goTo(expert) else Movement.stop() end
            return "Waiting for the trial teleport"
        end
        if not Common.item("Volcanic Magnet") then return "Magnet: " .. Volcano.magnetStep(mode) end
        return Volcano.findStep() or "Island found"
    end,
    stop = Boat.stop,
})

---------------------------------------------------------------------------
-- Loop
---------------------------------------------------------------------------

function V4.step()
    if Settings.get("RaceTurnOnV4") then V4.turnOn() end
    if Settings.get("RaceBuyGear") and Common.every("V4BuyGear", 2) then V4.buyGear() end
    if Settings.get("RaceChooseGear") and Common.every("V4Gear", 2) then V4.chooseGear() end
    if Settings.get("RaceNoFog") and Common.every("V4Fog", 5) then V4.noFog() end
    if Settings.get("RaceResetCharacter") and V4.borderUp() and Common.every("V4Reset", 1) then
        local humanoid = Player.humanoid()
        if humanoid and humanoid.Health > 0 then humanoid.Health = 0 end
    end
end

function V4.start()
    Loop.start("RaceV4", 0.5, function() pcall(V4.step) end)
end

function V4.reset()
    search:reset()
end

return V4
