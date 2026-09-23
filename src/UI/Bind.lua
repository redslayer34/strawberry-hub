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
    return parent:AddSlider(key, {
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

return Bind
