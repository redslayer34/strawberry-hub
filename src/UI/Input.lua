--=============================================================================
-- INPUT — click, hover and drag, mouse and touch alike
--=============================================================================
--  A single module handles input so components never have to tell a mouse from
--  a finger.
--
--  On dragging: no loop. The tracking connections (InputChanged, InputEnded)
--  are opened only when a drag starts and closed the moment it ends. At rest a
--  window costs one InputBegan connection on its topbar — against one
--  permanent RenderStepped connection per window in the naive approach.
--=============================================================================

local UserInputService = game:GetService("UserInputService")

local Input = {}

-- Input types treated as a press. Touch and mouse are deliberately equivalent
-- everywhere.
local function isPress(inputObject)
    local kind = inputObject.UserInputType
    return kind == Enum.UserInputType.MouseButton1
        or kind == Enum.UserInputType.Touch
end

local function isMove(inputObject)
    local kind = inputObject.UserInputType
    return kind == Enum.UserInputType.MouseMovement
        or kind == Enum.UserInputType.Touch
end

function Input.isTouchDevice()
    local ok, touch = pcall(function() return UserInputService.TouchEnabled end)
    local okMouse, mouse = pcall(function() return UserInputService.MouseEnabled end)
    return (ok and touch) and not (okMouse and mouse)
end

---------------------------------------------------------------------------
-- Activation
---------------------------------------------------------------------------

-- `Activated` covers click, tap and gamepad in one: it is the signal to use
-- for "the user confirmed this element".
function Input.onActivate(button, callback)
    return button.Activated:Connect(function()
        local ok, err = pcall(callback)
        if not ok then warn("[UI] callback: " .. tostring(err)) end
    end)
end

-- Press feedback. Separate from activation: on mobile there is no hover, so
-- the press is the only feedback available.
function Input.onPress(button, onDown, onUp)
    local connections = {}

    connections[#connections + 1] = button.InputBegan:Connect(function(inputObject)
        if isPress(inputObject) and onDown then onDown() end
    end)

    connections[#connections + 1] = button.InputEnded:Connect(function(inputObject)
        if isPress(inputObject) and onUp then onUp() end
    end)

    return connections
end

-- Mouse hover only, on purpose: faking hover on touch leaves elements lit up
-- after the finger is gone.
function Input.onHover(button, onEnter, onLeave)
    local connections = {}

    if onEnter then
        connections[#connections + 1] = button.MouseEnter:Connect(onEnter)
    end
    if onLeave then
        connections[#connections + 1] = button.MouseLeave:Connect(onLeave)
    end

    return connections
end

---------------------------------------------------------------------------
-- Window dragging
---------------------------------------------------------------------------

-- handle : the grab area (topbar). frame : what moves. Returns the permanent
-- connection and a stop function, both for the Maid.
function Input.makeDraggable(frame, handle, options)
    options = options or {}

    local dragging = false
    local startInput, startPosition
    local moveConnection, endConnection

    local function stop()
        dragging = false
        if moveConnection then moveConnection:Disconnect() end
        if endConnection then endConnection:Disconnect() end
        moveConnection, endConnection = nil, nil
    end

    local function update(inputObject)
        local delta = inputObject.Position - startInput
        local goal = UDim2.new(
            startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)

        -- No tween here: interpolating position during a drag introduces a
        -- visible lag between finger and window. Direct tracking is what
        -- actually feels smooth.
        frame.Position = goal
        if options.onDrag then options.onDrag(goal) end
    end

    local begin = handle.InputBegan:Connect(function(inputObject)
        if not isPress(inputObject) then return end

        dragging = true
        startInput = inputObject.Position
        startPosition = frame.Position

        -- Opened only for the duration of the drag, closed right after.
        moveConnection = UserInputService.InputChanged:Connect(function(moved)
            if dragging and isMove(moved) then update(moved) end
        end)

        endConnection = UserInputService.InputEnded:Connect(function(ended)
            if isPress(ended) then stop() end
        end)
    end)

    return begin, stop
end

---------------------------------------------------------------------------
-- Scrubbing a bar (slider)
---------------------------------------------------------------------------

-- Same principle: tracking opens on press, closes on release. `onMove` gets
-- the absolute pointer position; converting it to a value is the slider's job,
-- since only it knows its own geometry.
function Input.makeScrubbable(target, onMove, onRelease)
    local active = false
    local moveConnection, endConnection

    local function stop()
        if not active then return end
        active = false
        if moveConnection then moveConnection:Disconnect() end
        if endConnection then endConnection:Disconnect() end
        moveConnection, endConnection = nil, nil
        if onRelease then onRelease() end
    end

    local begin = target.InputBegan:Connect(function(inputObject)
        if not isPress(inputObject) then return end

        active = true
        -- The initial press counts as a move: clicking the bar must jump the
        -- handle there without having to drag.
        onMove(inputObject.Position)

        moveConnection = UserInputService.InputChanged:Connect(function(moved)
            if active and isMove(moved) then onMove(moved.Position) end
        end)

        endConnection = UserInputService.InputEnded:Connect(function(ended)
            if isPress(ended) then stop() end
        end)
    end)

    return begin, stop
end

---------------------------------------------------------------------------
-- Outside click
---------------------------------------------------------------------------

-- Closes a menu when a press lands outside its area. Used by the Dropdown. The
-- connection opens when the menu opens and closes when it closes: nothing runs
-- while no menu is open.
function Input.onOutsideClick(regions, callback)
    return UserInputService.InputBegan:Connect(function(inputObject)
        if not isPress(inputObject) then return end

        local position = inputObject.Position
        for _, region in ipairs(regions) do
            if region and region.Parent then
                local origin = region.AbsolutePosition
                local size = region.AbsoluteSize
                if position.X >= origin.X and position.X <= origin.X + size.X
                    and position.Y >= origin.Y and position.Y <= origin.Y + size.Y then
                    return
                end
            end
        end

        callback()
    end)
end

return Input
