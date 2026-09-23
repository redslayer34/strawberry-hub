--=============================================================================
-- GATEWAY — the Portal fruit's teleport (the reference's "Use Portal Teleport")
--=============================================================================
--  With the Portal fruit eaten, its tool at level 200+ and its C skill ready,
--  pressing C opens the Gateway menu (PlayerGui.Main.Gateway); each island is
--  a button in MainContent.ScrollingFrame. The reference clicks the button
--  of the island nearest the goal by firing its click connections.
--  Island names and positions are the reference's, per sea.
--=============================================================================

local Player = require("Core.Player")
local Services = require("Core.Services")

local Gateway = {}

Gateway.FRUIT = "Portal-Portal"
Gateway.MIN_LEVEL = 200
Gateway.OPEN_STEPS = 30        -- x 0.1 s: 3 s for the menu to show

local function v(x, y, z) return Vector3.new(x, y, z) end

Gateway.ISLANDS = {
    [1] = {
        Colosseum = v(-2143.41333, 152.074326, -3025.54614),
        Desert = v(1330.68298, 103.55368, 4489.30615),
        Fountain = v(5420.33643, 431.04068, 4396.38721),
        Jungle = v(-1340.21948, 136.020538, -101.374214),
        ["Marine Fortress"] = v(-5180.23828, 281.343445, 4383.03174),
        ["Middle Town"] = v(-703.16748, 9.55188751, 1575.1864),
        ["Pirate Village"] = v(-807.662109, 27.8020515, 4119.30127),
        Prison = v(5270.56934, 163.508469, 844.72821),
        Sky = v(-4808.76904, 721.326355, -2668.81787),
        Snow = v(1394.46399, 39.0448875, -1321.63904),
        ["Starter Island"] = v(1038.29968, 112.1365051, 1287.83447),
        ["Starter Marine"] = v(-3096.51929, 231.443558, 2087.51929),
        Underwater = v(61147.9766, 20.5708408, 1366.09839),
        ["Upper Sky"] = v(-7950.03662, 5815.68457, -1968.3374),
        Volcano = v(-5513.97852, 64.4943161, 8577.40039),
    },
    [2] = {
        Cafe = v(-382, 74, 356),
        Colosseum = v(-1836, 46, 1642),
        ["Dark Arena"] = v(3948, 13, -3479),
        ["Docks 1"] = v(-923, 8, 1810),
        ["Docks 2"] = v(-13, 39, 2708),
        ["Docks 3"] = v(-1944, 9, -2594),
        ["Docks 4"] = v(-5798, 1, -5021),
        Doghouse = v(-1984, 125, -82),
        Graveyard = v(-5710, 126, -775),
        ["Haunted Ship"] = v(937, 125, 32879),
        Lab = v(-5542, 335, -5924),
        Lava = v(-5280, 7, -5618),
        Mansion = v(-494, 339, 593),
        Raid = v(-6503, 251, -4495),
        Remote = v(4766, 8, 2911),
        Skull = v(-2956.24341, 123.399323, -9981.06934),
        Snow = v(1210, 429, -4663),
        ["Winter Castle"] = v(5544.71777, 60.1393852, -6359.08887),
    },
    [3] = {
        ["Cake Land"] = v(-2098.970458984375, 76.39494323730469, -12128.359375),
        ["Chocolate Land"] = v(379.1396179199219, 130.20599365234375, -12720.83984375),
        ["Great Tree"] = v(4345.09375, 575.0524291992188, -6159.00439453125),
        ["Haunted Castle"] = v(-9515.0009765625, 149.18876647949, 5534.0502929688),
        ["Hydra Arena"] = v(5020.94580078125, 174.08645629882812, -2011.18505859375),
        ["Hydra Town"] = v(5288.62158203125, 1011.6527709960938, 392.4296875),
        ["Ice Cream Land"] = v(-917.54852294922, 63.364143371582, -10858.696289062),
        ["Peanut Land"] = v(-2037.8001708984, 13.651118278503, -9948.2021484375),
        Port = v(-342.4343566894531, 23.8315486907959, 5547.345703125),
        ["Sea Castle"] = v(-5502.1787109375, 323.6708984375, -2863.4616699219),
        ["Tiki Outpost"] = v(-16456.4629, 530.251953, 436.231812),
        ["Turtle Center"] = v(-12007.979492188, 339.15548706055, -9178.580078125),
        ["Turtle Entrance"] = v(-10163.96484375, 340.29028320313, -8320.767578125),
        ["Turtle Mansion"] = v(-12538.421875, 339.39358520508, -7817.0708007813),
        ["Turtle Mountain"] = v(-12856.61328125, 852.75360107422, -10715.23046875),
    },
}

local WHITE = Color3.new(1, 1, 1)
local IDLE = UDim2.new(0, 0, 1, -1)
local FULL = UDim2.new(1, 0, 1, -1)

local function tool()
    local character = Player.character()
    local player = Services.player()
    return (character and character:FindFirstChild(Gateway.FRUIT))
        or (player and Services.find(player, "Backpack." .. Gateway.FRUIT))
end

local function equip(fruit)
    local humanoid = Player.humanoid()
    if fruit and humanoid and not humanoid.Sit and fruit.Parent ~= Player.character() then
        pcall(function() humanoid:EquipTool(fruit) end)
    end
end

-- The Portal fruit is eaten and its tool is past level 200.
function Gateway.owned()
    if Player.data("DevilFruit") ~= Gateway.FRUIT then return false end
    local fruit = tool()
    local level = fruit and fruit:FindFirstChild("Level")
    return level ~= nil and (tonumber(level.Value) or 0) > Gateway.MIN_LEVEL
end

-- Owned and the C skill ready. The skill bar only exists once the fruit is
-- equipped: with `equipMissing`, it is equipped (as the reference does) and
-- the answer is no for this time.
function Gateway.ready(equipMissing)
    if not Gateway.owned() then return false end
    local player = Services.player()
    local frame = player and Services.find(player, "PlayerGui.Main.Skills." .. Gateway.FRUIT .. ".C")
    if not frame or not frame:IsA("Frame") then
        if equipMissing then equip(tool()) end
        return false
    end
    local title = frame:FindFirstChild("Title")
    local cooldown = frame:FindFirstChild("Cooldown")
    return title ~= nil and cooldown ~= nil and title.TextColor3 == WHITE
        and (cooldown.Size == IDLE or cooldown.Size == FULL)
end

-- The Gateway island nearest `goal` within `radius`, { name, position }.
function Gateway.islandNear(goal, radius)
    local best, bestDistance
    for name, position in pairs(Gateway.ISLANDS[Player.sea() or 0] or {}) do
        local distance = (position - goal).Magnitude
        if distance <= radius and (not bestDistance or distance < bestDistance) then
            best, bestDistance = { name = name, position = position }, distance
        end
    end
    return best
end

-- Opens the Gateway and picks `island`. Returns true once the island's
-- button was clicked.
function Gateway.open(island)
    local fruit = tool()
    if not fruit then return false end
    equip(fruit)
    local player = Services.player()
    local gui = player and Services.find(player, "PlayerGui.Main.Gateway")
    if not gui then return false end
    pcall(function()
        local input = Services.get("VirtualInputManager")
        input:SendKeyEvent(true, "C", false, game)
        input:SendKeyEvent(false, "C", false, game)
    end)
    for _ = 1, Gateway.OPEN_STEPS do
        if gui.Visible then break end
        task.wait(0.1)
    end
    if not gui.Visible then return false end
    local list = Services.find(gui, "MainContent.ScrollingFrame")
    local button = list and list:FindFirstChild(tostring(island))
    if not button or not getconnections then return false end
    local ok, connections = pcall(getconnections, button.MouseButton1Click)
    if not ok or type(connections) ~= "table" then return false end
    for _, connection in ipairs(connections) do
        pcall(function() connection.Function() end)
    end
    return true
end

return Gateway
