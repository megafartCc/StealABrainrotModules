local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local Workspace = game:GetService('Workspace')

local localPlayer = Players.LocalPlayer
local module = {}

local Synchronizer = require(ReplicatedStorage:FindFirstChild('Packages') and ReplicatedStorage.Packages:FindFirstChild('Synchronizer') or ReplicatedStorage:WaitForChild('Packages'):WaitForChild('Synchronizer'))

local function getHRP()
    local char = localPlayer and localPlayer.Character
    return char and char:FindFirstChild('HumanoidRootPart')
end

local function getTheme(opts)
    local t = opts.theme or {}
    return {
        accentA = t.accentA or t.accent or Color3.fromRGB(64, 156, 255),
        accentB = t.accentB or t.accent or Color3.fromRGB(0, 204, 204),
        panel2 = t.panel2 or Color3.fromRGB(22, 24, 30),
        text = t.text or Color3.fromRGB(230, 235, 240),
    }
end

local function toTitle(str)
    if type(str) ~= 'string' then
        return ''
    end
    return (str:gsub('^%l', string.upper))
end

local function formatMoney(val)
    if val >= 1e9 then
        return string.format('$%.1fb/s', val / 1e9)
    elseif val >= 1e6 then
        return string.format('$%.1fm/s', val / 1e6)
    elseif val >= 1e3 then
        return string.format('$%.1fk/s', val / 1e3)
    end
    return string.format('$%d/s', val)
end

local function setup(opts)
    local section = opts.section
    if not (section and section.CreateToggle) then
        return nil
    end
    local theme = getTheme(opts)

    local enabled = false
    local mostExpensiveOnly = false
    local visuals = {}
    local connections = {}
    local mostExpensiveTarget = nil

    local function cleanup(target)
        local v = visuals[target]
        if not v then
            return
        end
        for _, inst in pairs({ v.hl, v.esp, v.tracer, v.att0, v.att1 }) do
            pcall(function()
                inst:Destroy()
            end)
        end
        visuals[target] = nil
    end

    local function cleanupAll()
        for target in pairs(visuals) do
            cleanup(target)
        end
        visuals = {}
    end

    local function buildInfoFromStand(stand)
        if not stand or not stand:IsA('Model') then
            return nil
        end
        local parent = stand.Parent
        if not parent or parent.Name ~= 'AnimalPodiums' then
            return nil
        end
        local root = stand:FindFirstChild('Root') or stand.PrimaryPart or stand:FindFirstChildWhichIsA('BasePart', true)
        if not root then
            return nil
        end
        local model = stand:FindFirstChildWhichIsA('Model') or stand:FindFirstChild('Brainrot')
        local resolvedName = stand:GetAttribute('Brainrot') or stand.Name or 'Brainrot'
        if model then
            local attrName = model:GetAttribute('Brainrot') or model:GetAttribute('Name')
            if attrName and attrName ~= '' then
                resolvedName = attrName
            end
        end
        local moneyAttr = stand:GetAttribute('MoneyPerSec') or (model and model:GetAttribute('MoneyPerSec'))
        local moneyValue = tonumber(moneyAttr) or 0
        return {
            key = stand,
            root = root,
            model = model,
            name = resolvedName,
            moneyValue = moneyValue,
            moneyText = formatMoney(moneyValue),
        }
    end

    local function refreshMostExpensive()
        mostExpensiveTarget = nil
        local bestVal = -math.huge
        for target, v in pairs(visuals) do
            if v.moneyValue and v.moneyValue > bestVal then
                bestVal = v.moneyValue
                mostExpensiveTarget = target
            end
        end
    end

    local function ensureVisual(info)
        if not info or not info.root then
            return
        end
        local target = info.key
        local v = visuals[target]
        if not v then
            v = {
                moneyValue = info.moneyValue or 0,
                name = info.name or 'Brainrot',
            }
            v.hl = Instance.new('Highlight')
            v.hl.FillColor = theme.accentA
            v.hl.OutlineColor = theme.accentB
            v.hl.FillTransparency = 0.35
            v.hl.OutlineTransparency = 0.1
            v.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            v.hl.Adornee = info.model or info.root
            v.hl.Parent = info.model or info.root

            v.esp = Instance.new('BillboardGui')
            v.esp.Name = 'BrainrotESP'
            v.esp.AlwaysOnTop = true
            v.esp.Adornee = info.root
            v.esp.Size = UDim2.new(0, 140, 0, 30)
            v.esp.Parent = info.root

            local bg = Instance.new('Frame')
            bg.Size = UDim2.new(1, 0, 1, 0)
            bg.BackgroundColor3 = theme.panel2
            bg.BackgroundTransparency = 0.2
            bg.BorderSizePixel = 0
            bg.Parent = v.esp
            local corner = Instance.new('UICorner')
            corner.CornerRadius = UDim.new(0, 6)
            corner.Parent = bg
            local stroke = Instance.new('UIStroke')
            stroke.Color = theme.accentA
            stroke.Thickness = 1
            stroke.Parent = bg

            v.label = Instance.new('TextLabel')
            v.label.BackgroundTransparency = 1
            v.label.Size = UDim2.new(1, -6, 1, -4)
            v.label.Position = UDim2.new(0, 3, 0, 2)
            v.label.Font = Enum.Font.GothamBold
            v.label.TextColor3 = theme.text
            v.label.RichText = true
            v.label.TextScaled = false
            v.label.TextSize = 13
            v.label.TextWrapped = true
            v.label.Parent = bg

            v.att0 = Instance.new('Attachment', getHRP() or info.root)
            v.att1 = Instance.new('Attachment', info.root)
            v.tracer = Instance.new('Beam', info.root)
            v.tracer.Attachment0 = v.att0
            v.tracer.Attachment1 = v.att1
            v.tracer.FaceCamera = true
            v.tracer.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, theme.accentA),
                ColorSequenceKeypoint.new(1, theme.accentB),
            })
            v.tracer.Width0 = 0.2
            v.tracer.Width1 = 0.1
            v.tracer.Transparency = NumberSequence.new(0.35)

            visuals[target] = v
        end
        v.root = info.root
        v.model = info.model
        v.moneyValue = info.moneyValue or 0
        v.moneyText = info.moneyText or '$0/s'
        v.name = info.name or 'Brainrot'
        if v.att1.Parent ~= info.root then
            v.att1.Parent = info.root
        end
        v.tracer.Attachment1 = v.att1
        v.esp.Adornee = info.root
        v.hl.Adornee = info.model or info.root or target
        v.hl.Parent = info.model or target or info.root
        v.label.Text = string.format('%s\n<font color="#ffd700">%s</font>', toTitle(v.name), v.moneyText or '')
    end

    local function rescan()
        if not enabled then
            return
        end
        cleanupAll()
        for _, stand in ipairs(Workspace:GetDescendants()) do
            if stand:IsA('Model') and stand.Parent and stand.Parent.Name == 'AnimalPodiums' then
                local info = buildInfoFromStand(stand)
                if info then
                    ensureVisual(info)
                end
            end
        end
        refreshMostExpensive()
    end

    local function updateVisibility()
        local hrp = getHRP()
        if not hrp then
            return
        end
        for target, v in pairs(visuals) do
            local shouldShow = enabled
            if mostExpensiveOnly and target ~= mostExpensiveTarget then
                shouldShow = false
            end
            if v.hl then
                v.hl.Enabled = shouldShow
            end
            if v.esp then
                v.esp.Enabled = shouldShow
                if shouldShow then
                    local dist = (hrp.Position - v.root.Position).Magnitude
                    v.esp.StudsOffset = Vector3.new(0, math.clamp(4 + (dist / 50), 4, 10), 0)
                end
            end
            if v.tracer then
                v.tracer.Enabled = shouldShow
                if shouldShow and v.att0 then
                    v.att0.Parent = hrp
                end
            end
        end
    end

    local function onAdded(desc)
        if not enabled then
            return
        end
        if desc:IsA('Model') and desc.Parent and desc.Parent.Name == 'AnimalPodiums' then
            local info = buildInfoFromStand(desc)
            if info then
                ensureVisual(info)
                refreshMostExpensive()
            end
        end
    end

    local function onRemoving(desc)
        if desc and visuals[desc] then
            cleanup(desc)
            refreshMostExpensive()
        end
    end

    local renderConn
    local function start()
        if enabled then
            return
        end
        enabled = true
        rescan()
        if not renderConn then
            renderConn = RunService.RenderStepped:Connect(function()
                updateVisibility()
            end)
        end
        if not connections.added then
            connections.added = Workspace.DescendantAdded:Connect(onAdded)
        end
        if not connections.removing then
            connections.removing = Workspace.DescendantRemoving:Connect(onRemoving)
        end
    end

    local function stop()
        enabled = false
        if renderConn then
            renderConn:Disconnect()
            renderConn = nil
        end
        for _, c in pairs(connections) do
            if typeof(c) == 'RBXScriptConnection' then
                c:Disconnect()
            end
        end
        connections = {}
        cleanupAll()
    end

    local brainrotToggle = section:CreateToggle({
        Title = 'Brainrot ESP',
        Default = false,
        SaveKey = 'brainrot_esp_enabled',
        Callback = function(state)
            if state then
                start()
            else
                stop()
            end
        end,
    })

    local mostExpensiveToggle = section:CreateToggle({
        Title = 'Most Expensive Only',
        Default = false,
        SaveKey = 'most_expensive_only_enabled',
        Callback = function(state)
            mostExpensiveOnly = state
            refreshMostExpensive()
            updateVisibility()
        end,
    })

    return {
        start = start,
        stop = stop,
        brainrotToggle = brainrotToggle,
        mostExpensiveToggle = mostExpensiveToggle,
        setTheme = function(newTheme)
            theme = getTheme({ theme = newTheme })
            for _, v in pairs(visuals) do
                if v.hl then
                    v.hl.FillColor = theme.accentA
                    v.hl.OutlineColor = theme.accentB
                end
                if v.tracer then
                    v.tracer.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, theme.accentA),
                        ColorSequenceKeypoint.new(1, theme.accentB),
                    })
                end
                if v.esp then
                    local bg = v.esp:FindFirstChildWhichIsA('Frame')
                    if bg then
                        bg.BackgroundColor3 = theme.panel2
                        local stroke = bg:FindFirstChildOfClass('UIStroke')
                        if stroke then
                            stroke.Color = theme.accentA
                        end
                    end
                end
            end
        end,
    }
end

module.setup = setup

local function autoAttach()
    local env
    pcall(function()
        env = getgenv and getgenv()
    end)
    if not env then
        return
    end
    local targetSection = env.BrainrotESPSection or env.PlayerESPSection or (env.sections and env.sections.esp)
    if targetSection and targetSection.CreateToggle then
        module.instance = setup({
            section = targetSection,
            theme = env.PlayerESPTheme or env.BrainrotESPTheme or {},
            defaultColor = env.PlayerESPDefaultColor,
        })
    end
end

autoAttach()

return module
