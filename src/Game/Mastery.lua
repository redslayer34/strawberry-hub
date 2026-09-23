--=============================================================================
-- MASTERY — finish low mobs with the fruit or gun to level its mastery
--=============================================================================
--  While the engaged mob is above MasteryHealth %, the normal weapon hits.
--  Below it, the mastery weapon is equipped and the first selected skill that
--  is ready is used on the mob (AimHook points it there). A skill's readiness
--  is read from the game's skill bar, PlayerGui.Main.Skills[tool][key]: the
--  same test the reference uses.
--=============================================================================

local AimHook = require("Game.AimHook")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Mastery = {}

Mastery.HOLD = 0.3          -- seconds a skill key is held
Mastery.PRESS_EVERY = 0.4   -- seconds between two skill presses

local lastPress = -math.huge

function Mastery.active(mob)
    if not Settings.get("MasteryFarm") then return false end
    local humanoid = mob and mob:FindFirstChildOfClass("Humanoid")
    if not humanoid or not humanoid.MaxHealth or humanoid.MaxHealth <= 0 then return false end
    return humanoid.Health / humanoid.MaxHealth * 100 <= Settings.get("MasteryHealth")
end

local function skillBar(tool)
    local player = Services.player()
    local gui = player and player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    for _, screen in ipairs(gui:GetChildren()) do
        local skills = screen:FindFirstChild("Skills")
        local bar = skills and skills:FindFirstChild(tool.Name)
        if bar then return bar end
    end
    return nil
end

local WHITE = Color3.new(1, 1, 1)
local IDLE = UDim2.new(0, 0, 1, -1)
local FULL = UDim2.new(1, 0, 1, -1)

local function ready(frame)
    local title = frame:FindFirstChild("Title")
    local cooldown = frame:FindFirstChild("Cooldown")
    if not title or not cooldown then return false end
    return (title.TextColor3 == WHITE and cooldown.Size == IDLE) or cooldown.Size == FULL
end

-- The first selected skill key that is ready on `tool`, or nil. `keys` (a
-- set) replaces the Mastery Skills selection when given.
function Mastery.readySkill(tool, keys)
    local bar = skillBar(tool)
    if not bar then return nil end
    local selected = keys or Settings.get("MasterySkills") or {}
    for _, frame in ipairs(bar:GetChildren()) do
        if frame:IsA("Frame") and frame.Name ~= "Template" and selected[frame.Name] and ready(frame) then
            return frame.Name
        end
    end
    return nil
end

local function press(key)
    local input = Services.get("VirtualInputManager")
    input:SendKeyEvent(true, key, false, game)
    task.delay(Mastery.HOLD, function()
        pcall(function() input:SendKeyEvent(false, key, false, game) end)
    end)
end

-- Called every frame by Fight while a mob is engaged. Returns true when the
-- mastery weapon took over (the caller then leaves the weapon alone).
function Mastery.step(mob)
    if not Mastery.active(mob) then
        AimHook.target = nil
        return false
    end

    local tool = Player.equip(Settings.get("MasteryWeapon"))
    if not tool then
        AimHook.target = nil
        return false
    end

    AimHook.install()
    AimHook.target = mob.HumanoidRootPart.CFrame

    local now = os.clock()
    if now - lastPress >= Mastery.PRESS_EVERY and tool.Parent == Player.character() then
        local key = Mastery.readySkill(tool)
        if key then
            lastPress = now
            press(key)
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Skills at a point (trees, sea events): every weapon in turn
---------------------------------------------------------------------------

Mastery.ALL_KEYS = { Z = true, X = true, C = true, V = true, F = true }
Mastery.WEAPONS = { "Blox Fruit", "Melee", "Sword", "Gun" }

local weaponIndex = 1

-- Aims the skills at `target` (a CFrame) and uses the next ready skill of
-- the weapons the player owns, moving on to the next weapon when the
-- current one has nothing ready. Paced like Mastery.step.
function Mastery.fireAt(target)
    AimHook.install()
    AimHook.target = target
    local now = os.clock()
    if now - lastPress < Mastery.PRESS_EVERY then return end
    for _ = 1, #Mastery.WEAPONS do
        local tool = Player.equip(Mastery.WEAPONS[weaponIndex])
        if tool and tool.Parent == Player.character() then
            local key = Mastery.readySkill(tool, Mastery.ALL_KEYS)
            if key then
                lastPress = now
                press(key)
                return
            end
        end
        weaponIndex = weaponIndex % #Mastery.WEAPONS + 1
    end
end

function Mastery.reset()
    AimHook.target = nil
    lastPress = -math.huge
end

return Mastery
