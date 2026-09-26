--=============================================================================
-- BIND — Fluent elements wired to a setting
--=============================================================================
--  Every control follows the same contract, so it lives in one place:
--    Idx      = the setting key (also what SaveManager stores it under)
--    Default  = the setting's current value
--    Callback = writes the setting
--
--  Fluent asserts on missing fields (a slider needs Title, Default, Min, Max
--  and Rounding). An assert inside a tab stops that tab and every element
--  after it, which is how a UI ends up showing only its first tab -- so the
--  required fields are always passed from here.
--=============================================================================

local Settings = require("Core.Settings")
local TouchSlider = require("UI.TouchSlider")

local Bind = {}

function Bind.toggle(parent, key, title, description)
    return parent:AddToggle(key, {
        Title = title,
        Description = description,
        Default = Settings.get(key) == true,
        Callback = function(value)
            Settings.set(key, value == true)
        end,
    })
end

-- Fluent's rounding hands back a string for whole numbers when Rounding > 0
-- ("3" instead of 3), and SaveManager reloads sliders from strings: the value
-- is always converted before it reaches the settings.
function Bind.slider(parent, key, title, min, max, rounding, description)
    local slider = parent:AddSlider(key, {
        Title = title,
        Description = description,
        Default = Settings.get(key),
        Min = min,
        Max = max,
        Rounding = rounding or 0,
        Callback = function(value)
            local number = tonumber(value)
            if number then Settings.set(key, number) end
        end,
    })
    pcall(TouchSlider.enhance, parent, slider)
    return slider
end

function Bind.dropdown(parent, key, title, values, description)
    return parent:AddDropdown(key, {
        Title = title,
        Description = description,
        Values = values,
        Multi = false,
        Default = Settings.get(key),
        Callback = function(value)
            if value ~= nil then Settings.set(key, value) end
        end,
    })
end

-- Text box: the setting holds the text. Finished = written when the box
-- loses focus, not on every key.
function Bind.input(parent, key, title, placeholder, description)
    return parent:AddInput(key, {
        Title = title,
        Description = description,
        Default = tostring(Settings.get(key) or ""),
        Placeholder = placeholder or "",
        Numeric = false,
        Finished = true,
        Callback = function(value)
            Settings.set(key, tostring(value or ""))
        end,
    })
end

-- Multi-select: the setting holds a set ({ Z = true, X = true }).
function Bind.multiDropdown(parent, key, title, values, description)
    local current = Settings.get(key) or {}
    local default = {}
    for _, value in ipairs(values) do
        if current[value] then default[#default + 1] = value end
    end
    return parent:AddDropdown(key, {
        Title = title,
        Description = description,
        Values = values,
        Multi = true,
        Default = default,
        Callback = function(selection)
            local set = {}
            if type(selection) == "table" then
                for value, on in pairs(selection) do
                    if on then set[value] = true end
                end
            end
            Settings.set(key, set)
        end,
    })
end

-- The current choice of a dropdown setting, as a list (a set's keys for a
-- multi-select). A list that must be fetched starts with just these, so the
-- saved choice survives until the full list arrives.
function Bind.saved(key, multi)
    local value = Settings.get(key)
    local list = {}
    if multi then
        for name, on in pairs(type(value) == "table" and value or {}) do
            if on then list[#list + 1] = name end
        end
        table.sort(list)
    elseif type(value) == "string" and value ~= "" then
        list[1] = value
    end
    return list
end

-- Fills a dropdown in the background: `fetch` may ask the server or load
-- game modules, which must not hold up the window while it is built. The
-- saved choice stays in the list and stays selected.
function Bind.fillLater(control, key, fetch, multi)
    task.spawn(function()
        local ok, values = pcall(fetch)
        if not ok or type(values) ~= "table" or #values == 0 then return end
        local seen = {}
        for _, name in ipairs(values) do seen[name] = true end
        for _, name in ipairs(Bind.saved(key, multi)) do
            if not seen[name] then values[#values + 1] = name end
        end
        pcall(function() control:SetValues(values) end)
        local value = Settings.get(key)
        if multi then
            pcall(function() control:SetValue(type(value) == "table" and value or {}) end)
        elseif value ~= nil and value ~= "" then
            pcall(function() control:SetValue(value) end)
        end
    end)
    return control
end

return Bind
