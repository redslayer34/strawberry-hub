--=============================================================================
-- UI — library entry point
--=============================================================================
--  A library, not a hidden singleton: the returned table keeps the list of its
--  windows so everything can be released in one call, which matters when a hub
--  reloads over itself.
--
--  Dependencies: none. Standard Roblox services only (TweenService,
--  UserInputService, Players). `gethui` is used when it exists, with a
--  PlayerGui fallback.
--=============================================================================

local Notification = require("UI.Notification")
local Theme = require("UI.Theme")
local Utility = require("UI.Utility")
local Window = require("UI.Window")

local UI = {}
UI.__index = UI

UI.Theme = Theme
UI.Utility = Utility
UI.windows = {}

local notifier

function UI:CreateWindow(opts)
    local window = Window.new(opts or {})
    table.insert(UI.windows, window)
    return window
end

-- The notification manager is created on first use: a hub that never emits one
-- does not pay for a ScreenGui.
function UI:Notify(opts)
    if not notifier or notifier.destroyed then
        notifier = Notification.new()
    end
    return notifier:Notify(opts)
end

function UI:ClearNotifications()
    if notifier then notifier:Clear() end
end

-- Applies a palette live. Nothing is rebuilt: toggle values, the active tab
-- and the window position are preserved.
function UI:SetTheme(newTheme)
    return Theme.set(newTheme)
end

function UI:GetTheme() return Theme.get() end
function UI:ResetTheme() return Theme.reset() end

function UI:Destroy()
    for index = #UI.windows, 1, -1 do
        local window = UI.windows[index]
        pcall(function() window:Destroy() end)
        UI.windows[index] = nil
    end
    if notifier then
        notifier:Destroy()
        notifier = nil
    end
end

return UI
