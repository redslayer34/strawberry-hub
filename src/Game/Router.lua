--=============================================================================
-- ROUTER — the reference's (Banana Cat Hub) way to far goals
--=============================================================================
--  Movement asks the Router every frame. The rules are the reference's
--  toTarget, in its order:
--
--    temple      Sea 3: out of the Temple of Time, its own way back
--    submarine   Sea 3: the only way to and from the Submerged Island
--    gateway     opt-in: the Portal fruit's Gateway to the island nearest the
--                goal (fruit level 200+, C skill ready)
--    entrance    requestEntrance to the unlocked portal point nearest the
--                goal, when the goal is FAR studs away and the point within
--                FAR studs of it
--    celestial   Sea 3: the Celestial Domain's own transports
--    mirror      Sea 3: the Cake Loaf's big mirror
--    respawn     opt-in ("Reset Teleport"): move the spawn point to the
--                goal's island, then reset the character
--    direct      fly
--
--  One thing is added to the reference: a shortcut that does not move the
--  player is not tried forever. An entrance gets ENTRANCE_TRIES calls; when
--  the player did not move, it cools down, and FAILS_TO_LOCK misses in a row
--  pause it for LOCK_TIME while the Router flies.
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
Router.TOO_CLOSE = 1000        -- studs: a point this close is not requested
Router.MOVED = 300             -- studs the character must move for a jump to count
Router.ENTRANCE_TRIES = 10     -- requestEntrance calls before giving up
Router.ENTRANCE_EVERY = 0.3    -- seconds between two calls
Router.LAST_LOOK = 4           -- x 0.25 s: a jump may land just after the last call
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

local route, note
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

-- The unlocked point nearest the goal, within FAR studs of it. Returns the
-- point, or nil and why none was taken.
function Router.entranceFor(here, goal)
    local points = Entrances.available()
    local best, bestDistance, why
    for _, point in ipairs(points) do
        local toGoal = (goal - point.position).Magnitude
        if toGoal <= Router.FAR then
            if isLocked(point.name) then
                why = point.name .. " paused (" .. tostring(attempts[point.name]) .. ")"
            elseif coolingDown(point.name) then
                why = point.name .. " just tried"
            elseif within(here, point.position, Router.TOO_CLOSE) then
                why = point.name .. " is right here"
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

-- What to do to reach `goal` from `here`, following the reference's rules.
function Router.plan(here, goal)
    local distance = (goal - here).Magnitude
    local direct = { kind = "direct" }
    local plan = direct
    local sea = Player.sea()

    if distance < Router.SNAP then
        plan = direct
    elseif not sea then
        direct.reason = "sea unknown"
    else
        local found
        if sea == 3 then
            local inTemple = within(here, Router.TEMPLE, Router.TEMPLE_RADIUS)
            local fromIsland = within(here, Router.ISLAND, Router.ISLAND_RADIUS)
            local toIsland = within(goal, Router.ISLAND, Router.ISLAND_RADIUS)
            if inTemple and not within(goal, Router.TEMPLE, Router.TEMPLE_RADIUS) then
                found = { kind = "temple", name = "Temple of Time exit", dock = Router.TEMPLE }
            elseif toIsland and not fromIsland then
                found = { kind = "submarine", name = "Submarine", dock = Router.WORKER, enter = true }
            elseif fromIsland and not toIsland then
                found = { kind = "submarine", name = "Submarine", dock = Router.DOCK, enter = false }
            end
        end

        if not found and distance >= Router.FAR then
            if Settings.get("PortalFruit") then
                local island = Gateway.islandNear(goal, Router.FAR)
                local key = island and ("Portal fruit to " .. island.name)
                if island and usable(key) and Gateway.ready(true) then
                    found = { kind = "gateway", name = key, island = island }
                end
            end
            if not found then
                local point, why = Router.entranceFor(here, goal)
                if point then
                    found = { kind = "entrance", name = point.name, point = point }
                else
                    direct.reason = why
                end
            end
        end

        if not found and sea == 3 then
            found = celestialPlan(here, goal) or mirrorPlan(here, goal)
            if found and not usable(found.name) then found = nil end
        end

        if not found and Settings.get("RespawnShortcut") and respawnsLeft(goal)
            and Regions.shouldRespawn(here, goal) then
            local spawn = Regions.respawnTarget(here, goal)
            local name = spawn and ("respawn at " .. spawn.name)
            if spawn and usable(name) then
                found = { kind = "respawn", name = name, spawn = spawn }
            end
        end

        plan = found or direct
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

-- The reference calls requestEntrance again and again while the goal is
-- far; here the calls stop at the first move or after ENTRANCE_TRIES.
function actions.entrance(plan)
    local start = Player.position()
    local function moved()
        local here = Player.position()
        if not here or not start then return 0 end
        return (here - start).Magnitude
    end
    local answer
    for try = 1, Router.ENTRANCE_TRIES do
        answer = Entrances.use(plan.point)
        if waitUntil(1, function() return moved() > Router.MOVED end, Router.ENTRANCE_EVERY) then
            recordResult(plan.name, true, string.format("moved %d studs, call %d", math.floor(moved()), try))
            return
        end
    end
    if waitUntil(Router.LAST_LOOK, function() return moved() > Router.MOVED end) then
        recordResult(plan.name, true, string.format("moved %d studs", math.floor(moved())))
        return
    end
    recordResult(plan.name, false, string.format("no move after %d calls, answer %s",
        Router.ENTRANCE_TRIES, tostring(answer)))
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
end

local function run(plan)
    busy = true
    lastUsed[plan.name] = os.clock()
    task.spawn(function()
        local ok, err = pcall(actions[plan.kind], plan)
        if not ok then warn("[Strawberry Hub] " .. plan.name .. ": " .. tostring(err)) end
        route = nil
        busy = false
        justJumped = true
    end)
end

-- Called by Movement each frame. Returns handled (true: a shortcut is
-- running, do not move this frame) and an optional Vector3 to fly to
-- instead of the goal (a dock, an NPC, the mirror).
function Router.update(here, goal)
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
        route = Router.plan(here, goal)
    end

    if route.kind == "direct" then
        note = route.reason and ("flying: " .. route.reason) or nil
        return false
    end
    note = "via " .. route.name

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

function Router.busy() return busy end
function Router.note() return note end

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
            state = "works"
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
    lines[#lines + 1] = "Reset teleport: " .. (Settings.get("RespawnShortcut") and "on" or "off")
    lines[#lines + 1] = "Sea: " .. tostring(Player.sea() or "unknown")
    return table.concat(lines, "\n")
end

-- Test hook.
function Router.reset()
    route, note = nil, nil
    busy, justJumped = false, false
    confirmed, lastUsed = {}, {}
    failures, lockedAt, attempts = {}, {}, {}
    respawns = { goal = nil, count = 0 }
end

return Router
