--=============================================================================
-- INPUT — clic, survol et deplacement, souris comme tactile
--=============================================================================
--  Un seul module traite les entrees, pour que les composants n'aient jamais
--  a distinguer souris et doigt.
--
--  Sur le deplacement : aucune boucle. Les connexions de suivi (InputChanged,
--  InputEnded) ne sont ouvertes qu'au moment ou le drag commence, et fermees
--  des qu'il finit. Au repos, une fenetre ne coute qu'une seule connexion
--  InputBegan sur sa barre de titre — contre une connexion RenderStepped
--  permanente par fenetre dans l'approche naive.
--=============================================================================

local UserInputService = game:GetService("UserInputService")

local Input = {}

-- Types d'entree traites comme un appui. Le tactile et la souris sont
-- volontairement equivalents partout.
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

-- `Activated` couvre le clic, le tap et la manette d'un seul coup : c'est le
-- signal a utiliser pour "l'utilisateur a valide cet element".
function Input.onActivate(button, callback)
    return button.Activated:Connect(function()
        local ok, err = pcall(callback)
        if not ok then warn("[UI] callback : " .. tostring(err)) end
    end)
end

-- Retour visuel d'appui. Separe de l'activation : sur mobile il n'y a pas de
-- survol, l'appui est le seul retour disponible.
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

-- Survol souris uniquement — volontairement : simuler un survol au doigt
-- laisse des elements allumes apres le retrait du doigt.
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
-- Deplacement de fenetre
---------------------------------------------------------------------------

-- handle : la zone qui saisit (barre de titre). frame : ce qui se deplace.
-- Renvoie la connexion permanente et une fonction d'arret, a confier au Maid.
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

        -- Pas de tween ici : interpoler la position pendant un drag ajoute un
        -- retard visible entre le doigt et la fenetre. Le suivi direct est ce
        -- qui donne la sensation de fluidite.
        frame.Position = goal
        if options.onDrag then options.onDrag(goal) end
    end

    local begin = handle.InputBegan:Connect(function(inputObject)
        if not isPress(inputObject) then return end

        dragging = true
        startInput = inputObject.Position
        startPosition = frame.Position

        -- Ouvertes seulement pendant le drag, refermees juste apres.
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
-- Glissement sur une barre (slider)
---------------------------------------------------------------------------

-- Meme principe : suivi ouvert a l'appui, referme au relachement. `onMove`
-- recoit la position absolue du pointeur ; c'est au slider de la convertir
-- en valeur, lui seul connaissant sa geometrie.
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
        -- Le premier appui compte comme un deplacement : cliquer sur la barre
        -- doit deplacer le curseur sans avoir a glisser.
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
-- Clic exterieur
---------------------------------------------------------------------------

-- Ferme un menu quand l'appui tombe hors de sa zone. Utilise par le
-- Dropdown. La connexion est ouverte a l'ouverture du menu et fermee a sa
-- fermeture : rien ne tourne quand aucun menu n'est ouvert.
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
