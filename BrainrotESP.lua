local Library = loadstring(game:HttpGet('https://pastebin.com/raw/Pr7SkYS8'))()
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local Workspace = game:GetService('Workspace')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local localPlayer = Players.LocalPlayer
local THEME = Library.Theme or {}
local DEFAULT_ACCENT = THEME.accent or Color3.fromRGB(50, 130, 250)

-- Setup Theme Defaults used by Brainrot ESP
THEME.accentA = THEME.accentA or DEFAULT_ACCENT
THEME.accentB = THEME.accentB or Color3.fromRGB(0, 204, 204)
THEME.panel2 = THEME.panel2 or Color3.fromRGB(22, 24, 30)
THEME.text = THEME.text or Color3.fromRGB(230, 235, 240)
THEME.gold = THEME.gold or Color3.fromRGB(255, 215, 0)

local player = localPlayer
local Character = player and player.Character or nil
local Humanoid = Character and Character:FindFirstChildOfClass('Humanoid')

local function getHRP()
    return Character and Character:FindFirstChild('HumanoidRootPart')
end

if player then
    player.CharacterAdded:Connect(function(char)
        Character = char
        Humanoid = char:WaitForChild('Humanoid', 5)
    end)
    player.CharacterRemoving:Connect(function()
        Character = nil
        Humanoid = nil
    end)
end

local function notify(title, text, dur)
    pcall(function()
        Library:Notify({
            Title = title or 'Info',
            Text = text or '',
            Duration = dur or 3,
            Type = 'Info',
        })
    end)
end

local function safeDisconnectConn(conn)
    if conn and typeof(conn) == 'RBXScriptConnection' then
        pcall(function()
            conn:Disconnect()
        end)
    end
end

local function safeCall(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then
        return res
    end
    return nil
end

local SETTINGS_FILE = 'newsab_settings.json'
Library:InitAutoSave(SETTINGS_FILE)

local window = Library:CreateWindow({
    Title = 'Eps1llon Hub | Steal A Brainrot',
    Theme = 'Premium',
    AutoDetectLanguage = true,
})

local pages = {
    main = window:CreatePage({ Title = 'Main', Icon = 'rbxassetid://132070472411182' }),
    helper = window:CreatePage({ Title = 'Helper', Icon = 'rbxassetid://130200273118631' }),
    stealer = window:CreatePage({ Title = 'Stealer', Icon = 'rbxassetid://138531621616068' }),
    shop = window:CreatePage({ Title = 'Shop', Icon = 'rbxassetid://95979593371652' }),
    autoJoiner = window:CreatePage({ Title = 'Auto Joiner', Icon = 'rbxassetid://122626540897089' }),
    misc = window:CreatePage({ Title = 'Miscellaneous', Icon = 'rbxassetid://81683171903925' }),
    settings = window:CreatePage({ Title = 'Settings', Icon = 'rbxassetid://135452049601292' }),
}

local sections = {
    character = pages.main:CreateSection({
        Title = 'Character',
        Icon = 'rbxassetid://132944044601566',
        HelpText = "Modify your character's movement abilities like speed and jump height.",
    }),
    esp = pages.helper:CreateSection({
        Title = 'ESP',
        Icon = 'rbxassetid://139777701329740',
        HelpText = 'ESP (Extrasensory Perception) lets you see players, items, and other objects through walls.',
    }),
    camera = pages.helper:CreateSection({
        Title = 'Camera X-Ray',
        Icon = 'rbxassetid://93815946105615',
        HelpText = 'Allows your camera to pass through walls, giving you a tactical advantage.',
    }),
    stealerMain = pages.stealer:CreateSection({
        Title = 'Stealer',
        Icon = 'rbxassetid://127132796651849',
        HelpText = 'Tools designed to give you an advantage when stealing items from other players.',
    }),
    combat = pages.stealer:CreateSection({
        Title = 'Combat',
        Icon = 'rbxassetid://119605181458611',
        HelpText = 'Reactive tools to counter enemy weapons.',
    }),
    autoBrainrot = pages.shop:CreateSection({
        Title = 'Auto Brainrot Purchase',
        Icon = 'rbxassetid://88521808497905',
        HelpText = 'This feature is coming soon.',
    }),
    itemPurchase = pages.shop:CreateSection({
        Title = 'Item Purchase',
        Icon = 'rbxassetid://113665504429833',
        HelpText = 'Automatically purchases selected items from the in-game shop.',
    }),
    finder = pages.autoJoiner:CreateSection({
        Title = 'Finder',
        Icon = 'rbxassetid://110882457725395',
        HelpText = 'Automatically finds and joins premium servers with valuable items.',
    }),
    server = pages.misc:CreateSection({
        Title = 'Server',
        Icon = 'rbxassetid://116427573380481',
        HelpText = 'Utilities for managing and changing game servers.',
    }),
    graphics = pages.misc:CreateSection({
        Title = 'Graphics',
        Icon = 'rbxassetid://138347320198139',
        HelpText = 'Enhance visual quality or improve performance by adjusting graphics settings.',
    }),
    world = pages.misc:CreateSection({
        Title = 'World',
        Icon = 'rbxassetid://119605181458611',
        HelpText = 'General world modifications, like preventing AFK kicks.',
    }),
}

local UI = {}
local Modules = {}

local espSection = sections.esp
if not espSection or type(espSection.CreateToggle) ~= 'function' then
    espSection = pages.helper:CreateSection({
        Title = 'ESP',
        Icon = 'rbxassetid://139777701329740',
        HelpText = 'ESP (Extrasensory Perception) lets you see players, items, and other objects through walls.',
    })
    sections.esp = espSection
end

-- Load Player ESP (with cache busting)
local playerEspUrl = 'https://raw.githubusercontent.com/megafartCc/StealABrainrotModules/refs/heads/main/PlayerESP.lua?t=' .. tostring(os.time())
local playerEspModule = loadstring(game:HttpGet(playerEspUrl))()

if playerEspModule and playerEspModule.setup and espSection and espSection.CreateToggle then
    Modules.PlayerESP = playerEspModule.setup({
        section = espSection,
        theme = THEME,
        defaultColor = DEFAULT_ACCENT,
    })
else
    Modules.PlayerESP = playerEspModule
end

-- Load Brainrot ESP (module-based)
do
    local brainrotModule
    -- Prefer remote module with Cache Buster
    local brainrotUrl = 'https://raw.githubusercontent.com/megafartCc/StealABrainrotModules/refs/heads/main/BrainrotESP.lua?t=' .. tostring(os.time())
    
    local okRemote, remoteMod = pcall(function()
        return loadstring(game:HttpGet(brainrotUrl))()
    end)

    if okRemote then
        brainrotModule = remoteMod
    else
        warn('Failed to fetch Brainrot ESP from GitHub, trying local file...')
        pcall(function()
            if readfile then
                local src = readfile('Modules/brainrot_esp.lua')
                brainrotModule = loadstring(src)()
            end
        end)
    end

    if brainrotModule and brainrotModule.setup then
        local brainrot = brainrotModule.setup({
            section = espSection,
            theme = THEME,
            notify = notify,
        })
        Modules.BrainrotESP = brainrot
        if brainrot then
            UI.brainrotEspToggle = brainrot.brainrotToggle
            UI.mostExpensiveToggle = brainrot.mostExpensiveToggle
        end
    else
        warn('Brainrot ESP module missing or failed to load.')
        notify('Error', 'Brainrot Module Failed to Load', 5)
    end
end

function UI:addToggle(pageKey, opts)
    local page = pages[pageKey]
    if not page or not page.CreateToggle then
        return nil
    end
    return page:CreateToggle(opts or {})
end

function UI:addButton(pageKey, opts)
    local page = pages[pageKey]
    if not page or not page.CreateButton then
        return nil
    end
    return page:CreateButton(opts or {})
end

function UI:addSlider(pageKey, opts)
    local page = pages[pageKey]
    if not page or not page.CreateSlider then
        return nil
    end
    return page:CreateSlider(opts or {})
end

-- Export handles for downstream scripts to attach real controls.
return {
    Library = Library,
    Window = window,
    Pages = pages,
    UI = UI,
    SettingsFile = SETTINGS_FILE,
    Modules = Modules,
}
