--=============================================================================
-- FAKE FLUENT — stands in for github.com/dawid-scripts/Fluent in the tests
--=============================================================================
--  Draws nothing. What it does reproduce is what can break the hub:
--    - the real library's asserts, message for message (a missing slider
--      field stops a tab and everything after it);
--    - Window.lua reading Config.Size.X.Offset with no default;
--    - Library:Round returning a STRING for whole numbers when Rounding > 0;
--    - Options registration by Idx, callbacks fired by SetValue, a toggle
--      and a slider firing their callback once at creation;
--    - SaveManager / InterfaceManager methods the hub calls.
--
--  newFakeFluent() returns library, saveManager, interfaceManager, and a
--  `record` table the tests inspect.
--=============================================================================

function newFakeFluent()
    local record = {
        windowConfig = nil,
        tabs = {},
        sections = {},
        buttons = {},
        paragraphs = {},
        notifications = {},
        dialogs = {},
        duplicates = {},
        saves = {},
        autoloadCalls = 0,
        minimized = 0,
    }

    local Library = {
        Version = "1.1.0",
        Options = {},
        Unloaded = false,
        Window = nil,
    }

    -- Verbatim behaviour of Fluent's Library:Round.
    function Library:Round(number, factor)
        if factor == 0 then return math.floor(number) end
        number = tostring(number)
        return number:find("%.") and tonumber(number:sub(1, number:find("%.") + factor)) or number
    end

    function Library:SafeCallback(fn, ...)
        if not fn then return end
        local ok, err = pcall(fn, ...)
        if not ok then
            record.callbackErrors = record.callbackErrors or {}
            record.callbackErrors[#record.callbackErrors + 1] = err
        end
    end

    function Library:Notify(config)
        record.notifications[#record.notifications + 1] = config
    end

    function Library:Destroy()
        Library.Unloaded = true
        record.destroyed = true
    end

    local function register(idx, element)
        if Library.Options[idx] ~= nil then
            record.duplicates[#record.duplicates + 1] = idx
        end
        Library.Options[idx] = element
    end

    local function element(title, description)
        local e = { Title = title, Description = description }
        function e:SetTitle(text) self.Title = text end
        function e:SetDesc(text) self.Description = text end
        return e
    end

    local Elements = {}
    Elements.__index = Elements

    function Elements:AddToggle(idx, config)
        assert(config.Title, "Toggle - Missing Title")
        local toggle = element(config.Title, config.Description)
        toggle.Type = "Toggle"
        toggle.Value = config.Default or false
        toggle.Callback = config.Callback or function() end
        function toggle:OnChanged(fn) toggle.Changed = fn; fn(toggle.Value) end
        function toggle:SetValue(value)
            toggle.Value = not not value
            Library:SafeCallback(toggle.Callback, toggle.Value)
            Library:SafeCallback(toggle.Changed, toggle.Value)
        end
        toggle:SetValue(toggle.Value)
        register(idx, toggle)
        return toggle
    end

    function Elements:AddSlider(idx, config)
        assert(config.Title, "Slider - Missing Title.")
        assert(config.Default, "Slider - Missing default value.")
        assert(config.Min, "Slider - Missing minimum value.")
        assert(config.Max, "Slider - Missing maximum value.")
        assert(config.Rounding, "Slider - Missing rounding value.")
        local slider = element(config.Title, config.Description)
        slider.Type = "Slider"
        slider.Min, slider.Max, slider.Rounding = config.Min, config.Max, config.Rounding
        slider.Callback = config.Callback or function() end
        function slider:OnChanged(fn) slider.Changed = fn; fn(slider.Value) end
        function slider:SetValue(value)
            slider.Value = Library:Round(math.clamp(tonumber(value), slider.Min, slider.Max), slider.Rounding)
            Library:SafeCallback(slider.Callback, slider.Value)
            Library:SafeCallback(slider.Changed, slider.Value)
        end
        slider:SetValue(config.Default)
        register(idx, slider)
        return slider
    end

    function Elements:AddDropdown(idx, config)
        local dropdown = element(config.Title, config.Description)
        dropdown.Type = "Dropdown"
        dropdown.Values = config.Values or {}
        dropdown.Multi = config.Multi
        dropdown.Callback = config.Callback or function() end
        local default = config.Default
        if config.Multi then
            dropdown.Value = {}
            for _, value in ipairs(type(default) == "table" and default or {}) do
                if table.find(dropdown.Values, value) then dropdown.Value[value] = true end
            end
        elseif type(default) == "number" then
            dropdown.Value = dropdown.Values[default]
        elseif type(default) == "string" and table.find(dropdown.Values, default) then
            dropdown.Value = default
        end
        function dropdown:OnChanged(fn) dropdown.Changed = fn end
        function dropdown:SetValues(values) dropdown.Values = values end
        function dropdown:SetValue(value)
            if dropdown.Multi then
                local set = {}
                for key, on in pairs(type(value) == "table" and value or {}) do
                    if on and table.find(dropdown.Values, key) then set[key] = true end
                end
                value = set
            elseif value ~= nil and not table.find(dropdown.Values, value) then
                value = nil
            end
            dropdown.Value = value
            Library:SafeCallback(dropdown.Callback, dropdown.Value)
            Library:SafeCallback(dropdown.Changed, dropdown.Value)
        end
        register(idx, dropdown)
        return dropdown
    end

    function Elements:AddInput(idx, config)
        assert(config.Title, "Input - Missing Title")
        local input = element(config.Title, config.Description)
        input.Type = "Input"
        input.Value = config.Default or ""
        function input:SetValue(value) input.Value = value end
        function input:OnChanged(fn) input.Changed = fn end
        register(idx, input)
        return input
    end

    function Elements:AddKeybind(idx, config)
        assert(config.Title, "KeyBind - Missing Title")
        assert(config.Default, "KeyBind - Missing default value.")
        local keybind = element(config.Title, config.Description)
        keybind.Type = "Keybind"
        keybind.Value = config.Default
        function keybind:OnChanged(fn) keybind.Changed = fn end
        function keybind:OnClick(fn) keybind.Clicked = fn end
        function keybind:SetValue(value) keybind.Value = value end
        register(idx, keybind)
        return keybind
    end

    function Elements:AddColorpicker(idx, config)
        assert(config.Title, "Colorpicker - Missing Title")
        assert(config.Default, "AddColorPicker: Missing default value.")
        local picker = element(config.Title, config.Description)
        picker.Type = "Colorpicker"
        picker.Value = config.Default
        register(idx, picker)
        return picker
    end

    -- Button and Paragraph take a single argument (no Idx) in Fluent.
    function Elements:AddButton(config)
        assert(config.Title, "Button - Missing Title")
        local button = element(config.Title, config.Description)
        button.Callback = config.Callback or function() end
        function button:Click() Library:SafeCallback(button.Callback) end
        record.buttons[config.Title] = button
        return button
    end

    function Elements:AddParagraph(config)
        assert(config.Title, "Paragraph - Missing Title")
        local paragraph = element(config.Title, config.Content or "")
        record.paragraphs[config.Title] = paragraph
        return paragraph
    end

    local function newTab(title)
        local tab = setmetatable({ Title = title, Sections = {} }, Elements)
        function tab:AddSection(sectionTitle)
            local section = setmetatable({ Title = sectionTitle }, Elements)
            tab.Sections[#tab.Sections + 1] = section
            record.sections[#record.sections + 1] = sectionTitle
            return section
        end
        return tab
    end

    function Library:CreateWindow(config)
        assert(config.Title, "Window - Missing Title")
        if Library.Window then
            print("You cannot create more than one window.")
            return nil
        end
        -- Window.lua: Camera.ViewportSize.X / 2 - Config.Size.X.Offset / 2
        local _ = config.Size.X.Offset
        record.windowConfig = config

        local window = {}
        function window:AddTab(tabConfig)
            local tab = newTab(tabConfig.Title)
            record.tabs[#record.tabs + 1] = tab
            return tab
        end
        function window:SelectTab(index) record.selectedTab = index end
        function window:Minimize() record.minimized = record.minimized + 1 end
        function window:Dialog(dialogConfig)
            local dialog = { Title = dialogConfig.Title, Buttons = {} }
            for _, button in next, dialogConfig.Buttons do
                dialog.Buttons[#dialog.Buttons + 1] = button
            end
            record.dialogs[#record.dialogs + 1] = dialog
        end

        Library.Window = window
        return window
    end

    local SaveManager = { Folder = "FluentSettings", Ignore = {} }

    function SaveManager:SetLibrary(library)
        self.Library = library
        self.Options = library.Options
    end
    function SaveManager:SetFolder(folder) self.Folder = folder end
    function SaveManager:IgnoreThemeSettings()
        self:SetIgnoreIndexes({ "InterfaceTheme", "AcrylicToggle", "TransparentToggle", "MenuKeybind" })
    end
    function SaveManager:SetIgnoreIndexes(list)
        for _, key in next, list do self.Ignore[key] = true end
    end
    function SaveManager:Save(name)
        local snapshot = {}
        for idx, option in next, self.Options do
            if not self.Ignore[idx] then snapshot[idx] = option.Value end
        end
        record.saves[#record.saves + 1] = { name = name, values = snapshot }
        return true
    end
    function SaveManager:LoadAutoloadConfig()
        record.autoloadCalls = record.autoloadCalls + 1
        local saved = record.savedConfig
        if saved then
            for idx, value in pairs(saved) do
                if self.Options[idx] then self.Options[idx]:SetValue(value) end
            end
        end
    end
    function SaveManager:BuildConfigSection(tab)
        assert(self.Library, "Must set SaveManager.Library")
        local section = tab:AddSection("Configuration")
        section:AddInput("SaveManager_ConfigName", { Title = "Config name" })
        section:AddDropdown("SaveManager_ConfigList", { Title = "Config list", Values = {}, AllowNull = true })
        section:AddButton({ Title = "Create config", Callback = function() end })
    end

    local InterfaceManager = {}
    function InterfaceManager:SetLibrary(library) self.Library = library end
    function InterfaceManager:SetFolder(folder) self.Folder = folder end
    function InterfaceManager:BuildInterfaceSection(tab)
        assert(self.Library, "Must set InterfaceManager.Library")
        local section = tab:AddSection("Interface")
        section:AddDropdown("InterfaceTheme", { Title = "Theme", Values = { "Dark", "Light" }, Default = "Dark" })
        section:AddToggle("AcrylicToggle", { Title = "Acrylic", Default = false })
        section:AddToggle("TransparentToggle", { Title = "Transparency", Default = true })
        section:AddKeybind("MenuKeybind", { Title = "Minimize Bind", Default = "LeftControl" })
    end

    return Library, SaveManager, InterfaceManager, record
end
