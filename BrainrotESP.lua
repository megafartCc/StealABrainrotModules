local module = {}

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local datasFolder = ReplicatedStorage:WaitForChild("Datas")

local trackedTags = {"Animal"}
local attributeNames = {"Traits", "Mutation"}

local function defaultNotify(title, text)
    warn(string.format("[BrainrotESP] %s - %s", tostring(title), tostring(text)))
end

local function safeRequire(instance, label)
    if not instance then
        return nil
    end

    local ok, result = pcall(require, instance)
    if ok then
        return result
    end

    warn(("[BrainrotESP] Failed to require %s: %s"):format(label, tostring(result)))
    return nil
end

local function parseTraitsAttribute(value)
    if typeof(value) ~= "string" or value == "" then
        return nil
    end

    local firstChar = string.sub(value, 1, 1)
    if firstChar == "[" or firstChar == "{" then
        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, value)
        if ok and typeof(decoded) == "table" then
            return decoded
        end
    end

    local traits = {}
    for trait in string.gmatch(value, "[^,]+") do
        local trimmed = trait:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            table.insert(traits, trimmed)
        end
    end

    if #traits > 0 then
        return traits
    end

    return nil
end

local function getAdornee(inst)
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
    end

    if inst:IsA("Attachment") and inst.Parent and inst.Parent:IsA("BasePart") then
        return inst.Parent
    end

    if inst:IsA("BasePart") then
        return inst
    end

    return nil
end

local function findPlotModel(inst)
    local current = inst
    while current and current ~= Workspace do
        if current:IsA("Model") and current:FindFirstChild("AnimalPodiums") then
            return current
        end
        current = current.Parent
    end
    return nil
end

local function formatNumber(value)
    if typeof(value) ~= "number" then
        return "0"
    end

    local suffixes = {"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"}
    local working = value
    local index = 1
    while math.abs(working) >= 1000 and index < #suffixes do
        working /= 1000
        index += 1
    end

    local absWorking = math.abs(working)
    local pattern = "%.2f"
    if absWorking >= 100 then
        pattern = "%.0f"
    elseif absWorking >= 10 then
        pattern = "%.1f"
    end

    return pattern:format(working) .. suffixes[index]
end

local function buildModuleState(opts)
    opts = opts or {}
    local section = opts.section
    local theme = opts.theme or {}
    local notify = opts.notify or defaultNotify

    local accentColor = theme.accent or Color3.fromRGB(50, 130, 250)
    local frameColor = theme.panel2 or Color3.fromRGB(16, 18, 24)
    local textColor = theme.text or Color3.fromRGB(230, 235, 240)
    local rateColor = theme.accentB or Color3.fromRGB(170, 210, 255)

    local state = {
        section = section,
        notify = notify,
        accentColor = accentColor,
        frameColor = frameColor,
        textColor = textColor,
        rateColor = rateColor,
        enabled = false,
        mostExpensiveOnly = false,
        tracked = {},
        heartbeatAccumulator = 0,
        observers = {},
    }

    return state
end

local function ensureAnimalData(state)
    if state.animalsShared and state.animalsData then
        return true
    end

    state.animalsShared = safeRequire(sharedFolder:FindFirstChild("Animals"), "Shared.Animals")
    state.animalsData = safeRequire(datasFolder:FindFirstChild("Animals"), "Datas.Animals")

    if not state.animalsShared or not state.animalsData then
        state.notify("Brainrot ESP", "Unable to load animal metadata. ESP disabled.")
        return false
    end

    return true
end

local function isBrainrotModel(state, inst)
    if not inst or not inst:IsA("Model") then
        return false
    end

    if not state.animalsData[inst.Name] then
        return false
    end

    if not Workspace:IsAncestorOf(inst) then
        return false
    end

    if not findPlotModel(inst) then
        return false
    end

    return inst:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

local function resolveIncome(state, model)
    local entry = state.animalsData[model.Name]
    if not entry then
        return nil
    end

    local mutation = model:GetAttribute("Mutation")
    if mutation == "" then
        mutation = nil
    end

    local traits = parseTraitsAttribute(model:GetAttribute("Traits"))
    local ok, amount = pcall(function()
        return state.animalsShared:GetGeneration(model.Name, mutation, traits, nil)
    end)

    if ok and typeof(amount) == "number" then
        return amount
    end

    return entry.Generation
end

local function setVisualVisibility(meta, visible)
    if meta.highlight then
        meta.highlight.Enabled = visible
    end
    if meta.billboard then
        meta.billboard.Enabled = visible
    end
    if meta.frame then
        meta.frame.Visible = visible
    end
end

local function refreshMostExpensiveVisibility(state)
    local tracked = state.tracked

    if not state.mostExpensiveOnly then
        for _, meta in pairs(tracked) do
            setVisualVisibility(meta, true)
        end
        return
    end

    local bestIncome = -math.huge
    for _, meta in pairs(tracked) do
        bestIncome = math.max(bestIncome, meta.income or 0)
    end

    if bestIncome == -math.huge then
        for _, meta in pairs(tracked) do
            setVisualVisibility(meta, false)
        end
        return
    end

    for _, meta in pairs(tracked) do
        local visible = (meta.income or 0) >= bestIncome - 1e-6
        setVisualVisibility(meta, visible)
    end
end

local function updateLabel(state, model)
    local meta = state.tracked[model]
    if not meta then
        return
    end

    local income = resolveIncome(state, model) or 0
    local entry = state.animalsData[model.Name]
    local displayName = entry and entry.DisplayName or model.Name

    meta.income = income
    meta.nameLabel.Text = displayName
    meta.rateLabel.Text = string.format("$%s/sec", formatNumber(income))
end

local function observeAttributes(state, model, meta)
    for _, attribute in ipairs(attributeNames) do
        table.insert(meta.connections, model:GetAttributeChangedSignal(attribute):Connect(function()
            updateLabel(state, model)
            refreshMostExpensiveVisibility(state)
        end))
    end
end

local function cleanupBrainrot(state, model)
    local meta = state.tracked[model]
    if not meta then
        return
    end

    for _, connection in ipairs(meta.connections) do
        connection:Disconnect()
    end

    if meta.billboard then
        meta.billboard:Destroy()
    end

    if meta.highlight then
        meta.highlight:Destroy()
    end

    state.tracked[model] = nil
end

local function createBrainrotEsp(state, model)
    if not state.enabled then
        return
    end

    if state.tracked[model] or not isBrainrotModel(state, model) then
        return
    end

    local adornee = getAdornee(model)
    if not adornee then
        return
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "BrainrotESPHighlight"
    highlight.Adornee = model
    highlight.FillColor = state.accentColor
    highlight.FillTransparency = 0.25
    highlight.OutlineColor = Color3.new(state.accentColor.R * 0.5, state.accentColor.G * 0.5, state.accentColor.B * 0.5)
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Enabled = true
    highlight.Parent = model

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "BrainrotESPBillboard"
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0, 140, 0, 30)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
    billboard.MaxDistance = 1200
    billboard.LightInfluence = 0
    billboard.Enabled = true
    billboard.Adornee = adornee
    billboard.Parent = model

    local frame = Instance.new("Frame")
    frame.Name = "BrainrotESPFrame"
    frame.BackgroundColor3 = state.frameColor
    frame.BackgroundTransparency = 0.45
    frame.BorderSizePixel = 0
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.Visible = true
    frame.Parent = billboard

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Thickness = 1
    stroke.Color = state.accentColor
    stroke.Transparency = 0.15
    stroke.Parent = frame

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "BrainrotESPName"
    nameLabel.BackgroundTransparency = 1
    nameLabel.Size = UDim2.new(1, -8, 0, 16)
    nameLabel.Position = UDim2.new(0, 4, 0, 3)
    nameLabel.Font = Enum.Font.GothamSemibold
    nameLabel.TextColor3 = state.textColor
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.TextStrokeTransparency = 0.4
    nameLabel.TextScaled = false
    nameLabel.TextSize = 14
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.TextYAlignment = Enum.TextYAlignment.Top
    nameLabel.ClipsDescendants = true
    nameLabel.Parent = frame

    local rateLabel = Instance.new("TextLabel")
    rateLabel.Name = "BrainrotESPRate"
    rateLabel.BackgroundTransparency = 1
    rateLabel.Size = UDim2.new(1, -8, 0, 12)
    rateLabel.Position = UDim2.new(0, 4, 0, 18)
    rateLabel.Font = Enum.Font.GothamSemibold
    rateLabel.TextColor3 = state.rateColor
    rateLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    rateLabel.TextStrokeTransparency = 0.55
    rateLabel.TextScaled = false
    rateLabel.TextSize = 12
    rateLabel.TextXAlignment = Enum.TextXAlignment.Center
    rateLabel.TextYAlignment = Enum.TextYAlignment.Top
    rateLabel.ClipsDescendants = true
    rateLabel.Parent = frame

    local meta = {
        highlight = highlight,
        billboard = billboard,
        frame = frame,
        nameLabel = nameLabel,
        rateLabel = rateLabel,
        connections = {},
        income = 0,
    }

    state.tracked[model] = meta

    table.insert(meta.connections, model.AncestryChanged:Connect(function(_, parent)
        if not parent then
            cleanupBrainrot(state, model)
            refreshMostExpensiveVisibility(state)
        end
    end))

    if model.Destroying then
        table.insert(meta.connections, model.Destroying:Connect(function()
            cleanupBrainrot(state, model)
            refreshMostExpensiveVisibility(state)
        end))
    end

    observeAttributes(state, model, meta)
    updateLabel(state, model)
    refreshMostExpensiveVisibility(state)
end

local function connectObservers(state)
    if state.observers.descendantAdded then
        return
    end

    state.observers.descendantAdded = Workspace.DescendantAdded:Connect(function(inst)
        if inst:IsA("Model") then
            createBrainrotEsp(state, inst)
        end
    end)

    state.observers.tagAdded = {}
    state.observers.tagRemoved = {}

    for _, tag in ipairs(trackedTags) do
        local addedConn = CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
            if inst:IsA("Model") then
                createBrainrotEsp(state, inst)
            end
        end)

        local removedConn = CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
            cleanupBrainrot(state, inst)
            refreshMostExpensiveVisibility(state)
        end)

        state.observers.tagAdded[tag] = addedConn
        state.observers.tagRemoved[tag] = removedConn
    end
end

local function disconnectObservers(state)
    if state.observers.descendantAdded then
        state.observers.descendantAdded:Disconnect()
        state.observers.descendantAdded = nil
    end

    if state.observers.tagAdded then
        for _, conn in pairs(state.observers.tagAdded) do
            conn:Disconnect()
        end
        state.observers.tagAdded = nil
    end

    if state.observers.tagRemoved then
        for _, conn in pairs(state.observers.tagRemoved) do
            conn:Disconnect()
        end
        state.observers.tagRemoved = nil
    end

    if state.observers.heartbeat then
        state.observers.heartbeat:Disconnect()
        state.observers.heartbeat = nil
    end
end

local function cleanupAll(state)
    for model in pairs(state.tracked) do
        cleanupBrainrot(state, model)
    end
    state.tracked = {}
end

local function scanWorkspace(state)
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("Model") then
            createBrainrotEsp(state, descendant)
        end
    end

    for _, tag in ipairs(trackedTags) do
        local ok, results = pcall(CollectionService.GetTagged, CollectionService, tag)
        if ok then
            for _, inst in ipairs(results) do
                if inst:IsA("Model") then
                    createBrainrotEsp(state, inst)
                end
            end
        end
    end
end

local function attachHeartbeat(state)
    if state.observers.heartbeat then
        return
    end

    state.heartbeatAccumulator = 0
    state.observers.heartbeat = RunService.Heartbeat:Connect(function(delta)
        state.heartbeatAccumulator += delta
        if state.heartbeatAccumulator < 1 then
            return
        end
        state.heartbeatAccumulator = 0

        for model in pairs(state.tracked) do
            updateLabel(state, model)
        end
        refreshMostExpensiveVisibility(state)
    end)
end

local function startEsp(state)
    if state.enabled then
        return
    end

    if not ensureAnimalData(state) then
        return
    end

    state.enabled = true
    connectObservers(state)
    attachHeartbeat(state)
    scanWorkspace(state)
    refreshMostExpensiveVisibility(state)
end

local function stopEsp(state)
    if not state.enabled then
        return
    end

    state.enabled = false
    disconnectObservers(state)
    cleanupAll(state)
end

local function setupToggles(state, controls)
    local section = state.section
    if not section or type(section.CreateToggle) ~= "function" then
        return
    end

    local brainrotToggle = section:CreateToggle({
        Title = "Brainrot ESP",
        Default = false,
        SaveKey = "brainrot_esp_enabled",
        Callback = function(enabled)
            if enabled then
                startEsp(state)
            else
                stopEsp(state)
            end
        end,
    })

    local expensiveToggle = section:CreateToggle({
        Title = "Most Expensive Only",
        Default = false,
        SaveKey = "brainrot_esp_most_expensive",
        Callback = function(onlyBest)
            state.mostExpensiveOnly = onlyBest and true or false
            refreshMostExpensiveVisibility(state)
        end,
    })

    controls.brainrotToggle = brainrotToggle
    controls.mostExpensiveToggle = expensiveToggle
end

function module.setup(opts)
    local state = buildModuleState(opts)
    local controls = {
        start = function()
            startEsp(state)
        end,
        stop = function()
            stopEsp(state)
        end,
        setMostExpensiveOnly = function(value)
            state.mostExpensiveOnly = not not value
            refreshMostExpensiveVisibility(state)
        end,
    }

    setupToggles(state, controls)
    return controls
end

return module


