--=============================================================================
-- ROUTER — the reference's (Banana Cat Hub) way to far goals
--=============================================================================
--  Movement asks the Router every frame. Two things come first, always:
--
--    temple      Sea 3: out of the Temple of Time, its own way back
--    submarine   Sea 3: the only way to and from the Submerged Island
--
--  Then every way that fits is given an estimated time (its own cost plus
--  the flight from where it lands, Router.COST) and the one that arrives
--  first is taken; flying is a way too:
--
--    gateway     opt-in: the Portal fruit's Gateway to the island nearest the
--                goal (fruit level 200+, C skill ready)
--    entrance    a portal (requestEntrance): an unlocked point within FAR
--                studs of the goal that lands CLOSER_BY studs closer to it
--    exit        Teddy Hub's: out of the Underwater City by the Whirlpool,
--                off the Cursed Ship by the Graveyard
--    celestial   Sea 3: the Celestial Domain's own transports
--    mirror      Sea 3: the Cake Loaf's big mirror
--    respawn     "Reset teleport": move the spawn point to the goal's island,
--                then reset the character; never while holding something
--                death would lose (Router.PROTECTED)
--    direct      fly
--
--  The gateway, the portals and the reset only count when the goal is
--  farther than the "Teleport when farther than" setting.
--
--  A portal is called three ways, the one that worked first next time:
--    banana      from where the player stands, every EXACT_EVERY seconds
--                (Banana Cat Hub's way)
--    placed      the character set on the point while calling (Teddy Hub's)
--    alt         Teddy Hub's own position for the point, placed
--  A portal where no way works cools down, so the same trip goes on with the
--  reset teleport; FAILS_TO_LOCK misses in a row pause it for LOCK_TIME.
--=============================================================================

local Entrances = require("Game.Entrances")
local Gateway = require("Game.Gateway")
local Player = require("Core.Player")
local Regions = require("Game.Regions")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Router = {}

Router.SNAP = 150              -- studs: closer goals are simply set
Router.FAR = 3000              -- the reference's distance for every shortcut
Router.TOO_CLOSE = 1000        -- studs: Test portals skips a point this close
Router.MOVED = 300             -- studs the character must move for a jump to count
Router.EXACT_EVERY = 0.1       -- seconds between two calls, as the reference
Router.EXACT_TIME = 15         -- seconds of calls without a move before giving up
Router.COOLDOWN = 4            -- seconds before the same shortcut is tried again
Router.FAILS_TO_LOCK = 2       -- misses in a row before a shortcut is paused
Router.LOCK_TIME = 120         -- seconds a paused shortcut stays paused
Router.REPLAN_MOVE = 300       -- studs the goal may move before re-planning
Router.REPLAN_EVERY = 5        -- seconds a flight is kept before looking again
Router.DOCK_RADIUS = 8         -- the reference calls at 8 studs from a dock
Router.VERIFY_STEPS = 24       -- x 0.25 s to see a transport happen
Router.RESPAWN_STEPS = 60      -- x 0.25 s to wait for the new character
Router.MAX_RESPAWNS = 5        -- respawns for one goal, as the reference
Router.GATEWAY_STEPS = 25      -- x 0.2 s to land after the Gateway
Router.GATEWAY_ARRIVED = 500
Router.CLOSER_BY = 1000        -- studs a portal must bring you closer to the goal
Router.BANANA_TIME = 1.5       -- seconds of Banana-way calls during a trip
Router.TEST_BANANA_TIME = 5    -- the same, in the portal test
Router.PLACED_TRIES = 3        -- Teddy's way: calls, PLACED_EVERY seconds apart
Router.PLACED_EVERY = 0.15
Router.PLACED_VERIFY = 1       -- seconds after the calls: still there = it worked
Router.PLACED_ARRIVED = 2000   -- studs from the point that count as there
Router.DEFAULT_DISTANCE = 2000

-- Seconds each way costs before the flight from where it lands.
Router.COST = { entrance = 1.5, exit = 1.5, gateway = 4, celestial = 3, mirror = 3, respawn = 10 }

Router.WAYS = {
    banana = "Banana way",
    placed = "Teddy way (placed on the point)",
    alt = "Teddy position",
}
Router.WAY_ORDER = { "banana", "placed", "alt" }

-- Teddy Hub's exits: inside `center` (radius) with the goal outside, the
-- named point takes you out.
Router.EXITS = {
    [1] = { name = "Underwater City", point = "Whirlpool",
        center = Vector3.new(61163.85, 11.68, 1819.78), radius = 3000 },
    [2] = { name = "Cursed Ship", point = "Graveyard",
        center = Vector3.new(923.21, 126.98, 32852.83), radius = 3000 },
}

-- Lost on death (Teddy Hub's list): no reset teleport while one is held.
Router.PROTECTED = { "Fist of Darkness", "God's Chalice", "Sweet Chalice", "Hallow Essence", "Special Microchip" }
Router.PROTECTED_SEA = {
    [2] = { "Flower 1", "Flower 2", "Flower 3", "Blue Flower", "Yellow Flower", "Red Flower" },
    [3] = { "Red Key" },
}

-- Sea 3 Submerged Island (reference): the island, the worker who sends you
-- there, the dock to leave from, and where leaving lands.
Router.ISLAND = Vector3.new(11538.599609375, -2154.7021484375, 9827.3125)
Router.ISLAND_RADIUS = 3000
Router.WORKER = Vector3.new(-16269.4082, 23.9799957, 1371.66235)
Router.DOCK = Vector3.new(11427.9189, -2156.36401, 9726.24023)
Router.TIKI = Vector3.new(-16456.5, 530.3, 436.2)

-- Sea 3 Temple of Time (reference): leaving it means standing on its exit
-- point and asking the game to send you back.
Router.TEMPLE = Vector3.new(28609.392578125, 14896.533203125, 106.4216537475586)
Router.TEMPLE_RADIUS = 3000

-- Sea 3 Cake Loaf: the big mirror leads to this place in the sky.
Router.MIRROR_INSIDE = Vector3.new(-1990.67, 4532.97, -14973.67)
Router.MIRROR_RADIUS = 1000

-- Sea 3 Celestial Domain: its NPC, and how close to it the transport works.
Router.CELESTIAL = "Celestial Domain"
Router.CELESTIAL_NPC = "Celestial Member"
Router.CELESTIAL_RADIUS = 300

local route, note, lastTrip
local bestWay = {}             -- [point name] = the way that worked
local busy, justJumped = false, false
local confirmed, lastUsed = {}, {}
local failures, lockedAt, attempts = {}, {}, {}
local respawns = { goal = nil, count = 0 }

---------------------------------------------------------------------------
-- Shortcut memory
---------------------------------------------------------------------------

local function isLocked(name)
    local since = lockedAt[name]
    if not since then return false end
    if os.clock() - since >= Router.LOCK_TIME then
        lockedAt[name] = nil
        failures[name] = 0
        return false
    end
    return true
end

local function coolingDown(name)
    return os.clock() - (lastUsed[name] or -math.huge) < Router.COOLDOWN
end

local function usable(name)
    return not isLocked(name) and not coolingDown(name)
end

local function recordResult(name, ok, detail)
    attempts[name] = detail
    if ok then
        confirmed[name] = true
        failures[name] = 0
        lockedAt[name] = nil
        return
    end
    failures[name] = (failures[name] or 0) + 1
    if failures[name] >= Router.FAILS_TO_LOCK then
        lockedAt[name] = os.clock()
    end
end

local function within(position, center, radius)
    return (position - center).Magnitude <= radius
end

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------

-- The unlocked point nearest the goal, within FAR studs of it and landing
-- CLOSER_BY studs closer to it than `here`. Returns the point, or nil and
-- why none was taken.
function Router.entranceFor(here, goal)
    local points = Entrances.available()
    local toGoalNow = (goal - here).Magnitude
    local best, bestDistance, why
    for _, point in ipairs(points) do
        local toGoal = (goal - point.position).Magnitude
        if toGoal <= Router.FAR then
            if toGoal + Router.CLOSER_BY > toGoalNow then
                why = why or (point.name .. " would not bring you closer")
            elseif isLocked(point.name) then
                why = point.name .. " paused (" .. tostring(attempts[point.name]) .. ")"
            elseif coolingDown(point.name) then
                why = point.name .. " just tried"
            elseif not bestDistance or toGoal < bestDistance then
                best, bestDistance = point, toGoal
            end
        end
    end
    if not best and not why then
        if #points == 0 then
            why = "no unlocked portal in sea " .. tostring(Player.sea() or "?")
        else
            why = "no portal near the goal"
        end
    end
    return best, why
end

-- Teddy Hub's exits: the point that takes you out of where you are, or nil.
function Router.exitFor(here, goal)
    local exit = Router.EXITS[Player.sea() or 0]
    if not exit or not within(here, exit.center, exit.radius) or within(goal, exit.center, exit.radius) then
        return nil
    end
    local point = Entrances.named(exit.point)
    if point and Entrances.confirmed(point) and usable(point.name) then return point, exit end
    return nil
end

local function holding(name)
    local character = Player.character()
    local player = Services.player()
    return (character and character:FindFirstChild(name) ~= nil)
        or (player ~= nil and Services.find(player, "Backpack." .. name) ~= nil)
end

local function unstoredFruit()
    local player = Services.player()
    local places = { Player.character(), player and player:FindFirstChild("Backpack") }
    for _, place in pairs(places) do
        for _, tool in ipairs(place:GetChildren()) do
            if tool:IsA("Tool") and tool.Name:find("Fruit", 1, true) then return tool.Name end
        end
    end
    return nil
end

local function inside(moduleName, fn)
    local ok, module = pcall(require, moduleName)
    if not ok or type(module) ~= "table" or type(module[fn]) ~= "function" then return false end
    local ran, result = pcall(module[fn])
    return ran and result == true
end

-- Why a reset teleport must not happen now (something death would lose,
-- or a place a reset would throw you out of), or nil.
function Router.resetBlocked()
    local names = {}
    for _, name in ipairs(Router.PROTECTED) do names[#names + 1] = name end
    for _, name in ipairs(Router.PROTECTED_SEA[Player.sea() or 0] or {}) do names[#names + 1] = name end
    for _, name in ipairs(names) do
        if holding(name) then return "holding " .. name end
    end
    local fruit = unstoredFruit()
    if fruit then return "holding " .. fruit .. " (not stored)" end
    local here = Player.position()
    if here and Player.sea() == 3 and within(here, Router.ISLAND, Router.ISLAND_RADIUS) then
        return "on the Submerged Island"
    end
    if inside("Features.Raids", "inRaid") then return "in a raid" end
    if inside("Features.Dungeon", "inside") then return "in a dungeon" end
    return nil
end

function Router.teleportDistance()
    return tonumber(Settings.get("TeleportDistance")) or Router.DEFAULT_DISTANCE
end

local function isInterior(part)
    return part ~= nil and (part.Name == Router.CELESTIAL .. " (Interior)" or part.Name == Router.CELESTIAL .. " <Interior>")
end

local function isDomain(part)
    return part ~= nil and part.Name == Router.CELESTIAL
end

-- The nearest ready "Celestial Member" NPC (the reference's DetectNpcOni).
local function celestialMember()
    local best, bestDistance
    local folders = { workspace:FindFirstChild("NPCs"), Services.replicated():FindFirstChild("NPCs") }
    for _, folder in pairs(folders) do
        for _, npc in ipairs(folder:GetChildren()) do
            local root = npc:FindFirstChild("HumanoidRootPart")
            if root and npc:GetAttribute("NPCLoaded") and npc:GetAttribute("NPCReady")
                and npc:GetAttribute("DisplayName") == Router.CELESTIAL_NPC then
                local distance = Player.distanceTo(root.Position)
                if not bestDistance or distance < bestDistance then best, bestDistance = npc, distance end
            end
        end
    end
    return best
end

local function celestialPlan(here, goal)
    local hereIn, goalIn = Regions.containing(here), Regions.containing(goal)
    local hereNear, goalNear = Regions.nearest(here), Regions.nearest(goal)
    local function viaMember(step)
        local npc = celestialMember()
        if not npc then return nil end
        local dock = (npc.HumanoidRootPart.CFrame * CFrame.new(0, 0, 20)).Position
        return { kind = "celestial", step = step, name = "Celestial Domain transport", dock = dock,
            dockRadius = Router.CELESTIAL_RADIUS }
    end
    if isDomain(goalIn) and not isDomain(hereIn) then return viaMember("temple") end
    if isInterior(goalNear) then
        if isDomain(hereIn) then
            return { kind = "celestial", step = "interior", name = "Celestial Domain interior" }
        end
        if not hereIn or (not isDomain(hereIn) and not isInterior(hereNear)) then
            return viaMember("temple+interior")
        end
    end
    if isInterior(hereNear) and not isInterior(goalNear) then
        return { kind = "celestial", step = "leave", name = "leaving the Celestial Domain" }
    end
    if isDomain(hereIn) and not isDomain(goalIn) then
        return { kind = "celestial", step = "leave", name = "leaving the Celestial Domain" }
    end
    return nil
end

local function mirrorPlan(here, goal)
    local mirror = Services.find(workspace, "Map.CakeLoaf.BigMirror.Main")
    if not mirror then return nil end
    if within(goal, Router.MIRROR_INSIDE, Router.MIRROR_RADIUS)
        and not within(here, Router.MIRROR_INSIDE, Router.MIRROR_RADIUS) then
        return { kind = "mirror", name = "Cake mirror", dock = mirror.Position, part = mirror }
    end
    return nil
end

local function respawnsLeft(goal)
    if respawns.goal and within(goal, respawns.goal, Router.REPLAN_MOVE) then
        return respawns.count < Router.MAX_RESPAWNS
    end
    return true
end

-- The Temple of Time exit and the submarine: taken whenever they apply.
local function mandatoryPlan(here, goal)
    if Player.sea() ~= 3 then return nil end
    local inTemple = within(here, Router.TEMPLE, Router.TEMPLE_RADIUS)
    local fromIsland = within(here, Router.ISLAND, Router.ISLAND_RADIUS)
    local toIsland = within(goal, Router.ISLAND, Router.ISLAND_RADIUS)
    if inTemple and not within(goal, Router.TEMPLE, Router.TEMPLE_RADIUS) then
        return { kind = "temple", name = "Temple of Time exit", dock = Router.TEMPLE }
    elseif toIsland and not fromIsland then
        return { kind = "submarine", name = "Submarine", dock = Router.WORKER, enter = true }
    elseif fromIsland and not toIsland then
        return { kind = "submarine", name = "Submarine", dock = Router.DOCK, enter = false }
    end
    return nil
end

-- What to do to reach `goal` from `here`: the mandatory ways, else the way
-- that arrives first at `speed` studs per second.
function Router.plan(here, goal, speed)
    speed = math.max(tonumber(speed) or tonumber(Settings.get("TweenSpeed")) or 300, 1)
    local distance = (goal - here).Magnitude
    local direct = { kind = "direct" }
    local plan = direct

    if distance < Router.SNAP then
        plan = direct
    elseif not Player.sea() then
        direct.reason = "sea unknown"
    else
        plan = mandatoryPlan(here, goal)
        if not plan then
            local far = distance >= Router.teleportDistance()
            local candidates, reasons = {}, {}
            local flyTime = distance / speed
            local mustTransport = false
            local function add(candidate, landing, cost)
                candidate.eta = cost + (landing - goal).Magnitude / speed
                candidates[#candidates + 1] = candidate
            end

            if far and Settings.get("PortalFruit") then
                local island = Gateway.islandNear(goal, Router.FAR)
                local key = island and ("Portal fruit to " .. island.name)
                if island and usable(key) and Gateway.ready(true) then
                    add({ kind = "gateway", name = key, island = island }, island.position, Router.COST.gateway)
                end
            end

            if far then
                local point, why = Router.entranceFor(here, goal)
                if point then
                    add({ kind = "entrance", name = point.name, point = point }, point.position, Router.COST.entrance)
                else
                    reasons[#reasons + 1] = why
                end
            end

            local exitPoint, exit = Router.exitFor(here, goal)
            if exitPoint then
                add({ kind = "entrance", name = exitPoint.name, point = exitPoint, exit = exit.name },
                    exitPoint.position, Router.COST.exit)
            end

            if Player.sea() == 3 then
                local special = celestialPlan(here, goal) or mirrorPlan(here, goal)
                if special and usable(special.name) then
                    mustTransport = true
                    local toDock = special.dock and (special.dock - here).Magnitude or 0
                    special.eta = toDock / speed + Router.COST[special.kind]
                    candidates[#candidates + 1] = special
                end
            end

            if far then
                if not Settings.get("ResetTeleport") then
                    reasons[#reasons + 1] = "reset teleport off"
                else
                    local blocked = Router.resetBlocked()
                    if blocked then
                        reasons[#reasons + 1] = "reset teleport skipped: " .. blocked
                    elseif respawnsLeft(goal) and Regions.shouldRespawn(here, goal) then
                        local spawn = Regions.respawnTarget(here, goal)
                        local name = spawn and ("respawn at " .. spawn.name)
                        if spawn and usable(name) then
                            add({ kind = "respawn", name = name, spawn = spawn }, spawn.position, Router.COST.respawn)
                        end
                    end
                end
            end

            local best
            for _, candidate in ipairs(candidates) do
                if not best or candidate.eta < best.eta then best = candidate end
            end
            if best and not mustTransport and best.eta >= flyTime then best = nil end
            if best then
                best.flyTime = flyTime
                plan = best
            else
                direct.reason = #reasons > 0 and table.concat(reasons, "; ") or nil
                plan = direct
            end
        end
    end

    plan.goal = goal
    plan.at = os.clock()
    return plan
end

---------------------------------------------------------------------------
-- Running a shortcut
---------------------------------------------------------------------------

local function waitUntil(steps, test, interval)
    for _ = 1, steps do
        task.wait(interval or 0.25)
        if test() then return true end
    end
    return false
end

local function near(position, radius)
    local here = Player.position()
    return here ~= nil and (here - position).Magnitude <= radius
end

local function netInvoke(name, ...)
    local remote = Services.find(Services.replicated(), "Modules.Net")
    remote = remote and remote:FindFirstChild(name)
    if not remote then return nil end
    local args = { n = select("#", ...), ... }
    local ok, result = pcall(function() return remote:InvokeServer((table.unpack or unpack)(args, 1, args.n)) end)
    return ok and result or nil
end

local actions = {}

-- The reference's loop: requestEntrance, wait EXACT_EVERY, again, until
-- the player has moved or `seconds` (EXACT_TIME) have passed. Returns
-- whether the player moved, how far, how many calls were made and the last
-- answer.
function Router.bananaLoop(point, seconds)
    seconds = seconds or Router.EXACT_TIME
    local start = Player.position()
    local function moved()
        local here = Player.position()
        if not here or not start then return 0 end
        return (here - start).Magnitude
    end
    local total = math.max(1, math.floor(seconds / Router.EXACT_EVERY + 0.5))
    local calls, answer = 0, nil
    for _ = 1, total do
        answer = Entrances.use(point)
        calls = calls + 1
        task.wait(Router.EXACT_EVERY)
        if moved() > Router.MOVED then return true, moved(), calls, answer end
    end
    return false, moved(), calls, answer
end

local function loopResult(ok, distance, calls, answer, seconds)
    if ok then return string.format("moved %d studs after %d calls", math.floor(distance), calls) end
    return string.format("no move after %g s (%d calls), answer %s", seconds or Router.EXACT_TIME, calls, tostring(answer))
end

-- Teddy Hub's way: the character set on the point (or its `alt`) while
-- calling, PLACED_TRIES times; still there PLACED_VERIFY seconds later (the
-- server did not pull it back) means the portal took it.
local function placedLoop(point, position)
    for _ = 1, Router.PLACED_TRIES do
        Entrances.use(point, position, true)
        task.wait(Router.PLACED_EVERY)
    end
    task.wait(Router.PLACED_VERIFY)
    return near(position, Router.PLACED_ARRIVED)
end

-- One way of calling a portal. Returns whether it worked and what happened.
function Router.tryWay(point, way, bananaTime)
    if way == "banana" then
        bananaTime = bananaTime or Router.BANANA_TIME
        local ok, distance, calls, answer = Router.bananaLoop(point, bananaTime)
        return ok, loopResult(ok, distance, calls, answer, bananaTime)
    end
    local position = way == "alt" and point.alt or point.position
    if not position then return false, "no Teddy position for this point" end
    local ok = placedLoop(point, position)
    return ok, ok and "arrived" or "pulled back"
end

-- The ways to try for `point`: the one that worked before first.
function Router.waysFor(point, fixedOrder)
    local list = {}
    local best = not fixedOrder and bestWay[point.name]
    if best then list[1] = best end
    for _, way in ipairs(Router.WAY_ORDER) do
        if way ~= best and (way ~= "alt" or point.alt) then list[#list + 1] = way end
    end
    return list
end

function actions.entrance(plan)
    local point = plan.point
    local started = os.clock()
    local tried = {}
    for _, way in ipairs(Router.waysFor(point)) do
        local ok, detail = Router.tryWay(point, way)
        if ok then
            bestWay[point.name] = way
            recordResult(point.name, true, nil)
            lastTrip = string.format("via %s (%s), %.1f s", point.name, Router.WAYS[way], os.clock() - started)
            return
        end
        tried[#tried + 1] = Router.WAYS[way] .. ": " .. detail
    end
    recordResult(point.name, false, "no way worked (" .. table.concat(tried, "; ") .. ")")
    lastTrip = point.name .. " portal did not work, reset teleport or flight next"
end

function actions.gateway(plan)
    if not Gateway.open(plan.island.name) then
        recordResult(plan.name, false, "the Gateway did not open")
        return
    end
    local ok = waitUntil(Router.GATEWAY_STEPS, function()
        return near(plan.island.position, Router.GATEWAY_ARRIVED)
    end, 0.2)
    recordResult(plan.name, ok, ok and "arrived" or "no arrival after the Gateway")
end

function actions.temple()
    Services.invoke("RaceV4Progress", "Check")
    Services.invoke("RaceV4Progress", "TeleportBack")
    waitUntil(Router.VERIFY_STEPS, function() return not near(Router.TEMPLE, Router.TEMPLE_RADIUS) end)
end

function actions.submarine(plan)
    if plan.enter then
        netInvoke("RF/SubmarineWorkerSpeak", "TravelToSubmergedIsland")
        Services.invoke("SetLastSpawnPoint", "SubmergedIsland")
        waitUntil(Router.VERIFY_STEPS * 2, function() return near(Router.ISLAND, Router.ISLAND_RADIUS) end)
    else
        netInvoke("RF/SubmarineTransportation", "GetAvailableLocations")
        netInvoke("RF/SubmarineTransportation", "InitiateTeleport", "Tiki Outpost")
        waitUntil(Router.VERIFY_STEPS * 2, function() return near(Router.TIKI, 1000) end)
    end
end

function actions.celestial(plan)
    local function transport(what) return netInvoke("RF/CelestialDomainTransportation", what) end
    if plan.step == "temple" or plan.step == "temple+interior" then
        transport("InitiateTeleportToTemple")
        local controller = Services.module("Controllers.MapServices.CelestialDomainController")
        if type(controller) == "table" and controller.LoadMap then pcall(controller.LoadMap, controller) end
        task.wait(1)
        if plan.step == "temple+interior" then transport("InitiateTeleportToInterior") end
    elseif plan.step == "interior" then
        transport("InitiateTeleportToInterior")
        task.wait(1)
    else
        transport("Leave")
        task.wait(1)
    end
end

function actions.mirror(plan)
    local hrp = Player.hrp()
    if firetouchinterest and hrp then
        pcall(firetouchinterest, hrp, plan.part, 0)
        pcall(firetouchinterest, hrp, plan.part, 1)
    end
    local ok = waitUntil(12, function() return near(Router.MIRROR_INSIDE, Router.MIRROR_RADIUS) end)
    recordResult(plan.name, ok, ok and "inside" or "the mirror did not take you in")
end

-- The reference's TweenBypass: the character's own LastSpawnPoint script is
-- switched off so it cannot put the old spawn point back, the spawn point
-- is moved, then the character is reset.
function actions.respawn(plan)
    if respawns.goal and within(plan.goal, respawns.goal, Router.REPLAN_MOVE) then
        respawns.count = respawns.count + 1
    else
        respawns.goal, respawns.count = plan.goal, 1
    end
    local character = Player.character()
    local script = character and character:FindFirstChild("LastSpawnPoint")
    if script then pcall(function() script.Disabled = true end) end
    Services.invoke("SetLastSpawnPoint", plan.spawn.name)
    if Player.data("LastSpawnPoint") ~= plan.spawn.name then
        if script then pcall(function() script.Disabled = false end) end
        recordResult(plan.name, false, "spawn point refused")
        return
    end
    local humanoid = Player.humanoid()
    if humanoid then humanoid.Health = 0 end
    local ok = waitUntil(Router.RESPAWN_STEPS, function()
        return Player.character() ~= character and Player.alive()
    end)
    if script and script.Parent then pcall(function() script.Disabled = false end) end
    recordResult(plan.name, ok, ok and "respawned" or "no new character")
    lastTrip = ok and ("reset teleport to " .. plan.spawn.name) or ("reset teleport to " .. plan.spawn.name .. " failed")
end

local function run(plan)
    busy = true
    lastUsed[plan.name] = os.clock()
    task.spawn(function()
        local started = os.clock()
        lastTrip = nil
        local ok, err = pcall(actions[plan.kind], plan)
        if not ok then warn("[Strawberry Hub] " .. plan.name .. ": " .. tostring(err)) end
        if plan.kind == "respawn" and lastTrip then
            lastTrip = string.format("%s, %.1f s", lastTrip, os.clock() - started)
        elseif not lastTrip then
            lastTrip = string.format("via %s, %.1f s", plan.name, os.clock() - started)
        end
        route = nil
        busy = false
        justJumped = true
    end)
end

-- Called by Movement each frame. Returns handled (true: a shortcut is
-- running, do not move this frame) and an optional Vector3 to fly to
-- instead of the goal (a dock, an NPC, the mirror).
function Router.update(here, goal, speed)
    if busy then return true end
    if not Settings.get("SmartTravel") then
        route, note = nil, nil
        return false
    end
    if (goal - here).Magnitude < Router.SNAP then
        route, note = nil, nil
        return false
    end
    if justJumped then
        -- Fly at least one frame between two shortcuts.
        justJumped = false
        route = nil
        return false
    end

    if not route or (route.goal - goal).Magnitude > Router.REPLAN_MOVE
        or (route.kind == "direct" and os.clock() - route.at >= Router.REPLAN_EVERY) then
        route = Router.plan(here, goal, speed)
    end

    if route.kind == "direct" then
        note = route.reason and ("flying: " .. route.reason) or nil
        return false
    end
    note = "via " .. route.name
    if route.eta and route.flyTime then
        note = string.format("%s, about %d s (flying: %d s)", note, math.ceil(route.eta), math.ceil(route.flyTime))
    end

    if route.dock and (here - route.dock).Magnitude > (route.dockRadius or Router.DOCK_RADIUS) then
        return false, route.dock
    end

    run(route)
    return true
end

-- Requests every unlocked point of this sea in turn and records what
-- happened. Returns false if a shortcut is already running.
function Router.testAll(onDone)
    if busy then return false end
    busy = true
    task.spawn(function()
        for _, point in ipairs(Entrances.available()) do
            if Player.distanceTo(point.position) <= Router.TOO_CLOSE then
                -- A jump here would not move the character: no verdict possible.
                attempts[point.name] = "too close to test, move away first"
            else
                local plan = { kind = "entrance", name = point.name, point = point }
                lastUsed[point.name] = os.clock()
                local ok, err = pcall(actions.entrance, plan)
                if not ok then recordResult(point.name, false, tostring(err)) end
            end
        end
        route = nil
        busy = false
        justJumped = true
        if onDone then pcall(onDone) end
    end)
    return true
end

-- The portal test: from where the player stands, the unlocked point nearest
-- `goal` is called each way in turn (Banana's, then placed on the point,
-- then Teddy's position) until one works. Returns false and why when it
-- cannot start; `onDone(text)` gets the result.
function Router.portalTest(goal, onDone)
    if busy then return false, "a teleport is already running" end
    local best, bestDistance
    for _, point in ipairs(Entrances.available()) do
        local distance = (goal - point.position).Magnitude
        if distance <= Router.FAR and (not bestDistance or distance < bestDistance) then
            best, bestDistance = point, distance
        end
    end
    if not best then return false, "no unlocked portal within 3000 studs of it" end
    busy = true
    lastUsed[best.name] = os.clock()
    task.spawn(function()
        local text
        local tried = {}
        for _, way in ipairs(Router.waysFor(best, true)) do
            local ok, detail = Router.tryWay(best, way, Router.TEST_BANANA_TIME)
            if ok then
                bestWay[best.name] = way
                recordResult(best.name, true, nil)
                text = "works with the " .. Router.WAYS[way] .. " (" .. detail .. ")"
                break
            end
            tried[#tried + 1] = Router.WAYS[way] .. ": " .. detail
        end
        if not text then
            text = "no way worked (" .. table.concat(tried, "; ") .. ")"
            recordResult(best.name, false, text)
        end
        route = nil
        busy = false
        justJumped = true
        if onDone then pcall(onDone, best.name .. ": " .. text) end
    end)
    return true, best.name
end

function Router.busy() return busy end
function Router.note() return note end
function Router.lastTrip() return lastTrip end

-- The portals of this sea and what is known about them, for the Settings tab.
function Router.describe()
    local lines = {}
    local unlocks = Entrances.unlocks()
    for _, point in ipairs(Entrances.POINTS[Player.sea() or 0] or {}) do
        local state
        if not Entrances.confirmed(point) then
            state = unlocks and ("not unlocked (" .. tostring(point.unlock) .. ")") or "waiting for the unlocks"
        elseif isLocked(point.name) then
            state = string.format("paused, %d s left", math.ceil(Router.LOCK_TIME - (os.clock() - lockedAt[point.name])))
        elseif confirmed[point.name] then
            state = "works" .. (bestWay[point.name] and (" (" .. Router.WAYS[bestWay[point.name]] .. ")") or "")
        else
            state = "untested"
        end
        if attempts[point.name] then state = state .. " (" .. attempts[point.name] .. ")" end
        lines[#lines + 1] = point.name .. ": " .. state
    end
    if #lines == 0 then lines[1] = "No portal known in this sea." end
    local fruit
    if not Settings.get("PortalFruit") then
        fruit = "off"
    elseif Gateway.owned() then
        fruit = Gateway.ready(false) and "ready" or "waiting for the C skill"
    else
        fruit = "needs the Portal fruit at level 200+"
    end
    lines[#lines + 1] = "Portal fruit: " .. fruit
    local reset = "off"
    if Settings.get("ResetTeleport") then
        local blocked = Router.resetBlocked()
        reset = blocked and ("on, skipped now: " .. blocked) or "on"
    end
    lines[#lines + 1] = "Reset teleport: " .. reset
    lines[#lines + 1] = string.format("Teleport when farther than %d studs", Router.teleportDistance())
    lines[#lines + 1] = "Last trip: " .. (lastTrip or "none yet")
    lines[#lines + 1] = "Sea: " .. tostring(Player.sea() or "unknown")
    return table.concat(lines, "\n")
end

-- Test hook.
function Router.reset()
    route, note, lastTrip = nil, nil, nil
    bestWay = {}
    busy, justJumped = false, false
    confirmed, lastUsed = {}, {}
    failures, lockedAt, attempts = {}, {}, {}
    respawns = { goal = nil, count = 0 }
end

return Router
