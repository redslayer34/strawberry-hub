--=============================================================================
-- UTILITY — instance factory, Maid, animations
--=============================================================================
--  The Maid is what makes Destroy() reliable: every component drops its
--  instances, connections and theme painter into one, then only has to call
--  maid:Destroy(). Without it each component reimplements its own teardown and
--  forgets part of it — usually the connections, which keep the object alive
--  and keep firing.
--=============================================================================

local TweenService = game:GetService("TweenService")

local Utility = {}

---------------------------------------------------------------------------
-- Factory
---------------------------------------------------------------------------

-- Parent is applied LAST: setting properties after parenting makes the engine
-- reflow once per property.
function Utility.new(className, props, children)
    local instance = Instance.new(className)
    local parent = nil

    if props then
        for key, value in pairs(props) do
            if key == "Parent" then
                parent = value
            else
                instance[key] = value
            end
        end
    end

    if children then
        for _, child in ipairs(children) do child.Parent = instance end
    end

    if parent then instance.Parent = parent end
    return instance
end

function Utility.corner(radius, parent)
    return Utility.new("UICorner", {
        CornerRadius = UDim.new(0, radius or 4),
        Parent = parent,
    })
end

function Utility.stroke(color, thickness, parent)
    return Utility.new("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

function Utility.padding(parent, top, bottom, left, right)
    return Utility.new("UIPadding", {
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or top or 0),
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or left or 0),
        Parent = parent,
    })
end

function Utility.list(parent, spacing, direction)
    return Utility.new("UIListLayout", {
        Padding = UDim.new(0, spacing or 4),
        FillDirection = direction or Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = parent,
    })
end

---------------------------------------------------------------------------
-- Animation
---------------------------------------------------------------------------

-- Discreet by default: 0.12 s, ease out. Long animations feel sluggish on
-- mobile, where every interaction counts.
Utility.FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
Utility.SLOW = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Utility.tween(instance, goal, info)
    local tween = TweenService:Create(instance, info or Utility.FAST, goal)
    tween:Play()
    return tween
end

---------------------------------------------------------------------------
-- Maid
---------------------------------------------------------------------------

local Maid = {}
Maid.__index = Maid

function Utility.maid()
    return setmetatable({ tasks = {}, dead = false }, Maid)
end

-- Accepts a connection, an instance, a function, or another Maid. A single
-- entry point means you never have to remember what type a task is.
function Maid:give(task)
    if self.dead then
        -- Handing a task to an already-destroyed Maid releases it at once,
        -- otherwise it would leak silently.
        Maid.dispose(task)
        return task
    end
    table.insert(self.tasks, task)
    return task
end

function Maid.dispose(task)
    if task == nil then return end
    local kind = typeof(task)

    if kind == "RBXScriptConnection" then
        task:Disconnect()
    elseif kind == "Instance" then
        task:Destroy()
    elseif kind == "function" then
        task()
    elseif kind == "table" then
        if task.Destroy then task:Destroy() end
    end
end

function Maid:Destroy()
    if self.dead then return end
    self.dead = true
    -- Reverse order: children are released before their parents.
    for i = #self.tasks, 1, -1 do
        local ok, err = pcall(Maid.dispose, self.tasks[i])
        if not ok then warn("[UI] teardown: " .. tostring(err)) end
        self.tasks[i] = nil
    end
end

function Maid:count() return #self.tasks end

---------------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------------

-- Rounding = 0 must return an INTEGER, not a float that happens to equal one:
-- division always yields a float, which made the slider read "20.0".
function Utility.round(value, decimals)
    decimals = decimals or 0
    if decimals <= 0 then return math.floor(value + 0.5) end
    local factor = 10 ^ decimals
    return math.floor(value * factor + 0.5) / factor
end

-- Stable display: "20" for an integer, and "0.30" rather than "0.3" when two
-- decimals were asked for.
function Utility.format(value, decimals)
    if (decimals or 0) <= 0 then return tostring(math.floor(value + 0.5)) end
    return string.format("%." .. decimals .. "f", value)
end

function Utility.clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

-- Display container. gethui() hides the interface from PlayerGui, where the
-- game (or another script) could walk it; we fall back if it is missing.
function Utility.screenParent()
    local ok, hidden = pcall(function() return gethui and gethui() end)
    if ok and hidden then return hidden end

    local players = game:GetService("Players")
    local player = players.LocalPlayer
    return player and player:FindFirstChildOfClass("PlayerGui") or nil
end

return Utility
