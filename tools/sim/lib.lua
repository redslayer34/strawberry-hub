--=============================================================================
-- SIM — a fake Blox Fruits game to replay a real case without playing it
--=============================================================================
--  Runs after tools/stubs.lua and the bundle (tools/sim.py assembles them).
--  A scenario builds a world (SIM.world), scripts the server (SIM.on /
--  SIM.onNet / SIM.hooks), starts the hub's engines (SIM.start) and runs
--  simulated time (SIM.run). The report lists every status the hub showed,
--  and the incidents: stuck, flapping, errors, deaths, unhandled remotes.
--
--  Simulated time: os.clock and os.time follow SIM.now, so every throttle,
--  rest and cooldown in the hub behaves as in game. One step = dt seconds:
--  the clock moves, Heartbeat fires (Movement and Boat move), every waiting
--  loop runs once (stepTasks), then the scenario's events.
--=============================================================================

SIM = {
    now = 1000,
    dt = 0.25,
    damage = 25,          -- health a mob loses per RegisterHit
    respawnAfter = 3,     -- seconds dead before the character respawns
    stuckAfter = 60,      -- same status this long = stuck
    flapCount = 8,        -- A, B, A, B... this many changes = flapping
    handlers = {},        -- CommF_ action -> function(...)
    hooks = {},           -- prompt(prompt), click(detector), hit(rig, firstPart)
    inventory = {},       -- { Name, Type, Count } as getInventory returns them
    timeline = {},
    incidents = {},
    unhandled = {},
    expects = {},
    notes = {},
}

local realTime = os.time
os.clock = function() return SIM.now end
os.time = function(t)
    if t then return realTime(t) end
    return 1700000000 + math.floor(SIM.now)
end

local Services = require("Core.Services")
local Settings = require("Core.Settings")
local Loop = require("Core.Loop")
local Movement = require("Game.Movement")
local Farm = require("Features.Farm")

local rs = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local lighting = game:GetService("Lighting")
local heartbeat = game:GetService("RunService").Heartbeat

SIM.SEA_PLACES = { 2753915549, 4442272183, 7449423635 }

---------------------------------------------------------------------------
-- Small builders
---------------------------------------------------------------------------

local function clear(instance)
    for _, child in ipairs(instance:GetChildren()) do child.Parent = nil end
end

function SIM.folder(name, parent)
    return parent:FindFirstChild(name) or newInstance("Folder", name, parent)
end

function SIM.part(name, position, parent, className)
    local p = newInstance(className or "Part", name, parent)
    p.Position = position
    p.Size = Vector3.new(2, 2, 1)
    p.CanCollide = true
    return p
end

-- A path of folders under `root` ("Map.Haunted Castle.Tablet").
function SIM.path(root, path)
    local node = root
    for name in string.gmatch(path, "[^%.]+") do node = SIM.folder(name, node) end
    return node
end

local function moduleScript(name, parent, value)
    local m = newInstance("ModuleScript", name, parent)
    m.ModuleValue = value
    return m
end

function SIM.note(text)
    SIM.notes[#SIM.notes + 1] = string.format("[%7.1fs] %s", SIM.elapsed(), text)
end

function SIM.elapsed()
    return SIM.now - (SIM.startedAt or SIM.now)
end

local function incident(kind, text)
    local line = string.format("[%7.1fs] %s: %s", SIM.elapsed(), kind, text)
    SIM.incidents[#SIM.incidents + 1] = line
end
SIM.incident = incident

---------------------------------------------------------------------------
-- Mobs and combat
---------------------------------------------------------------------------

-- A mob (or boss) in workspace.Enemies. opts: { maxHealth, parent }.
function SIM.spawn(name, position, health, opts)
    opts = opts or {}
    local model = newInstance("Model", name, opts.parent or SIM.folder("Enemies", workspace))
    local humanoid = newInstance("Humanoid", "Humanoid", model)
    humanoid.MaxHealth = opts.maxHealth or health or 100
    humanoid.Health = health or humanoid.MaxHealth
    SIM.part("HumanoidRootPart", position, model)
    SIM.part("Head", position + Vector3.new(0, 1.5, 0), model)
    SIM.part("UpperTorso", position, model)
    model.WorldPivot = CFrame.new(position)
    return model
end

local dying = {}
local skillFrames = {}   -- "tool/key" -> { frame, readyAt }

local function hurt(rig, amount)
    local humanoid = rig and rig:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    if SIM.hooks.hit and SIM.hooks.hit(rig) == false then return end
    humanoid.Health = math.max(0, humanoid.Health - amount)
    if humanoid.Health <= 0 then
        dying[#dying + 1] = { rig = rig, at = SIM.now + 0.5 }
        if SIM.hooks.died then SIM.hooks.died(rig) end
    end
end

-- RegisterHit(firstPart, { {rig, part}, ... }): the first part's rig and
-- every listed rig lose SIM.damage.
local function onRegisterHit(firstPart, rest)
    local seen = {}
    local function one(rig)
        if rig and not seen[rig] then
            seen[rig] = true
            hurt(rig, SIM.damage)
        end
    end
    if typeof(firstPart) == "Instance" then one(firstPart.Parent) end
    for _, pair in ipairs(type(rest) == "table" and rest or {}) do
        if type(pair) == "table" then one(pair[1]) end
    end
end

---------------------------------------------------------------------------
-- The world
---------------------------------------------------------------------------

local function resets()
    clearTasks()
    Loop.stopAll()
    for _, name in ipairs({
        "Core.Services", "Core.Settings", "Game.Enemies", "Game.Bring", "Game.Movement", "Game.Quests",
        "Game.Router", "Game.Pads", "Game.Regions", "Game.TeleportTag", "Game.IslandLoader", "Game.Boat",
        "Features.PlayerTweaks", "Features.Stack.Common",
    }) do
        local module = require(name)
        if type(module) == "table" and module.reset then pcall(module.reset) end
    end
end

-- profile = {
--   sea = 3, level = 2550, beli = 0, fragments = 0, race = "Human",
--   position = Vector3, inventory = { { Name = "Bones", Type = "Material", Count = 500 } },
--   clock = 12 (Lighting.ClockTime), moon = 5 (MoonPhase attribute),
--   settings = { Weapon = "Melee", ... } (hub settings to set),
-- }
function SIM.world(profile)
    profile = profile or {}
    clear(workspace)
    clear(rs)
    clear(players)
    resets()
    WARNINGS = {}
    SIM.timeline, SIM.incidents, SIM.unhandled, SIM.notes, SIM.expects = {}, {}, {}, {}, {}
    SIM.handlers, SIM.hooks, dying = {}, {}, {}
    skillFrames, SIM.presses = {}, {}
    SIM.inventory = profile.inventory or {}
    SIM.profile = profile
    game.PlaceId = SIM.SEA_PLACES[profile.sea or 3]

    SIM.folder("Enemies", workspace)
    SIM.folder("Map", workspace)
    SIM.folder("NPCs", workspace)
    SIM.folder("Boats", workspace)
    SIM.path(workspace, "_WorldOrigin.Locations")
    SIM.path(workspace, "_WorldOrigin.EnemySpawns")
    local characters = SIM.folder("Characters", workspace)

    local player = newInstance("Player", "Tester", players)
    player.UserId = 1
    players.LocalPlayer = player
    newInstance("Backpack", "Backpack", player)
    local data = newInstance("Folder", "Data", player)
    local function value(class, name, v) local x = newInstance(class, name, data) x.Value = v return x end
    value("IntValue", "Level", profile.level or 2550)
    value("IntValue", "Beli", profile.beli or 0)
    value("IntValue", "Fragments", profile.fragments or 0)
    value("StringValue", "Race", profile.race or "Human")
    value("StringValue", "LastSpawnPoint", profile.spawnPoint or "")
    value("StringValue", "DevilFruit", profile.fruit or "")
    newInstance("BoolValue", "DataLoaded", player)
    local gui = newInstance("PlayerGui", "PlayerGui", player)
    local main = newInstance("ScreenGui", "Main", gui)
    newInstance("Frame", "Quest", main).Visible = false
    newInstance("Frame", "TopHUDList", main)
    newInstance("Frame", "Notifications", gui)

    SIM.spawnAt = profile.position or Vector3.new(0, 20, 0)
    SIM.respawn()

    -- Remotes: CommF_ goes through SIM.handlers.
    local remotes = SIM.folder("Remotes", rs)
    local commF = newInstance("RemoteFunction", "CommF_", remotes)
    commF.OnInvoke = function(action, ...)
        local handler = SIM.handlers[action]
        if handler then return handler(...) end
        if action == "getInventory" then return SIM.inventory end
        SIM.unhandled[tostring(action)] = (SIM.unhandled[tostring(action)] or 0) + 1
        return nil
    end
    SIM.commF = commF
    newInstance("RemoteEvent", "CommE", remotes)

    local modules = SIM.folder("Modules", rs)
    moduleScript("CombatUtil", modules, {
        GetRigOfHitPart = function(_, hitPart) return hitPart.Parent end,
        IsVulnerable = function(_, rig) return not rig.Invulnerable end,
        IsGunReloading = function() return false end,
    })
    local net = moduleScript("Net", modules, nil)
    newInstance("RemoteEvent", "RE/RegisterAttack", net)
    local hit = newInstance("RemoteEvent", "RE/RegisterHit", net)
    hit.OnFire = onRegisterHit
    net.ModuleValue = {
        RemoteEvent = function(_, name) return net:FindFirstChild("RE/" .. name) end,
    }
    SIM.net = net
    moduleScript("GuideModule", rs, { Data = { QuestData = nil, NPCList = {} } })
    moduleScript("Quests", rs, {})

    lighting.ClockTime = profile.clock or 12
    lighting:SetAttribute("MoonPhase", profile.moon or 1)

    -- Executor functions the hub calls.
    fireproximityprompt = function(prompt, ...)
        SIM.note("prompt: " .. prompt:GetFullName())
        if SIM.hooks.prompt then SIM.hooks.prompt(prompt, ...) end
    end
    fireclickdetector = function(detector, ...)
        if SIM.hooks.click then SIM.hooks.click(detector, ...) end
    end
    sethiddenproperty = function() end

    for key, v in pairs(profile.settings or {}) do Settings.set(key, v) end
    -- Respawn teleports and portals need a real map: off unless asked.
    if profile.resetTeleport ~= true then Settings.set("ResetTeleport", false) end
    return player
end

-- A fresh character at SIM.spawnAt (called on death after respawnAfter).
function SIM.respawn()
    local player = players.LocalPlayer
    local old = player.Character
    if old then old.Parent = nil end
    local character = newInstance("Model", "Tester", SIM.folder("Characters", workspace))
    local humanoid = newInstance("Humanoid", "Humanoid", character)
    humanoid.MaxHealth = 100
    humanoid.Health = 100
    SIM.part("HumanoidRootPart", SIM.spawnAt, character)
    newInstance("NumberValue", "Stun", character).Value = 0
    newInstance("NumberValue", "Energy", character).Value = 100
    player.Character = character
    SIM.deadSince = nil
    return character
end

function SIM.character() return players.LocalPlayer.Character end
function SIM.hrp() return SIM.character() and SIM.character():FindFirstChild("HumanoidRootPart") end
function SIM.humanoid() return SIM.character() and SIM.character():FindFirstChildOfClass("Humanoid") end

-- CommF_ action handler: SIM.on("GuitarPuzzleProgress", function(step) ... end).
function SIM.on(action, fn) SIM.handlers[action] = fn end

-- A Modules.Net remote ("RF/Craft", "RF/DragonHunter"...), answered by fn.
function SIM.onNet(name, fn)
    local remote = SIM.net:FindFirstChild(name)
        or newInstance(name:sub(1, 2) == "RE" and "RemoteEvent" or "RemoteFunction", name, SIM.net)
    if remote.ClassName == "RemoteEvent" then remote.OnFire = fn else remote.OnInvoke = fn end
    return remote
end

-- Inventory helpers (getInventory answers).
function SIM.give(name, count, kind)
    for _, item in ipairs(SIM.inventory) do
        if item.Name == name then
            item.Count = (item.Count or 0) + (count or 1)
            return item
        end
    end
    local item = { Name = name, Type = kind or "Material", Count = count or 1 }
    SIM.inventory[#SIM.inventory + 1] = item
    return item
end

function SIM.take(name, count)
    for index, item in ipairs(SIM.inventory) do
        if item.Name == name then
            item.Count = (item.Count or 0) - (count or 1)
            if item.Count <= 0 then table.remove(SIM.inventory, index) end
            return true
        end
    end
    return false
end

-- A HUD timer (PrehistoricRaidTimer, RaidTimer...).
function SIM.hud(name, visible)
    local list = players.LocalPlayer.PlayerGui.Main.TopHUDList
    local timer = list:FindFirstChild(name) or newInstance("Frame", name, list)
    timer.Visible = visible
    return timer
end

-- An NPC in workspace.NPCs.
function SIM.npc(name, position)
    local model = newInstance("Model", name, SIM.folder("NPCs", workspace))
    SIM.part("HumanoidRootPart", position, model)
    SIM.part("Head", position + Vector3.new(0, 1.5, 0), model)
    model.WorldPivot = CFrame.new(position)
    return model
end

---------------------------------------------------------------------------
-- Skills (the skill bar and the key presses)
---------------------------------------------------------------------------

SIM.SKILL_COOLDOWN = 3
SIM.presses = {}

-- A tool the character owns (in the Backpack), with its skill bar.
-- SIM.tool("Combat", "Melee", { "Z", "X", "C" })
function SIM.tool(name, tooltip, keys)
    local player = players.LocalPlayer
    local tool = newInstance("Tool", name, player.Backpack)
    tool.ToolTip = tooltip
    local skills = SIM.folder("Skills", player.PlayerGui.Main)
    local bar = SIM.folder(name, skills)
    for _, key in ipairs(keys or {}) do
        local frame = newInstance("Frame", key, bar)
        newInstance("TextLabel", "Title", frame).TextColor3 = Color3.new(1, 1, 1)
        newInstance("Frame", "Cooldown", frame).Size = UDim2.new(0, 0, 1, -1)
        skillFrames[name .. "/" .. key] = { frame = frame, readyAt = 0 }
    end
    return tool
end

-- VirtualInputManager: a key press uses the equipped tool's skill (aimed
-- at the hub's AimHook target), puts it on cooldown and calls
-- SIM.hooks.skill(key, aim, tool).
local input = game:GetService("VirtualInputManager")
input.SendKeyEvent = function(_, down, key)
    if not down then return end
    local character = SIM.character()
    local tool = character and character:FindFirstChildOfClass("Tool")
    local name = tostring(key and key.Name or key)
    local entry = tool and skillFrames[tool.Name .. "/" .. name]
    if not entry then return end
    if SIM.now < entry.readyAt then return end
    entry.readyAt = SIM.now + SIM.SKILL_COOLDOWN
    entry.frame.Cooldown.Size = UDim2.new(0.5, 0, 1, -1)
    local aim = require("Game.AimHook").target
    SIM.presses[#SIM.presses + 1] = { key = name, tool = tool.Name, at = SIM.now, aim = aim }
    if SIM.hooks.skill then SIM.hooks.skill(name, aim, tool) end
end

local function cooldowns()
    for _, entry in pairs(skillFrames) do
        if SIM.now >= entry.readyAt then entry.frame.Cooldown.Size = UDim2.new(0, 0, 1, -1) end
    end
end

---------------------------------------------------------------------------
-- Boats and seats
---------------------------------------------------------------------------

-- BuyBoat answers with a boat next to this sea's dealer (Game/Boat.DEALERS).
function SIM.enableBoats()
    local Boat = require("Game.Boat")
    SIM.on("BuyBoat", function(name)
        local old = require("Game.Boat").mine()
        if old then old.Parent = nil end
        local dealer = Boat.DEALERS[SIM.profile.sea or 3] or Vector3.new(0, 0, 0)
        local model = newInstance("Model", tostring(name), SIM.folder("Boats", workspace))
        local owner = newInstance("ObjectValue", "Owner", model)
        owner.Value = players.LocalPlayer.Name
        newInstance("IntValue", "Humanoid", model).Value = 1000
        local seat = SIM.part("VehicleSeat", Vector3.new(dealer.X + 30, 10, dealer.Z), model, "VehicleSeat")
        model.WorldPivot = CFrame.new(seat.Position)
        SIM.note("server: boat " .. tostring(name) .. " bought")
        return true
    end)
end

local leftSeatAt = -math.huge

-- Seats: touching one sits the character (Movement's "stand up" clears it),
-- and a seated character rides along with its seat.
local function seats()
    local humanoid, hrp = SIM.humanoid(), SIM.hrp()
    if not humanoid or not hrp or humanoid.Health <= 0 then return end
    local seat = humanoid.SeatPart
    if seat then
        if humanoid.Sit == false or not seat.Parent then
            humanoid.SeatPart = nil
            leftSeatAt = SIM.now
            return
        end
        hrp.Position = seat.Position + Vector3.new(0, 2, 0)
        hrp.CFrame = CFrame.new(hrp.Position)
        return
    end
    if SIM.now - leftSeatAt < 2 then return end
    for _, boat in ipairs(SIM.folder("Boats", workspace):GetChildren()) do
        for _, part in ipairs(boat:GetDescendants()) do
            if (part.ClassName == "VehicleSeat" or part.ClassName == "Seat")
                and (part.Position - hrp.Position).Magnitude <= 6 then
                humanoid.SeatPart = part
                humanoid.Sit = true
                SIM.note("sat on " .. part:GetFullName())
                return
            end
        end
    end
end
SIM.seats = seats

---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------

-- The hub's engines a scenario usually needs (settings set before).
function SIM.start(opts)
    opts = opts or {}
    Movement.start()
    if opts.boat ~= false then require("Game.Boat").start() end
    if opts.farm ~= false then Farm.start() end
    for _, fn in ipairs(opts.extra or {}) do fn() end
end

function SIM.status()
    local ok, text = pcall(Farm.status)
    return ok and text or ("status error: " .. tostring(text))
end

local lastStatus, statusSince, recent, stuckReported = nil, nil, {}, {}
local warningsSeen = 0

local function record(status)
    if status == lastStatus then
        if SIM.now - statusSince >= SIM.stuckAfter and not stuckReported[status .. statusSince] then
            stuckReported[status .. statusSince] = true
            incident("STUCK", string.format("%q for %ds", status, SIM.stuckAfter))
        end
        return
    end
    SIM.timeline[#SIM.timeline + 1] = string.format("[%7.1fs] %s", SIM.elapsed(), status)
    lastStatus, statusSince = status, SIM.now
    recent[#recent + 1] = status
    if #recent > SIM.flapCount then table.remove(recent, 1) end
    if #recent == SIM.flapCount then
        local a, b = recent[1], recent[2]
        local flapping = a ~= b
        for index = 3, #recent do
            if recent[index] ~= (index % 2 == 1 and a or b) then flapping = false break end
        end
        if flapping then
            incident("FLAPPING", string.format("%q <-> %q", a, b))
            recent = {}
        end
    end
end

-- opts = { seconds, dt, events = { { at = 5, fn = function() end } },
--          untilFn = function() return done end, every = function(t) end }
-- Returns true when untilFn became true.
function SIM.run(opts)
    local dt = opts.dt or SIM.dt
    SIM.startedAt = SIM.startedAt or SIM.now
    local stopAt = SIM.now + (opts.seconds or 60)
    local events = {}
    for _, event in ipairs(opts.events or {}) do events[#events + 1] = event end
    local base = SIM.elapsed()
    while SIM.now < stopAt do
        SIM.now = SIM.now + dt
        local ok, err = pcall(function()
            heartbeat:Fire(dt)
            seats()
            cooldowns()
            stepTasks()
        end)
        if not ok then incident("ERROR", tostring(err)) end
        for index = #dying, 1, -1 do
            if SIM.now >= dying[index].at then
                dying[index].rig.Parent = nil
                table.remove(dying, index)
            end
        end
        local humanoid = SIM.humanoid()
        if humanoid and humanoid.Health <= 0 then
            SIM.deadSince = SIM.deadSince or SIM.now
            if SIM.now - SIM.deadSince >= SIM.respawnAfter then
                SIM.note("respawn")
                SIM.respawn()
            end
        end
        local hrp = SIM.hrp()
        if hrp and hrp.Position.Y < -200 then incident("FELL", "character under the map at " .. tostring(hrp.Position)) end
        for index = #events, 1, -1 do
            if SIM.elapsed() - base >= events[index].at then
                local event = table.remove(events, index)
                local okEvent, errEvent = pcall(event.fn)
                if not okEvent then incident("SCENARIO ERROR", tostring(errEvent)) end
            end
        end
        if opts.every then pcall(opts.every, SIM.elapsed()) end
        record(SIM.status())
        while #WARNINGS > warningsSeen do
            warningsSeen = warningsSeen + 1
            incident("WARN", WARNINGS[warningsSeen])
        end
        if opts.untilFn and opts.untilFn() then return true end
    end
    return false
end

function SIM.expect(name, condition, detail)
    SIM.expects[#SIM.expects + 1] = { name = name, ok = condition and true or false, detail = detail }
end

-- Prints the report; exits 1 when an expectation failed.
function SIM.finish(name)
    local failed = 0
    print(string.format("=== scenario %s (%.0f simulated seconds) ===", name or "?", SIM.elapsed()))
    print("-- timeline (" .. #SIM.timeline .. " statuses)")
    for _, line in ipairs(SIM.timeline) do print(line) end
    if #SIM.notes > 0 then
        print("-- notes")
        for index = 1, math.min(#SIM.notes, 60) do print(SIM.notes[index]) end
        if #SIM.notes > 60 then print("  ... " .. (#SIM.notes - 60) .. " more") end
    end
    print("-- incidents (" .. #SIM.incidents .. ")")
    for _, line in ipairs(SIM.incidents) do print(line) end
    local unhandled = {}
    for action, count in pairs(SIM.unhandled) do unhandled[#unhandled + 1] = action .. " x" .. count end
    table.sort(unhandled)
    if #unhandled > 0 then print("-- remotes nobody answered: " .. table.concat(unhandled, ", ")) end
    print("-- expectations")
    for _, entry in ipairs(SIM.expects) do
        if not entry.ok then failed = failed + 1 end
        print(string.format("  %s %s%s", entry.ok and "PASS" or "FAIL", entry.name,
            entry.detail ~= nil and ("  -- " .. tostring(entry.detail)) or ""))
    end
    print(string.format("RESULT %s: %s (%d expectation(s) failed, %d incident(s))", name or "?",
        failed == 0 and "PASS" or "FAIL", failed, #SIM.incidents))
    if failed > 0 then os.exit(1) end
end
