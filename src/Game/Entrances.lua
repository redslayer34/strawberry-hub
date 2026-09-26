--=============================================================================
-- ENTRANCES — the game's own teleport points
--=============================================================================
--  CommF_:InvokeServer("requestEntrance", position) moves the player
--  straight to one of these points, from anywhere in the sea: that is how
--  the reference (Banana Cat Hub) travels. Which points exist depends on the
--  sea and on what the player has unlocked (CommF_ GetUnlockables):
--  Doflamingo's rooms need FlamingoAccess, the Rip Indra portals need
--  DefeatedIndraTrueForm. Points and rules are the reference's, with what
--  Teddy Hub adds: another position for several points (`alt`), two more
--  Sky points in Sea 1, and a second way to call (Entrances.use with
--  `placed`: the character is set on the point while calling).
--=============================================================================

local Player = require("Core.Player")
local Services = require("Core.Services")
local TeleportTag = require("Game.TeleportTag")

local Entrances = {}

local function v(x, y, z) return Vector3.new(x, y, z) end

-- unlock: the GetUnlockables flag the point needs (nil = always open).
-- alt: the position Teddy Hub sends for the same point. The two hubs do not
-- agree on the digits (Upper Sky's Y is 5545.49 in one and 5547.14 in the
-- other), so the server does not need an exact match; which one works is
-- learned in game.
Entrances.POINTS = {
    [1] = {
        { name = "Upper Sky", position = v(-7894.6201171875, 5545.49169921875, -380.2467346191406),
            alt = v(-7894.6177, 5547.1416, -380.2912) },
        { name = "Sky Island", position = v(-4607.82275390625, 872.5422973632812, -1667.556884765625) },
        { name = "Underwater City", position = v(61163.8515625, 11.759522438049316, 1819.7841796875),
            alt = v(61163.85, 11.6796875, 1819.7842) },
        { name = "Whirlpool", position = v(3876.280517578125, 35.10614013671875, -1939.3201904296875),
            alt = v(3864.6885, 6.7369504, -1926.2141) },
        { name = "Upper Sky 2", position = v(-6023.5767, 5469.7197, 2203.3083) },
        { name = "Sky Island 2", position = v(-4166.61, 1093.698, -347.16226) },
    },
    [2] = {
        { name = "Cursed Ship", position = v(923.21252441406, 126.9760055542, 32852.83203125) },
        { name = "Graveyard", position = v(-6508.5581054688, 89.034996032715, -132.83953857422) },
        { name = "Doflamingo Mansion", position = v(-288.46246337890625, 306.130615234375, 597.9988403320312), unlock = "FlamingoAccess" },
        { name = "Flamingo Room", position = v(2284.912109375, 15.152046203613281, 905.48291015625), unlock = "FlamingoAccess" },
    },
    [3] = {
        { name = "Temple of Time", position = v(28282.5703125, 14896.8505859375, 105.1042709350586), temple = true },
        { name = "Castle on the Sea", position = v(-4967.6826171875, 314.88238525390625, -3157.098388671875), unlock = "DefeatedIndraTrueForm",
            alt = v(-5069.1216, 314.5155, -3000.4673) },
        { name = "Hydra", position = v(5661.5302734375, 1013.4113159179688, -334.9619140625), unlock = "DefeatedIndraTrueForm",
            alt = v(5657.0947, 1013.0795, -340.00446) },
        { name = "Turtle Mansion", position = v(-12463.8740234375, 374.9144592285156, -7523.77392578125), unlock = "DefeatedIndraTrueForm",
            alt = v(-12547.14, 337.16827, -7471.882) },
    },
}

-- The point called `name` in the current sea, or nil.
function Entrances.named(name)
    for _, point in ipairs(Entrances.POINTS[Player.sea() or 0] or {}) do
        if point.name == name then return point end
    end
    return nil
end

Entrances.UNLOCK_RETRY = 5
Entrances.UNLOCK_TRIES = 30

local unlocks   -- GetUnlockables result, nil until known

function Entrances.unlocks()
    return unlocks
end

-- Fetches the unlockables once, in the background, retrying a few times.
function Entrances.refresh()
    task.spawn(function()
        for _ = 1, Entrances.UNLOCK_TRIES do
            local result = Services.invoke("GetUnlockables")
            if type(result) == "table" then
                unlocks = result
                return
            end
            task.wait(Entrances.UNLOCK_RETRY)
        end
    end)
end

-- Whether the unlockables confirm this point (points without a
-- requirement are always confirmed).
function Entrances.confirmed(point)
    if not point.unlock then return true end
    return unlocks ~= nil and unlocks[point.unlock] == true
end

-- The points of the current sea the player has unlocked, as the reference
-- builds its list: a point with a requirement only once GetUnlockables has
-- answered and confirms it.
function Entrances.available()
    local list = {}
    for _, point in ipairs(Entrances.POINTS[Player.sea() or 0] or {}) do
        if Entrances.confirmed(point) then list[#list + 1] = point end
    end
    return list
end

-- The Temple of Time map lives in ReplicatedStorage.MapStash until the
-- client loads it; the entrance only works once it is in workspace.Map. As
-- in the reference, it goes back to the stash unless the player reaches it
-- within BORROW_STEPS x 0.25 s.
Entrances.TEMPLE = Vector3.new(28282.5703125, 14896.8505859375, 105.1042709350586)
Entrances.BORROW_STEPS = 120
Entrances.AT_TEMPLE = 1000
Entrances.PLACED_ABOVE = 1.5   -- studs above the point, as Teddy Hub places it

local function borrowTemple()
    local stash = Services.replicated():FindFirstChild("MapStash")
    local temple = stash and stash:FindFirstChild("Temple of Time")
    local map = workspace:FindFirstChild("Map")
    if not temple or not map then return end
    temple:SetAttribute("ClientBorrowed", true)
    temple.Parent = map
    task.spawn(function()
        for _ = 1, Entrances.BORROW_STEPS do
            task.wait(0.25)
            if temple.Parent ~= map or Player.distanceTo(Entrances.TEMPLE) < Entrances.AT_TEMPLE then break end
        end
        pcall(function()
            temple:SetAttribute("ClientBorrowed", nil)
            if temple.Parent == map and Player.distanceTo(Entrances.TEMPLE) >= Entrances.AT_TEMPLE then
                temple.Parent = stash
            end
        end)
    end)
end

-- Sends the teleport request, the reference's way: the player tagged
-- "Teleporting", the Temple of Time map borrowed first for its point.
-- `position` replaces the point's own (its `alt`); with `placed` the
-- character is first set on that position, as Teddy Hub does.
function Entrances.use(point, position, placed)
    position = position or point.position
    TeleportTag.mark()
    if point.temple then pcall(borrowTemple) end
    if placed then
        local hrp = Player.hrp()
        if hrp then
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                hrp.CFrame = CFrame.new(position + Vector3.new(0, Entrances.PLACED_ABOVE, 0))
            end)
        end
    end
    local remote = Services.commF()
    if not remote then return nil end
    -- A method call, written as the reference writes it.
    local ok, answer = pcall(function() return remote:InvokeServer("requestEntrance", position) end)
    if ok then return answer end
    return nil
end

-- Test hook.
function Entrances.reset(value)
    unlocks = value
end

return Entrances
