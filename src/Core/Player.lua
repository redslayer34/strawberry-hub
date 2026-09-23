--=============================================================================
-- PLAYER — the local character, its data, its tools
--=============================================================================
--  Every accessor tolerates a missing piece (no character while respawning,
--  no Data folder before it replicates) and returns nil instead of erroring,
--  so callers only ever test one value.
--=============================================================================

local Services = require("Core.Services")

local Player = {}

-- Blox Fruits runs each sea as its own place, with one id per server region.
Player.SEAS = {
    [2753915549] = 1, [85211729168715] = 1,
    [4442272183] = 2, [79091703265657] = 2,
    [7449423635] = 3, [100117331123089] = 3,
}

function Player.character()
    local player = Services.player()
    return player and player.Character
end

function Player.humanoid()
    local character = Player.character()
    return character and character:FindFirstChildOfClass("Humanoid")
end

function Player.hrp()
    local character = Player.character()
    return character and character:FindFirstChild("HumanoidRootPart")
end

function Player.alive()
    local humanoid = Player.humanoid()
    return humanoid ~= nil and humanoid.Health > 0 and Player.hrp() ~= nil
end

function Player.position()
    local hrp = Player.hrp()
    return hrp and hrp.Position
end

function Player.distanceTo(position)
    local here = Player.position()
    if not here or not position then return math.huge end
    return (position - here).Magnitude
end

-- LocalPlayer.Data.<name>.Value (Level, Race, Beli, Fragments...).
function Player.data(name)
    local player = Services.player()
    local data = player and player:FindFirstChild("Data")
    local value = data and data:FindFirstChild(name)
    return value and value.Value
end

function Player.level()
    return Player.data("Level") or 0
end

function Player.sea()
    return Player.SEAS[game.PlaceId]
end

-- True while the character is stunned: the server rejects attacks then.
function Player.stunned()
    local character = Player.character()
    local stun = character and character:FindFirstChild("Stun")
    return stun ~= nil and stun.Value ~= 0
end

---------------------------------------------------------------------------
-- Tools
---------------------------------------------------------------------------
--  Weapons are recognised by ToolTip ("Melee", "Sword", "Blox Fruit", "Gun"):
--  the game sets it on every weapon, whereas names change with each item.

local function toolIn(container, tooltip)
    if not container then return nil end
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Tool") and child.ToolTip == tooltip then
            return child
        end
    end
    return nil
end

function Player.findTool(tooltip)
    local player = Services.player()
    return toolIn(Player.character(), tooltip)
        or toolIn(player and player:FindFirstChild("Backpack"), tooltip)
end

function Player.equippedTool()
    local character = Player.character()
    return character and character:FindFirstChildOfClass("Tool")
end

-- Equips the first tool with this ToolTip. Returns the tool, or nil when the
-- player owns none.
function Player.equip(tooltip)
    local tool = Player.findTool(tooltip)
    if not tool then return nil end
    if tool.Parent == Player.character() then return tool end

    local humanoid = Player.humanoid()
    if humanoid and not humanoid.Sit then
        humanoid:EquipTool(tool)
    end
    return tool
end

---------------------------------------------------------------------------
-- Session
---------------------------------------------------------------------------

-- Blocks until the game, the player data and the main GUI exist, or until
-- `timeout` seconds have passed. Returns true when everything is there.
function Player.waitUntilLoaded(timeout)
    local deadline = os.clock() + (timeout or 60)
    while os.clock() < deadline do
        local player = Services.player()
        if game:IsLoaded() and player and player:FindFirstChild("DataLoaded") then
            return true
        end
        task.wait(0.5)
    end
    return false
end

-- Roblox kicks an idle client after 20 minutes. A right click on Idled resets
-- the timer. Returns the connection so Unload can drop it.
function Player.antiAfk()
    local player = Services.player()
    local virtualUser = Services.get("VirtualUser")
    return player.Idled:Connect(function()
        pcall(function()
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.new())
        end)
    end)
end

local function mainGui()
    local player = Services.player()
    local gui = player and player:FindFirstChild("PlayerGui")
    return gui and (gui:FindFirstChild("Main (minimal)") or gui:FindFirstChild("Main"))
end

-- The team screen is a game GUI: the button is selected, then Return is sent
-- through VirtualInputManager, which is what activates it on every executor.
local function press(button)
    local guiService = Services.get("GuiService")
    local input = Services.get("VirtualInputManager")
    button.Selectable = true
    guiService.SelectedObject = button
    input:SendKeyEvent(true, "Return", false, button)
    input:SendKeyEvent(false, "Return", false, button)
    guiService.SelectedObject = nil
end

-- Picks a team if the team screen is up. Returns true once no team screen is
-- showing (already chosen, or chosen now).
function Player.chooseTeam(team, timeout)
    team = team == "Marines" and "Marines" or "Pirates"
    local deadline = os.clock() + (timeout or 30)
    while os.clock() < deadline do
        local gui = mainGui()
        local screen = gui and gui:FindFirstChild("ChooseTeam")
        if screen then
            if not screen.Visible then return true end
            local button = Services.find(screen, "Container." .. team .. ".Frame.TextButton")
            if button then pcall(press, button) end
        end
        task.wait(1)
    end
    return false
end

return Player
