--=============================================================================
-- FACADE — the strawberry window library, spoken to like Fluent
--=============================================================================
--  The tabs, Bind and Interface were written for Fluent. UI.Library (Banana
--  Hub's window, in red) has close but different calls, so this turns one
--  into the other, and the tabs stay as they are:
--
--    Library:CreateWindow / Notify / Destroy / Options[idx]
--    Window:AddTab / SelectTab / Dialog / Minimize
--    Tab:AddSection (and elements straight on a tab)
--    Section:AddToggle / AddSlider / AddDropdown (single, multi) / AddInput
--            / AddButton / AddParagraph
--
--  Facade.saveManager() stands in for Fluent's SaveManager, in its file
--  format (settings/<name>.json with { objects = { {type, idx, value} } }),
--  so the settings saved by the Fluent window load in this one.
--
--  `core` is UI.Library's table; tests pass a fake one.
--=============================================================================

local Services = require("Core.Services")

local Facade = {}

Facade.SEARCH_FROM = 8    -- dropdowns with this many values get a search box

local function safe(fn, ...)
    if not fn then return end
    local ok, err = pcall(fn, ...)
    if not ok then warn("[Strawberry Hub] UI callback: " .. tostring(err)) end
end

local function copySet(set)
    local out = {}
    for key, on in pairs(set) do if on then out[key] = true end end
    return out
end

---------------------------------------------------------------------------
-- Elements
---------------------------------------------------------------------------

local function newSection(library, coreSection)
    local section = {}

    local function register(idx, option)
        if idx ~= nil then library.Options[idx] = option end
        return option
    end

    function section:AddToggle(idx, config)
        local option = { Type = "Toggle", Value = config.Default == true }
        local control = coreSection:AddToggle(idx, {
            Title = config.Title,
            Desc = config.Description,
            Default = option.Value,
            Callback = function(value)
                option.Value = value == true
                safe(config.Callback, option.Value)
                safe(option.changed, option.Value)
            end,
        })
        function option:SetValue(value)
            value = value == true
            if control and control.SetStage then
                control.SetStage(value)
            end
            if option.Value ~= value then
                option.Value = value
                safe(config.Callback, value)
            end
        end
        function option:OnChanged(fn) option.changed = fn end
        return register(idx, option)
    end

    function section:AddSlider(idx, config)
        local option = { Type = "Slider", Value = tonumber(config.Default) or config.Min or 0 }
        local control = coreSection:AddSlider({
            Title = config.Title,
            Min = config.Min,
            Max = config.Max,
            Default = option.Value,
            Precise = (tonumber(config.Rounding) or 0) > 0,
            Callback = function(value)
                local number = tonumber(value)
                if number == nil then return end
                option.Value = number
                safe(config.Callback, number)
                safe(option.changed, number)
            end,
        })
        function option:SetValue(value)
            local number = tonumber(value)
            if number == nil then return end
            if control and control.SetValue then control.SetValue(number) end
            if option.Value ~= number then
                option.Value = number
                safe(config.Callback, number)
            end
        end
        function option:OnChanged(fn) option.changed = fn end
        return register(idx, option)
    end

    function section:AddDropdown(idx, config)
        local values = config.Values or {}
        local multi = config.Multi == true
        local option = { Type = "Dropdown", Multi = multi, Values = values }
        local control
        if multi then
            option.Value = {}
            for _, name in ipairs(type(config.Default) == "table" and config.Default or {}) do
                option.Value[name] = true
            end
            control = coreSection:AddDropdown(idx, {
                Title = config.Title,
                Values = values,
                Multi = true,
                Search = #values >= Facade.SEARCH_FROM,
                Callback = function(name, on)
                    option.Value[name] = on and true or nil
                    local set = copySet(option.Value)
                    safe(config.Callback, set)
                    safe(option.changed, set)
                end,
            })
            -- Ticks the saved choices (the library starts with none).
            local wanted = copySet(option.Value)
            for name in pairs(wanted) do
                if control and control.SetValue then pcall(control.SetValue, control, name) end
            end
            option.Value = wanted
        else
            option.Value = config.Default
            control = coreSection:AddDropdown(idx, {
                Title = config.Title,
                Values = values,
                Default = type(config.Default) == "string" and config.Default or nil,
                Search = #values >= Facade.SEARCH_FROM,
                Callback = function(value)
                    option.Value = value
                    safe(config.Callback, value)
                    safe(option.changed, value)
                end,
            })
        end
        function option:SetValues(list)
            option.Values = list
            if control and control.GetNewList then control:GetNewList(list) end
        end
        function option:SetValue(value)
            if multi then
                local set = type(value) == "table" and value or {}
                for name, on in pairs(set) do
                    if on and not option.Value[name] and control and control.SetValue then
                        pcall(control.SetValue, control, name)
                    end
                end
                option.Value = copySet(set)
                safe(config.Callback, copySet(set))
            else
                if control and control.SetValue then pcall(control.SetValue, control, value) end
                if option.Value ~= value then
                    option.Value = value
                    safe(config.Callback, value)
                end
            end
        end
        function option:OnChanged(fn) option.changed = fn end
        return register(idx, option)
    end

    function section:AddInput(idx, config)
        local option = { Type = "Input", Value = tostring(config.Default or "") }
        local control = coreSection:AddInput(idx, {
            Title = config.Title,
            Default = option.Value,
            Placeholder = config.Placeholder or "",
            Numeric = config.Numeric == true,
            Callback = function(text)
                option.Value = tostring(text or "")
                safe(config.Callback, option.Value)
                safe(option.changed, option.Value)
            end,
        })
        function option:SetValue(text)
            text = tostring(text or "")
            if control and control.SetValue then pcall(control.SetValue, text) end
            if option.Value ~= text then
                option.Value = text
                safe(config.Callback, text)
            end
        end
        function option:OnChanged(fn) option.changed = fn end
        return register(idx, option)
    end

    function section:AddButton(config)
        local button = coreSection:AddButton({
            Title = config.Title,
            Callback = function() safe(config.Callback) end,
        })
        return button or {}
    end

    -- A paragraph is a label: "Title: content" (content on its own when
    -- there is no title).
    function section:AddParagraph(config)
        local title, content = config.Title or "", config.Content or ""
        local function text()
            if title == "" then return content end
            if content == "" then return title end
            return title .. ": " .. content
        end
        local label = coreSection:AddLabel(text())
        local paragraph = {}
        function paragraph:SetDesc(value)
            content = tostring(value or "")
            if label and label.SetText then pcall(label.SetText, label, text()) end
        end
        function paragraph:SetTitle(value)
            title = tostring(value or "")
            if label and label.SetText then pcall(label.SetText, label, text()) end
        end
        return paragraph
    end

    return section
end

---------------------------------------------------------------------------
-- Dialog (the library has none): a small modal in the same colours
---------------------------------------------------------------------------

local RED = Color3.fromRGB(230, 46, 76)
local BACK = Color3.fromRGB(30, 18, 24)
local TEXT = Color3.fromRGB(235, 235, 230)

local function dialog(config)
    local gui = Instance.new("ScreenGui")
    gui.Name = "StrawberryHubDialog"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 50
    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.Size = UDim2.new(0, 320, 0, 150)
    frame.BackgroundColor3 = BACK
    frame.BorderSizePixel = 0
    frame.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = RED
    stroke.Thickness = 2
    stroke.Parent = frame
    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 12, 0, 8)
    title.Size = UDim2.new(1, -24, 0, 24)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextColor3 = RED
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "🍓 " .. tostring(config.Title or "")
    title.Parent = frame
    local content = Instance.new("TextLabel")
    content.BackgroundTransparency = 1
    content.Position = UDim2.new(0, 12, 0, 36)
    content.Size = UDim2.new(1, -24, 0, 60)
    content.Font = Enum.Font.Gotham
    content.TextSize = 14
    content.TextWrapped = true
    content.TextColor3 = TEXT
    content.TextXAlignment = Enum.TextXAlignment.Left
    content.TextYAlignment = Enum.TextYAlignment.Top
    content.Text = tostring(config.Content or "")
    content.Parent = frame
    local buttons = config.Buttons or { { Title = "OK" } }
    local width = (320 - 12 * (#buttons + 1)) / #buttons
    for index, entry in ipairs(buttons) do
        local button = Instance.new("TextButton")
        button.Position = UDim2.new(0, 12 + (index - 1) * (width + 12), 1, -42)
        button.Size = UDim2.new(0, width, 0, 30)
        button.BackgroundColor3 = index == 1 and RED or Color3.fromRGB(52, 32, 38)
        button.BorderSizePixel = 0
        button.Font = Enum.Font.GothamBold
        button.TextSize = 14
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.Text = tostring(entry.Title or "")
        button.Parent = frame
        local buttonCorner = Instance.new("UICorner")
        buttonCorner.CornerRadius = UDim.new(0, 6)
        buttonCorner.Parent = button
        button.MouseButton1Click:Connect(function()
            pcall(function() gui:Destroy() end)
            safe(entry.Callback)
        end)
    end
    gui.Parent = Services.guiParent()
    return gui
end

---------------------------------------------------------------------------
-- Library and window
---------------------------------------------------------------------------

function Facade.wrap(core)
    local library = { Options = {}, Unloaded = false, Core = core }
    local connections = {}

    function library:Notify(config)
        local content = tostring(config.Content or "")
        if config.SubContent and config.SubContent ~= "" then
            content = content .. "\n" .. tostring(config.SubContent)
        end
        pcall(core.Notify, core, { Title = config.Title, Content = content, Duration = config.Duration })
    end

    function library:CreateWindow(config)
        local coreWindow = core:CreateWindow({
            Title = config.Title,
            Subtitle = config.SubTitle,
        })
        if not coreWindow then return nil end
        local window = { HasToggleButton = true, Tabs = {} }

        function window:AddTab(tabConfig)
            local page = coreWindow:AddTab(type(tabConfig) == "table" and tabConfig.Title or tostring(tabConfig))
            local tab = { Title = type(tabConfig) == "table" and tabConfig.Title or tostring(tabConfig) }
            local default
            function tab:AddSection(title)
                return newSection(library, page:AddLeftGroupbox(title))
            end
            -- Elements added straight on a tab go into one untitled section.
            for _, method in ipairs({ "AddToggle", "AddSlider", "AddDropdown", "AddInput", "AddButton", "AddParagraph" }) do
                tab[method] = function(_, ...)
                    default = default or newSection(library, page:AddLeftGroupbox(""))
                    return default[method](default, ...)
                end
            end
            window.Tabs[#window.Tabs + 1] = tab
            return tab
        end

        function window:SelectTab() end
        function window:Minimize()
            if core.ToggleUI then pcall(core.ToggleUI) end
        end
        function window:Dialog(dialogConfig)
            local ok, gui = pcall(dialog, dialogConfig)
            return ok and gui or nil
        end

        -- Show it, and the hide key (Fluent's MinimizeKey).
        if core.ToggleUI then pcall(core.ToggleUI) end
        local key = config.MinimizeKey
        if key then
            local okInput, input = pcall(Services.get, "UserInputService")
            if okInput and input and input.InputBegan then
                connections[#connections + 1] = input.InputBegan:Connect(function(event, processed)
                    if not processed and event.KeyCode == key then window:Minimize() end
                end)
            end
        end
        library.Window = window
        return window
    end

    function library:Destroy()
        library.Unloaded = true
        for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
        connections = {}
        if core.DestroyUI then pcall(core.DestroyUI) end
    end

    return library
end

---------------------------------------------------------------------------
-- Saving (Fluent SaveManager's file format)
---------------------------------------------------------------------------

function Facade.saveManager()
    local manager = { Folder = "StrawberryHub/BloxFruits", Ignore = {} }
    local library

    local function ensureFolders()
        if not (makefolder and isfolder) then return end
        local path = ""
        for part in string.gmatch(manager.Folder .. "/settings", "[^/]+") do
            path = path == "" and part or (path .. "/" .. part)
            if not isfolder(path) then pcall(makefolder, path) end
        end
    end

    local function file(name)
        return manager.Folder .. "/settings/" .. name .. ".json"
    end

    function manager:SetLibrary(value) library = value end
    function manager:IgnoreThemeSettings() end
    function manager:SetIgnoreIndexes(list)
        for _, idx in ipairs(list or {}) do manager.Ignore[idx] = true end
    end
    function manager:SetFolder(folder)
        manager.Folder = folder
        ensureFolders()
    end

    function manager:Save(name)
        if not (library and writefile) then return false, "no file access" end
        ensureFolders()
        local objects = {}
        for idx, option in pairs(library.Options) do
            if not manager.Ignore[idx] then
                local value = option.Value
                if option.Type == "Dropdown" and option.Multi then value = copySet(value or {}) end
                if option.Type == "Slider" then value = tostring(value) end
                objects[#objects + 1] = { type = option.Type, idx = idx, value = value, multi = option.Multi }
            end
        end
        table.sort(objects, function(a, b) return tostring(a.idx) < tostring(b.idx) end)
        local http = Services.get("HttpService")
        local ok, encoded = pcall(http.JSONEncode, http, { objects = objects })
        if not ok then return false, "encode failed" end
        local written = pcall(writefile, file(name), encoded)
        return written, written and nil or "write failed"
    end

    function manager:Load(name)
        if not (library and readfile and isfile) then return false, "no file access" end
        if not isfile(file(name)) then return false, "no config " .. tostring(name) end
        local http = Services.get("HttpService")
        local ok, decoded = pcall(function() return http:JSONDecode(readfile(file(name))) end)
        if not ok or type(decoded) ~= "table" then return false, "decode failed" end
        for _, object in ipairs(decoded.objects or {}) do
            local option = library.Options[object.idx]
            if option and not manager.Ignore[object.idx] then
                local value = object.value
                if option.Type == "Input" then value = object.text or value end
                if option.Type == "Dropdown" and option.Multi and type(value) == "table" and value[1] ~= nil then
                    local set = {}
                    for _, name in ipairs(value) do set[name] = true end
                    value = set
                end
                pcall(option.SetValue, option, value)
            end
        end
        return true
    end

    function manager:LoadAutoloadConfig()
        local name = "autosave"
        if isfile and readfile and isfile(manager.Folder .. "/settings/autoload.txt") then
            local okRead, text = pcall(readfile, manager.Folder .. "/settings/autoload.txt")
            if okRead and type(text) == "string" and text ~= "" then name = text end
        end
        return manager:Load(name)
    end

    function manager:BuildConfigSection(tab)
        local section = tab:AddSection("Configuration")
        section:AddParagraph({ Title = "Saved automatically", Content = manager.Folder .. "/settings/autosave.json" })
        section:AddButton({ Title = "Save now", Callback = function() manager:Save("autosave") end })
        section:AddButton({ Title = "Reload saved settings", Callback = function() manager:Load("autosave") end })
    end

    return manager
end

-- The bundled library, wrapped: library, saveManager. Errors when the
-- window library cannot be built (main.lua then falls back to Fluent).
function Facade.load()
    local core = require("UI.Library")
    if type(core) ~= "table" or not core.CreateWindow then
        error("the window library did not load", 0)
    end
    return Facade.wrap(core), Facade.saveManager()
end

return Facade
