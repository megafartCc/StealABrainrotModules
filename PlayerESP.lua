local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local module = {}

function module.setup(opts)
    local section = opts.section
    local theme = opts.theme or {}
    local defaultColor = opts.defaultColor or theme.accent or Color3.fromRGB(50, 130, 250)
    local localPlayer = Players.LocalPlayer

    local enabled = false
    local color = defaultColor
    local alpha = 0.6
    local visuals = {}
    local connections = {}

    local function destroy(targetPlayer)
        local ref = visuals[targetPlayer]
        if not ref then
            return
        end
        if ref.adjustConn then
            ref.adjustConn:Disconnect()
        end
        if ref.highlight then
            ref.highlight:Destroy()
        end
        if ref.billboard then
            ref.billboard:Destroy()
        end
        if ref.charConn then
            ref.charConn:Disconnect()
        end
        visuals[targetPlayer] = nil
    end

    local function applyColors()
        for _, ref in pairs(visuals) do
            if ref.highlight then
                ref.highlight.FillColor = color
                ref.highlight.FillTransparency = alpha
                ref.highlight.OutlineColor = Color3.new(color.R * 0.5, color.G * 0.5, color.B * 0.5)
            end
            if ref.stroke then
                ref.stroke.Color = color
                ref.stroke.Transparency = math.max(0, alpha - 0.4)
            end
        end
    end

    local function create(targetPlayer, character)
        if not enabled or not targetPlayer or targetPlayer == localPlayer or not character then
            return
        end
        local head = character:FindFirstChild('Head')
        local hrp = character:FindFirstChild('HumanoidRootPart')
        if not head and not hrp then
            return
        end
        destroy(targetPlayer)
        local highlight = Instance.new('Highlight')
        highlight.Adornee = character
        highlight.FillColor = color
        highlight.FillTransparency = alpha
        highlight.OutlineColor = Color3.new(color.R * 0.5, color.G * 0.5, color.B * 0.5)
        highlight.OutlineTransparency = alpha
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Enabled = true
        highlight.Parent = character

        local billboard = Instance.new('BillboardGui')
        billboard.Adornee = head or hrp
        billboard.Size = UDim2.new(0, 80, 0, 18)
        billboard.StudsOffset = Vector3.new(0, 1.7, 0)
        billboard.AlwaysOnTop = true
        billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        billboard.LightInfluence = 0
        billboard.Parent = character

        local frame = Instance.new('Frame')
        frame.Size = UDim2.new(1, 0, 1, 0)
        frame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
        frame.BackgroundTransparency = 0.5
        frame.BorderSizePixel = 0
        frame.Parent = billboard

        local stroke = Instance.new('UIStroke')
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Thickness = 0.9
        stroke.Color = color
        stroke.Transparency = math.max(0, alpha - 0.4)
        stroke.Parent = frame

        local corner = Instance.new('UICorner')
        corner.CornerRadius = UDim.new(0, 3)
        corner.Parent = frame

        local label = Instance.new('TextLabel')
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.Font = Enum.Font.GothamSemibold
        label.TextColor3 = Color3.fromRGB(230, 235, 240)
        label.TextScaled = true
        label.Text = targetPlayer.DisplayName or targetPlayer.Name
        label.Parent = frame

        local adjustConn
        adjustConn = RunService.Heartbeat:Connect(function()
            if not enabled or not billboard.Parent then
                if adjustConn then
                    adjustConn:Disconnect()
                end
                return
            end
            local cam = workspace.CurrentCamera
            if not cam then
                return
            end
            local targetPos = (head or hrp).Position
            local distance = (cam.CFrame.Position - targetPos).Magnitude
            local extra = math.clamp(distance / 50, 0, 4)
            billboard.StudsOffset = Vector3.new(0, 1.7 + extra, 0)
        end)

        local charConn = character.Destroying:Connect(function()
            destroy(targetPlayer)
        end)

        visuals[targetPlayer] = {
            highlight = highlight,
            billboard = billboard,
            stroke = stroke,
            charConn = charConn,
            adjustConn = adjustConn,
        }
    end

    local function bind(targetPlayer)
        if targetPlayer == localPlayer then
            return
        end
        local function onCharacter(character)
            create(targetPlayer, character)
        end
        if targetPlayer.Character then
            onCharacter(targetPlayer.Character)
        end
        connections[targetPlayer] = targetPlayer.CharacterAdded:Connect(onCharacter)
    end

    local function unbind(targetPlayer)
        destroy(targetPlayer)
        local c = connections[targetPlayer]
        if c then
            c:Disconnect()
            connections[targetPlayer] = nil
        end
    end

    local function start()
        if enabled then
            return
        end
        enabled = true
        for _, plr in ipairs(Players:GetPlayers()) do
            bind(plr)
        end
        connections.added = Players.PlayerAdded:Connect(bind)
        connections.removing = Players.PlayerRemoving:Connect(unbind)
    end

    local function stop()
        enabled = false
        if connections.added then
            connections.added:Disconnect()
            connections.added = nil
        end
        if connections.removing then
            connections.removing:Disconnect()
            connections.removing = nil
        end
        for targetPlayer, conn in pairs(connections) do
            if typeof(conn) == 'RBXScriptConnection' then
                conn:Disconnect()
            end
            connections[targetPlayer] = nil
        end
        for targetPlayer in pairs(visuals) do
            destroy(targetPlayer)
        end
    end

    local toggle = section:CreateToggle({
        Title = 'Player ESP',
        Default = false,
        SaveKey = 'player_esp_enabled',
        Configurable = true,
        DefaultColor = defaultColor,
        ColorSaveKey = 'player_esp_color',
        AlphaSaveKey = 'player_esp_alpha',
        OnColorChanged = function(newColor, newAlpha)
            color = newColor or color
            alpha = newAlpha or alpha
            applyColors()
        end,
        Callback = function(state)
            if state then
                start()
            else
                stop()
            end
        end,
    })

    return {
        start = start,
        stop = stop,
        toggle = toggle,
        setColor = function(c, a)
            color = c or color
            alpha = a or alpha
            applyColors()
        end,
    }
end

local function tryAutoAttach()
    local env = nil
    pcall(function()
        env = getgenv and getgenv()
    end)
    local autoSection = nil
    local autoTheme = {}
    local autoDefaultColor = nil
    if env then
        autoSection = env.PlayerESPSection or (env.sections and env.sections.esp) or env.ESPSection
        autoTheme = env.PlayerESPTheme or env.theme or {}
        autoDefaultColor = env.PlayerESPDefaultColor
    end
    if autoSection and type(autoSection.CreateToggle) == 'function' then
        module.instance = module.setup({
            section = autoSection,
            theme = autoTheme,
            defaultColor = autoDefaultColor,
        })
    end
end

tryAutoAttach()

return module
