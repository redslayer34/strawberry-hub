--=============================================================================
-- FLUENT — downloads the Fluent UI library and its two addons
--=============================================================================
--  https://github.com/dawid-scripts/Fluent -- loaded exactly as its README
--  says: the latest release for the library, the master branch for the
--  addons. Nothing of Fluent is bundled, so the hub always gets its fixes.
--
--  The library is required; the addons are optional (without them the hub
--  works, it just cannot save settings or switch themes).
--=============================================================================

local FluentLoader = {}

FluentLoader.URLS = {
    library = "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua",
    saveManager = "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua",
    interfaceManager = "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua",
}

-- Replaceable in tests, where there is no network.
function FluentLoader.fetch(url)
    local source = game:HttpGet(url)
    local compile = loadstring or load
    local chunk, err = compile(source)
    if not chunk then
        error("could not compile " .. url .. ": " .. tostring(err), 0)
    end
    return chunk()
end

-- Returns library, saveManager, interfaceManager. Errors only when the
-- library itself cannot be loaded.
function FluentLoader.load()
    local library = FluentLoader.fetch(FluentLoader.URLS.library)
    if type(library) ~= "table" or not library.CreateWindow then
        error("Fluent did not return a library", 0)
    end

    local function addon(url)
        local ok, result = pcall(FluentLoader.fetch, url)
        if ok and type(result) == "table" then return result end
        warn("[Strawberry Hub] Fluent addon unavailable (" .. url .. "): " .. tostring(result))
        return nil
    end

    return library, addon(FluentLoader.URLS.saveManager), addon(FluentLoader.URLS.interfaceManager)
end

return FluentLoader
