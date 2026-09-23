--=============================================================================
-- ROUTER — picks the fastest way to a far goal
--=============================================================================
--  Movement asks the Router every frame. Each possible route is priced in
--  seconds and the cheapest wins:
--
--    direct      fly all the way (distance / current speed)
--    learned     a portal learned in game: fly to its entrance (or use it
--                from here when it is known to reach), trigger it, fly on
--    entrance    requestEntrance to a hard-coded point: rejected by the
--                server now, kept for "Test portals" only
--    submarine   Sea 3: the only way in and out of the Submerged Island
--    respawn     opt-in: move the spawn point near the goal, then reset
--
--  A shortcut is only taken when it saves MIN_SAVING seconds. The game does
--  not drop the player exactly on the requested point (the Rip Indra and
--  Doflamingo portals land on the destination's own spawn), so a jump counts
--  as done once the player has moved far away or landed near the point. A
--  portal that fails twice in a row is locked for a while; one that works is
--  confirmed. The chosen route is kept while the goal stays put, so
--  a moving mob does not cause a re-plan every frame, and two shortcuts are
--  never chained without flying in between.
--=============================================================================

local Entrances = require("Game.Entrances")
local PortalRecorder = require("Game.PortalRecorder")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Router = {}

Router.SNAP = 150            -- studs: closer goals are simply set
Router.OVERHEAD = 1.5        -- seconds a teleport request costs
Router.MIN_SAVING = 5        -- seconds a shortcut must save...
Router.MIN_SAVED_STUDS = 2000 -- ...or studs of flight (fast flights still get pulled back)
Router.REPLAN_MOVE = 300     -- studs the goal may move before re-planning
Router.COOLDOWN = 4          -- seconds before the same portal is used again
Router.VERIFY_STEPS = 24     -- x 0.25 s to see a jump happen (6 s: the area streams in)
Router.TOO_CLOSE = 1000      -- studs: a portal this close is not worth a request
Router.MOVED = 300           -- studs the character must move for a jump to count
Router.FAILS_TO_LOCK = 2     -- failures in a row before a portal is locked
Router.LOCK_TIME = 120       -- seconds a locked portal stays locked
Router.UNCONFIRMED_COST = 2  -- seconds added to a portal its unlock flag does not confirm
Router.GUESSED_COST = 3      -- seconds added to hard-coded points: learned portals win
Router.RESPAWN_COST = 6      -- seconds a respawn costs
Router.RESPAWN_STEPS = 60    -- x 0.25 s to wait for the new character
Router.PORTAL_STEPS = 12     -- x 0.25 s to see a learned portal work (3 s)
Router.EXIT_RADIUS = 500     -- studs from a portal's exit that count as arrived
Router.PORTAL_DOCK = 3       -- studs from a learned entrance before triggering it
Router.HOLD_STEPS = 3        -- x 0.2 s standing in the portal so the server sees it

-- Sea 3 Submerged Island (reference): the island, the worker who sends you
-- there, the dock to leave from, and where leaving lands.
Router.ISLAND = Vector3.new(11538.6, -2154.7, 9827.3)
Router.ISLAND_RADIUS = 3000
Router.WORKER = Vector3.new(-16269.4, 24.0, 1371.7)
Router.DOCK = Vector3.new(11427.9, -2156.4, 9726.2)
Router.TIKI = Vector3.new(-16456.5, 530.3, 436.2)

-- Sea 3 Temple of Time (reference): leaving it means standing on its exit
-- point and asking the game to send you back.
Router.TEMPLE = Vector3.new(28609.392578125, 14896.533203125, 106.4216537475586)
Router.TEMPLE_RADIUS = 3000
Router.AT_DOCK = 30

local route, note
local busy, justJumped = false, false
local confirmed, lastUsed = {}, {}
local failures, lockedAt, attempts = {}, {}, {}
local decision   -- lines explaining the last far plan

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

local function inTemple(position)
    return Player.sea() == 3 and (position - Router.TEMPLE).Magnitude <= Router.TEMPLE_RADIUS
end

local function onIsland(position)
    return Player.sea() == 3 and (position - Router.ISLAND).Magnitude <= Router.ISLAND_RADIUS
end

local function spawnPoints()
    local points = {}
    local origin = workspace:FindFirstChild("_WorldOrigin")
    local spawns = origin and origin:FindFirstChild("PlayerSpawns")
    if not spawns then return points end
    for _, group in ipairs(spawns:GetChildren()) do
        for _, model in ipairs(group:GetChildren()) do
            if model:IsA("Model") then
                local ok, pivot = pcall(function() return model:GetPivot() end)
                if ok and pivot then points[#points + 1] = { name = model.Name, position = pivot.Position } end
            end
        end
    end
    return points
end

-- The cheapest route from `here` to `goal` at `speed` studs/s.
function Router.plan(here, goal, speed)
    speed = math.max(speed or 1, 1)
    local direct = (goal - here).Magnitude / speed
    local best = { kind = "direct", cost = direct, goal = goal }

    local function consider(option)
        option.goal = goal
        if option.cost < best.cost then best = option end
    end

    -- The Submerged Island is only reachable by submarine, both ways.
    -- Out of the Temple of Time: its own way back, before anything else.
    if inTemple(here) and not inTemple(goal) then
        return {
            kind = "temple", name = "Temple of Time exit", goal = goal, dock = Router.TEMPLE,
            cost = (here - Router.TEMPLE).Magnitude / speed + Router.OVERHEAD, saving = 0,
        }
    end

    local fromIsland, toIsland = onIsland(here), onIsland(goal)
    if toIsland and not fromIsland then
        return {
            kind = "submarine", name = "Submarine", goal = goal, dock = Router.WORKER, enter = true,
            cost = (here - Router.WORKER).Magnitude / speed + Router.OVERHEAD,
            saving = 0,
        }
    elseif fromIsland and not toIsland then
        -- As in the reference, the submarine comes first: portals are not
        -- used from the island.
        return {
            kind = "submarine", name = "Submarine", goal = goal, dock = Router.DOCK, enter = false,
            cost = (here - Router.DOCK).Magnitude / speed + Router.OVERHEAD + (Router.TIKI - goal).Magnitude / speed,
            saving = 0,
        }
    end

    -- Portals learned by watching the player take them: fly to the
    -- entrance, trigger it, continue from the exit. A portal known to reach
    -- this far is triggered from here. The hard-coded requestEntrance points
    -- are not routed: the server only accepts the call at the portal.
    local now = os.clock()
    local learned = PortalRecorder.portals()
    local lines = { string.format("speed %d studs/s, direct %d s", math.floor(speed), math.floor(direct)) }
    local reason
    if #learned == 0 then
        reason = "no portal learned for sea " .. tostring(Player.sea() or "?")
    end
    local bestPortal, bestPortalCost, lockedName
    for _, portal in ipairs(learned) do
        local distance = (here - portal.entrance).Magnitude
        local fromHere = PortalRecorder.canUseFrom(portal, distance)
        local cost = (fromHere and 0 or distance / speed) + Router.OVERHEAD
            + (portal.exit - goal).Magnitude / speed
        if isLocked(portal.name) then
            lockedName = portal.name
            lines[#lines + 1] = string.format("%s: locked, %d s left (%s)", portal.name,
                math.ceil(Router.LOCK_TIME - (now - lockedAt[portal.name])), tostring(attempts[portal.name]))
        elseif now - (lastUsed[portal.name] or -math.huge) < Router.COOLDOWN then
            lines[#lines + 1] = portal.name .. ": just used, cooling down"
        else
            lines[#lines + 1] = string.format("%s: %d s%s", portal.name, math.floor(cost),
                fromHere and " (from here)" or "")
            if not bestPortalCost or cost < bestPortalCost then
                bestPortal, bestPortalCost = portal, cost
            end
            consider({
                kind = "learned", name = portal.name, portal = portal,
                dock = not fromHere and portal.entrance or nil, dockRadius = Router.PORTAL_DOCK,
                cost = cost,
            })
        end
    end

    if Settings.get("RespawnShortcut") then
        for _, spawn in ipairs(spawnPoints()) do
            consider({
                kind = "respawn", name = "respawn at " .. spawn.name, spawn = spawn,
                cost = Router.RESPAWN_COST + (spawn.position - goal).Magnitude / speed,
            })
        end
    end

    best.saving = direct - best.cost
    if best.kind ~= "direct" and best.kind ~= "submarine" and best.saving < Router.MIN_SAVING
        and best.saving * speed < Router.MIN_SAVED_STUDS then
        best = { kind = "direct", cost = direct, goal = goal, saving = 0 }
    end

    if best.kind == "direct" and not reason then
        if bestPortal then
            reason = string.format("best portal %s saves only %d s", bestPortal.name,
                math.max(0, math.floor(direct - bestPortalCost)))
        elseif lockedName then
            reason = lockedName .. " locked (" .. tostring(attempts[lockedName]) .. ")"
        else
            reason = "no portal usable from here"
        end
    end
    best.reason = reason
    if direct >= Router.MIN_SAVING then
        table.insert(lines, 1, best.kind == "direct" and ("chose: fly (" .. tostring(reason) .. ")")
            or ("chose: " .. tostring(best.name)))
        decision = lines
    end
    return best
end

-- The last far trip's plan, for the panel and the log.
function Router.lastDecision()
    return decision and table.concat(decision, "\n") or nil
end

---------------------------------------------------------------------------
-- Running a shortcut
---------------------------------------------------------------------------

local function waitUntil(steps, test)
    for _ = 1, steps do
        task.wait(0.25)
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
    local args = { ... }
    local ok, result = pcall(function() return remote:InvokeServer((table.unpack or unpack)(args)) end)
    return ok and result or nil
end

local actions = {}

function actions.entrance(plan)
    local start = Player.position()
    local answer = Entrances.use(plan.point)
    local function moved()
        local here = Player.position()
        if not here or not start then return 0 end
        return (here - start).Magnitude
    end
    -- Only a real move counts: being near the point already proves nothing.
    local ok = waitUntil(Router.VERIFY_STEPS, function()
        return moved() > Router.MOVED
    end)
    if ok then
        recordResult(plan.name, true, string.format("moved %d studs", math.floor(moved())))
    else
        recordResult(plan.name, false, "no move, server answered " .. tostring(answer))
    end
end

-- Replays a learned portal and waits to land near its exit. Returns
-- whether it worked, the distance it was triggered from, the answer.
-- Stands exactly on the entrance, still, long enough for the server to
-- receive that position: it checks the player is in the portal.
local function standOn(position)
    for _ = 1, math.max(Router.HOLD_STEPS, 1) do
        local hrp = Player.hrp()
        if not hrp then return end
        pcall(function()
            hrp.CFrame = CFrame.new(position)
            hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        end)
        if Router.HOLD_STEPS > 0 then task.wait(0.2) end
    end
end

local function tryPortal(portal, callOnly)
    local here = Player.position()
    if not callOnly and here and (here - portal.entrance).Magnitude <= PortalRecorder.AT_ENTRANCE then
        standOn(portal.entrance)
        here = Player.position()
    end
    local distance = here and (here - portal.entrance).Magnitude or math.huge
    local answer = PortalRecorder.trigger(portal, callOnly)
    local ok = waitUntil(Router.PORTAL_STEPS, function() return near(portal.exit, Router.EXIT_RADIUS) end)
    PortalRecorder.recordUse(portal, distance, ok)
    PortalRecorder.recordTry(portal, ok)
    return ok, distance, answer
end

function actions.learned(plan)
    local ok, distance, answer = tryPortal(plan.portal)
    if ok then
        recordResult(plan.name, true, string.format("worked from %d studs", math.floor(distance)))
    elseif distance > PortalRecorder.AT_ENTRANCE then
        -- Too far for the server: no lock, the next plan flies to the entrance.
        attempts[plan.name] = string.format("too far from %d studs", math.floor(distance))
        lastUsed[plan.name] = nil
    else
        recordResult(plan.name, false, "no teleport at the entrance, answer " .. tostring(answer))
    end
end

function actions.temple(plan)
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

function actions.respawn(plan)
    Services.invoke("SetLastSpawnPoint", plan.spawn.name)
    if Player.data("LastSpawnPoint") ~= plan.spawn.name then
        recordResult(plan.name, false, "spawn point refused")
        return
    end
    local old = Player.character()
    local humanoid = Player.humanoid()
    if humanoid then humanoid.Health = 0 end
    waitUntil(Router.RESPAWN_STEPS, function()
        return Player.character() ~= old and Player.alive()
    end)
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
-- instead of the goal (the submarine dock, for instance).
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

    if not route or (route.goal - goal).Magnitude > Router.REPLAN_MOVE then
        route = Router.plan(here, goal, speed)
    end

    if route.kind == "direct" then
        note = route.reason and ("flying: " .. route.reason) or nil
        return false
    end

    if route.saving and route.saving > 0 and route.saving < math.huge then
        note = string.format("via %s (saves %d s)", route.name, math.floor(route.saving))
    else
        note = "via " .. route.name
    end

    if route.dock and (here - route.dock).Magnitude > (route.dockRadius or Router.AT_DOCK) then
        return false, route.dock
    end

    run(route)
    return true
end

-- Requests every portal of this sea in turn and records what happened, so
-- the player can see once which ones work. Returns false if a shortcut is
-- already running.
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
        -- Learned portals with a game call: does the call work from here?
        for _, portal in ipairs(PortalRecorder.portals()) do
            if portal.call and Player.distanceTo(portal.entrance) > Router.TOO_CLOSE then
                local ok, works = pcall(tryPortal, portal, true)
                if ok and works then break end   -- moved: the other distances changed
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

-- Portals of this sea and what is known about them, for the Settings tab.
function Router.describe()
    local lines = {}
    local known = Entrances.unlocks() ~= nil
    for _, point in ipairs(Entrances.POINTS[Player.sea() or 0] or {}) do
        local state
        if isLocked(point.name) then state = "locked"
        elseif confirmed[point.name] then state = "works"
        elseif not Entrances.confirmed(point) then state = "unlock not confirmed"
        else state = "untested" end
        if attempts[point.name] then state = state .. " (" .. attempts[point.name] .. ")" end
        lines[#lines + 1] = point.name .. ": " .. state
    end
    if #lines == 0 then return "No portal known in this sea." end
    if not known then lines[#lines + 1] = "(unlocks not read yet)" end
    lines[#lines + 1] = "Sea: " .. tostring(Player.sea() or "unknown")
    return table.concat(lines, "\n")
end

PortalRecorder.busyCheck = Router.busy

-- A portal taught again starts clean: earlier failures were before the lesson.
PortalRecorder.onLearned = function(portal)
    failures[portal.name], lockedAt[portal.name], attempts[portal.name] = nil, nil, nil
    lastUsed[portal.name] = nil
end
PortalRecorder.stateOf = function(portal)
    if isLocked(portal.name) then
        return string.format("locked, %d s left", math.ceil(Router.LOCK_TIME - (os.clock() - lockedAt[portal.name])))
    end
    return nil
end
PortalRecorder.decisionText = function() return Router.lastDecision() end

-- Test hook.
function Router.reset()
    route, note = nil, nil
    busy, justJumped = false, false
    confirmed, lastUsed = {}, {}
    failures, lockedAt, attempts = {}, {}, {}
    decision = nil
end

return Router
