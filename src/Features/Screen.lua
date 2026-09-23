--=============================================================================
-- SCREEN — AFK helpers: white / black screen, boost FPS, quiet notifications,
-- rejoin after a disconnect, copy the config
--=============================================================================
--  Everything the hub changes here is undone on Unload, except Boost FPS:
--  it rewrites the map's materials, so only a rejoin brings them back.
--=============================================================================

local Loop = require("Core.Loop")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Screen = {}

Screen.CONFIG_FILE = "StrawberryHub/BloxFruits/settings/autosave.json"
Screen.REJOIN_DELAY = 3

local blackout
local rendering = true
local notification, originalDisplay, originalDead
local connections = {}
local boosted = false

---------------------------------------------------------------------------
-- White / black screen
---------------------------------------------------------------------------

local function setRendering(on)
    if rendering == on then return end
    rendering = on
    pcall(function() Services.get("RunService"):Set3dRenderingEnabled(on) end)
end

local function blackFrame(visible)
    if visible and not blackout then
        blackout = Instance.new("ScreenGui")
        blackout.Name = "StrawberryBlackScreen"
        blackout.IgnoreGuiInset = true
        blackout.DisplayOrder = -10
        blackout.ResetOnSpawn = false
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 1, 0)
        frame.BackgroundColor3 = Color3.new(0, 0, 0)
        frame.BorderSizePixel = 0
        frame.Parent = blackout
        blackout.Parent = Services.guiParent()
    elseif not visible and blackout then
        pcall(function() blackout:Destroy() end)
        blackout = nil
    end
end

function Screen.apply()
    local white, black = Settings.get("ScreenWhite") == true, Settings.get("ScreenBlack") == true
    setRendering(not (white or black))
    blackFrame(black)
end

---------------------------------------------------------------------------
-- Boost FPS (the reference's pass: plain materials, no effects)
---------------------------------------------------------------------------

local EFFECTS = { "BlurEffect", "SunRaysEffect", "ColorCorrectionEffect", "BloomEffect", "DepthOfFieldEffect" }

function Screen.simplify(node)
    if node:IsA("BasePart") then
        node.Material = Enum.Material.SmoothPlastic
        node.Reflectance = 0
    elseif node:IsA("Decal") or node:IsA("Texture") then
        node.Transparency = 1
    elseif node:IsA("ParticleEmitter") or node:IsA("Trail") then
        if not (node.Parent and node.Parent.Name == "RelicFire") then
            node.Enabled = false
        end
    elseif node:IsA("Explosion") then
        node.BlastPressure = 1
        node.BlastRadius = 1
    elseif node:IsA("Fire") or node:IsA("SpotLight") or node:IsA("Smoke") or node:IsA("Sparkles") then
        node.Enabled = false
    end
end

function Screen.boost()
    if boosted then return end
    boosted = true
    pcall(function()
        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            terrain.WaterWaveSize, terrain.WaterWaveSpeed = 0, 0
            terrain.WaterReflectance, terrain.WaterTransparency = 0, 0
        end
        local lighting = Services.get("Lighting")
        lighting.GlobalShadows = false
        lighting.FogEnd = 9e9
        for _, effect in ipairs(lighting:GetChildren()) do
            for _, class in ipairs(EFFECTS) do
                if effect:IsA(class) then effect.Enabled = false end
            end
        end
        settings().Rendering.QualityLevel = "Level01"
    end)
    -- The map is huge: yield now and then so the game keeps running.
    task.spawn(function()
        local started = os.clock()
        for _, node in ipairs(workspace:GetDescendants()) do
            pcall(Screen.simplify, node)
            if os.clock() - started > 1 / 120 then
                task.wait()
                started = os.clock()
            end
        end
    end)
    local origin = workspace:FindFirstChild("_WorldOrigin")
    if origin then
        connections.boost = origin.DescendantAdded:Connect(function(node) pcall(Screen.simplify, node) end)
    end
end

---------------------------------------------------------------------------
-- Game notifications
---------------------------------------------------------------------------

-- The game's Notification module decides whether a notification shows
-- (Display) and when it goes (Dead): both answer "handled, gone" while on.
function Screen.wrapNotifications()
    if notification then return true end
    local module = Services.module("Notification")
    if type(module) ~= "table" or type(module.Display) ~= "function" then return false end
    notification, originalDisplay, originalDead = module, module.Display, module.Dead
    module.Display = function(...)
        if Settings.get("ScreenNoNotifications") then return true end
        return originalDisplay(...)
    end
    if type(originalDead) == "function" then
        module.Dead = function(...)
            if Settings.get("ScreenNoNotifications") then return true end
            return originalDead(...)
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Rejoin after a disconnect
---------------------------------------------------------------------------

-- After a kick the server browser is gone; a plain Teleport to the place
-- is what still works from the client.
function Screen.rejoin()
    local player = Services.player()
    return pcall(function() Services.get("TeleportService"):Teleport(game.PlaceId, player) end)
end

local function onPrompt(child)
    if child.Name ~= "ErrorPrompt" or not Settings.get("ScreenAutoRejoin") then return end
    local message = Services.find(child, "MessageArea.ErrorFrame.ErrorMessage")
    if message and tostring(message.Text):find("Teleport", 1, true) then return end
    task.delay(Screen.REJOIN_DELAY, Screen.rejoin)
end
Screen.onPrompt = onPrompt

local function watchDisconnect()
    if connections.prompt then return end
    local overlay = Services.find(Services.get("CoreGui"), "RobloxPromptGui.promptOverlay")
    if not overlay then return end
    connections.prompt = overlay.ChildAdded:Connect(onPrompt)
end

---------------------------------------------------------------------------
-- Config
---------------------------------------------------------------------------

function Screen.copyConfig()
    if not (setclipboard and readfile and isfile) then return false, "your executor cannot copy" end
    if not isfile(Screen.CONFIG_FILE) then return false, "no config saved yet" end
    local ok = pcall(function() setclipboard(readfile(Screen.CONFIG_FILE)) end)
    return ok, ok and "config copied" or "copy failed"
end

---------------------------------------------------------------------------

local function step()
    Screen.apply()
    if Settings.get("ScreenBoostFps") then Screen.boost() end
    if Settings.get("ScreenNoNotifications") then Screen.wrapNotifications() end
    if Settings.get("ScreenAutoRejoin") then watchDisconnect() end
end

function Screen.start()
    Loop.start("Screen", 1, step)
end

function Screen.destroy()
    Loop.stop("Screen")
    setRendering(true)
    blackFrame(false)
    if notification then
        notification.Display, notification.Dead = originalDisplay, originalDead
    end
    notification, originalDisplay, originalDead = nil, nil, nil
    for key, connection in pairs(connections) do
        pcall(function() connection:Disconnect() end)
        connections[key] = nil
    end
end

-- Test hook.
function Screen.reset()
    Screen.destroy()
    rendering, boosted = true, false
end

return Screen
