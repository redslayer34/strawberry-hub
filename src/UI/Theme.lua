--=============================================================================
-- THEME — central palette, applied live
--=============================================================================
--  No component hardcodes a colour. Each one registers a "painter": a function
--  that applies the palette to its instances. Changing theme is then a matter
--  of replaying every painter, rebuilding nothing — toggle values, window
--  position and the active tab all survive the change.
--
--  A painter runs once on registration, so a component never has to paint
--  itself at construction time.
--=============================================================================

local Theme = {}

-- Dark, compact, discreet red accent. The gaps between Background, Sidebar and
-- Element are deliberately small: that restraint is what gives the reference
-- its settled look, without heavy borders.
Theme.DEFAULT = {
    Window       = Color3.fromRGB(13, 13, 15),
    Background   = Color3.fromRGB(20, 20, 23),
    Sidebar      = Color3.fromRGB(16, 16, 18),
    Topbar       = Color3.fromRGB(16, 16, 18),

    Element      = Color3.fromRGB(26, 26, 30),
    ElementHover = Color3.fromRGB(34, 34, 39),
    ElementDown  = Color3.fromRGB(22, 22, 26),

    TabActive    = Color3.fromRGB(26, 26, 30),
    TabHover     = Color3.fromRGB(22, 22, 26),

    Accent       = Color3.fromRGB(196, 54, 54),
    AccentMuted  = Color3.fromRGB(120, 38, 38),

    Text         = Color3.fromRGB(232, 232, 236),
    MutedText    = Color3.fromRGB(128, 128, 138),
    Border       = Color3.fromRGB(38, 38, 44),

    Toggle       = Color3.fromRGB(44, 44, 50),
    ToggleKnob   = Color3.fromRGB(150, 150, 158),
    Slider       = Color3.fromRGB(44, 44, 50),

    Notification = Color3.fromRGB(22, 22, 26),
}

local current = {}
for key, value in pairs(Theme.DEFAULT) do current[key] = value end

local painters = {}
local nextId = 0

function Theme.get() return current end

-- Reads a colour, falling back to the default palette: a partial theme
-- supplied by the caller must not leave holes.
function Theme.color(key)
    return current[key] or Theme.DEFAULT[key] or Color3.fromRGB(255, 0, 255)
end

-- painter : function(theme). Called immediately, then on every SetTheme.
-- Returns an id to hand to Theme.unregister — held by the component's Maid,
-- which is what prevents orphaned painters after Destroy.
function Theme.register(painter)
    nextId = nextId + 1
    painters[nextId] = painter
    local ok, err = pcall(painter, current)
    if not ok then warn("[UI] painter failed: " .. tostring(err)) end
    return nextId
end

function Theme.unregister(id)
    if id then painters[id] = nil end
end

-- Merge, not replace: passing { Accent = ... } must not wipe the rest of the
-- palette.
function Theme.set(newTheme)
    if type(newTheme) ~= "table" then return current end

    for key, value in pairs(newTheme) do
        if typeof(value) == "Color3" then current[key] = value end
    end

    for _, painter in pairs(painters) do
        local ok, err = pcall(painter, current)
        if not ok then warn("[UI] painter failed: " .. tostring(err)) end
    end
    return current
end

function Theme.reset()
    local copy = {}
    for key, value in pairs(Theme.DEFAULT) do copy[key] = value end
    return Theme.set(copy)
end

-- Useful for tests and diagnostics: a count that never comes back down means
-- components are being destroyed without releasing their painter.
function Theme.painterCount()
    local n = 0
    for _ in pairs(painters) do n = n + 1 end
    return n
end

return Theme
