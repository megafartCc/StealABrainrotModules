local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local datasFolder = ReplicatedStorage:WaitForChild("Datas")
local packagesFolder = ReplicatedStorage:WaitForChild("Packages")

local Synchronizer = require(packagesFolder:WaitForChild("Synchronizer"))
local AnimalsDataModule = require(datasFolder:WaitForChild("Animals"))
local AnimalsSharedModule = require(sharedFolder:WaitForChild("Animals"))
local MutationsDataModule = require(datasFolder:WaitForChild("Mutations"))
local TraitsDataModule = require(datasFolder:WaitForChild("Traits"))
local GameDataModule = require(datasFolder:WaitForChild("Game"))

local LOCAL_PLAYER = Players.LocalPlayer
local module = {}

local function safeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

local function formatNumber(value)
    value = tonumber(value) or 0
    if value >= 1e12 then
        return string.format("%.1fT", value / 1e12)
    elseif value >= 1e9 then
        return string.format("%.1fB", value / 1e9)
    elseif value >= 1e6 then
        return string.format("%.1fM", value / 1e6)
    elseif value >= 1e3 then
        return string.format("%.0fK", value / 1e3)
    end
    return tostring(math.floor(value))
end

local function sanitizeKey(value)
    if value == nil then
        return nil
    end
    local valueType = typeof(value)
    if valueType == "string" then
        local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            return trimmed:lower()
        end
    elseif valueType == "number" then
        return tostring(value):lower()
    end
    return nil
end

local animalsLookup = {}
for key, entry in pairs(AnimalsDataModule) do
    if typeof(key) == "string" then
        animalsLookup[key:lower()] = entry
    end
    if entry.DisplayName then
        animalsLookup[entry.DisplayName:lower()] = entry
    end
end

local mutationMultipliers = {}
for name, data in pairs(MutationsDataModule) do
    mutationMultipliers[name] = 1 + (data.Modifier or 0)
end

local state = {
    enabled = false,
    mostExpensiveOnly = false,
    tracked = {},
    knownStands = setmetatable({}, { __mode = "k" }),
    standConns = setmetatable({}, { __mode = "k" }),
    lastSeen = {},
    scanToken = 0,
    connections = {},
    podiumsConns = setmetatable({}, { __mode = "k" }),
    baseConns = setmetatable({}, { __mode = "k" }),
    boundPlots = nil,
    queue = {},
    queueSet = setmetatable({}, { __mode = "k" }),
    forceSet = setmetatable({}, { __mode = "k" }),
    queueHead = 1,
    queueTail = 0,
    refreshList = {},
    refreshIndex = 1,
    refreshAccumulator = 0,
    refreshInterval = 3,
    refreshBatch = 6,
    standUpdateInterval = 2,
    queueBudget = 6,
    frameBudget = 0.003,
    bestDirty = false,
    lastBestRefresh = 0,
    accentColor = Color3.fromRGB(50, 130, 250),
    frameColor = Color3.fromRGB(16, 18, 24),
    textColor = Color3.fromRGB(230, 235, 240),
    notify = function(msg)
        warn("[BrainrotESP] " .. tostring(msg))
    end,
    baseChannelCache = {},
    bestMeta = nil,
}

local function isLocalOwner(owner)
    if not owner then
        return false
    end
    if owner == LOCAL_PLAYER then
        return true
    end
    if typeof(owner) == "Instance" and owner:IsA("Player") then
        return LOCAL_PLAYER and owner == LOCAL_PLAYER
    end
    if typeof(owner) == "table" then
        if owner.UserId and LOCAL_PLAYER and owner.UserId == LOCAL_PLAYER.UserId then
            return true
        end
        if owner.Name and LOCAL_PLAYER and owner.Name:lower() == LOCAL_PLAYER.Name:lower() then
            return true
        end
    elseif typeof(owner) == "string" then
        return LOCAL_PLAYER and owner:lower() == LOCAL_PLAYER.Name:lower()
    elseif typeof(owner) == "number" then
        return LOCAL_PLAYER and LOCAL_PLAYER.UserId and owner == LOCAL_PLAYER.UserId
    end
    return false
end

local function destroyBeam()
    if state.beam then
        state.beam:Destroy()
        state.beam = nil
    end
    if state.beamAttachment0 then
        state.beamAttachment0:Destroy()
        state.beamAttachment0 = nil
    end
end

local function applyOptions(opts)
    opts = opts or {}
    local theme = opts.theme or {}
    if theme.accent then
        state.accentColor = theme.accent
    end
    if theme.accentA then
        state.accentColor = theme.accentA
    end
    if theme.panel2 then
        state.frameColor = theme.panel2
    end
    if theme.text then
        state.textColor = theme.text
    end
    if typeof(opts.notify) == "function" then
        state.notify = opts.notify
    end
end

local function updatePlayerAttachment()
    local character = LOCAL_PLAYER and LOCAL_PLAYER.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        if state.beamAttachment0 then
            state.beamAttachment0:Destroy()
            state.beamAttachment0 = nil
        end
        return
    end
    if state.beamAttachment0 and state.beamAttachment0.Parent == hrp then
        return
    end
    if state.beamAttachment0 then
        state.beamAttachment0:Destroy()
        state.beamAttachment0 = nil
    end
    local attachment = Instance.new("Attachment")
    attachment.Name = "BrainrotESPPivot"
    attachment.Parent = hrp
    state.beamAttachment0 = attachment
    if state.beam and state.beamAttachment0 then
        state.beam.Attachment0 = state.beamAttachment0
    end
end

if LOCAL_PLAYER then
    LOCAL_PLAYER.CharacterAdded:Connect(function()
        task.wait(0.25)
        updatePlayerAttachment()
    end)
    LOCAL_PLAYER.CharacterRemoving:Connect(function()
        updatePlayerAttachment()
    end)
end

local function ensureBeam()
    if state.beam then
        return
    end
    state.beam = Instance.new("Beam")
    state.beam.Name = "BrainrotESPLaser"
    state.beam.Width0 = 0.1
    state.beam.Width1 = 0.1
    state.beam.LightEmission = 0.4
    state.beam.Color = ColorSequence.new(state.accentColor)
    state.beam.Transparency = NumberSequence.new(0.1)
    state.beam.FaceCamera = true
    state.beam.Enabled = false
    state.beam.Parent = Workspace
    updatePlayerAttachment()
end

local function setBeamTarget(meta)
    if not state.mostExpensiveOnly or not state.enabled then
        if state.beam then
            state.beam.Enabled = false
        end
        return
    end
    ensureBeam()
    updatePlayerAttachment()
    if state.beam and state.beamAttachment0 and meta and meta.targetAttachment then
        state.beam.Attachment0 = state.beamAttachment0
        state.beam.Attachment1 = meta.targetAttachment
        state.beam.Enabled = true
    elseif state.beam then
        state.beam.Enabled = false
    end
end

local function computeBestMeta()
    local bestMeta
    local bestIncome = -math.huge
    for _, meta in pairs(state.tracked) do
        local income = meta.income or 0
        if income > bestIncome then
            bestIncome = income
            bestMeta = meta
        end
    end
    state.bestMeta = bestMeta
    return bestMeta
end

local function getPlotsFolder()
    return Workspace:FindFirstChild("Plots")
end

local function getStandBase(stand)
    if not stand or not stand.Parent then
        return nil
    end
    if stand.Parent.Name == "AnimalPodiums" then
        return stand.Parent.Parent
    end
    return stand:FindFirstAncestorOfClass("Model")
end

local function getValidStandBase(stand)
    local plots = getPlotsFolder()
    local base = getStandBase(stand)
    if not base then
        return nil
    end
    if plots then
        if not base:IsDescendantOf(plots) then
            return nil
        end
        if not base:FindFirstChild("PlotSign") then
            return nil
        end
        return base
    end
    -- Fallback: if Plots folder is missing (e.g. renamed), still accept the base
    -- as long as it looks like a podium parent.
    if base:FindFirstChild("AnimalPodiums") then
        return base
    end
    return nil
end

local function findBrainrotModelOnStand(stand)
    if not stand or not stand.Parent then
        return nil
    end
    for _, desc in ipairs(stand:GetDescendants()) do
        if desc:IsA("Model") then
            local root = desc:FindFirstChild("RootPart")
                or desc:FindFirstChild("HumanoidRootPart")
                or desc.PrimaryPart
            if root then
                local lookup = sanitizeKey(desc.Name)
                local idxAttr = sanitizeKey(desc:GetAttribute("Index") or desc:GetAttribute("Animal") or desc:GetAttribute("Brainrot"))
                local hasIncome = desc:FindFirstChild("Income")
                    or desc:FindFirstChild("Generation")
                    or desc:GetAttribute("IncomePerSecond")
                if (lookup and animalsLookup[lookup])
                    or (idxAttr and animalsLookup[idxAttr])
                    or hasIncome
                    or desc:GetAttribute("Mutation")
                    or desc:GetAttribute("Traits")
                then
                    return desc, root
                end
            end
        end
    end
    return nil
end

local function findBrainrotModelInBase(base, nameList)
    if not base then
        return nil, nil
    end
    local wanted = {}
    for _, n in ipairs(nameList or {}) do
        local key = sanitizeKey(n)
        if key and key ~= "" then
            wanted[key] = true
        end
    end
    for _, desc in ipairs(base:GetDescendants()) do
        if desc:IsA("Model") and desc.Parent ~= base:FindFirstChild("AnimalPodiums") then
            local root = desc.PrimaryPart
                or desc:FindFirstChild("RootPart")
                or desc:FindFirstChild("HumanoidRootPart")
                or desc:FindFirstChildWhichIsA("BasePart", true)
            if root then
                local key = sanitizeKey(desc.Name)
                if not next(wanted) or (key and wanted[key]) then
                    return desc, root
                end
            end
        end
    end
    return nil, nil
end

local function getStandRootPart(stand)
    local model, root = findBrainrotModelOnStand(stand)
    if model then
        root = root or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
        if root then
            return model, root
        end
    end
    local base = stand and stand:FindFirstChild("Base")
    if base then
        local spawn = base:FindFirstChild("Spawn")
        if spawn and spawn:IsA("BasePart") then
            return nil, spawn
        end
    end
    return nil, stand and (stand.PrimaryPart or stand:FindFirstChildWhichIsA("BasePart", true))
end

local function getAttrNumber(container, keys)
    for _, key in ipairs(keys) do
        local val = container:GetAttribute(key)
        if val then
            local num = tonumber(val)
            if num then
                return num
            end
        end
        local child = container:FindFirstChild(key)
        if child and child.Value then
            local num = tonumber(child.Value)
            if num then
                return num
            end
        end
    end
    return nil
end

local function readMutation(container)
    if not container then
        return nil
    end
    local val = container:GetAttribute("Mutation") or container:GetAttribute("Mut")
    if val ~= nil then
        return val
    end
    local child = container:FindFirstChild("Mutation") or container:FindFirstChild("Mut")
    if child and child.Value ~= nil then
        return child.Value
    end
    return nil
end

local normalizeTraits

local function readTraits(container)
    if not container then
        return nil
    end
    local traits = normalizeTraits(container:GetAttribute("Traits"))
    if traits then
        return traits
    end
    local collected = {}
    for i = 1, 4 do
        local key = "Trait" .. i
        local val = container:GetAttribute(key)
        if val then
            table.insert(collected, val)
        else
            local child = container:FindFirstChild(key)
            if child and child.Value then
                table.insert(collected, child.Value)
            end
        end
    end
    if #collected > 0 then
        return collected
    end
    return nil
end

local function safePlayerMultiplier(owner)
    local okGame, gameShared = pcall(function()
        return require(sharedFolder:WaitForChild("Game"))
    end)
    if not okGame or not gameShared or type(gameShared.GetPlayerCashMultiplayer) ~= "function" then
        return 1
    end
    local okMult, mult = pcall(gameShared.GetPlayerCashMultiplayer, gameShared, owner)
    if okMult and mult then
        local num = tonumber(mult)
        if num then
            return num
        end
    end
    return 1
end

local function getMutationAndTraitsFromModel(model)
    if not model then
        return nil, nil
    end
    local mutation = readMutation(model)
    local traits = readTraits(model)
    if not mutation then
        local folder = model:FindFirstChild("MutationFolder") or model:FindFirstChild("Mutations")
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("StringValue") and child.Value ~= "" then
                    mutation = child.Value
                    break
                end
            end
        end
    end
    if not traits then
        local tFolder = model:FindFirstChild("Traits") or model:FindFirstChild("TraitsFolder")
        if tFolder then
            local list = {}
            for _, child in ipairs(tFolder:GetChildren()) do
                if child:IsA("StringValue") and child.Value ~= "" then
                    table.insert(list, child.Value)
                end
            end
            if #list > 0 then
                traits = list
            end
        end
    end
    if type(traits) == "string" then
        traits = { traits }
    end
    return mutation, normalizeTraits(traits)
end

local function calculateMultiplier(mutation, traits)
    local multipliers = {}
    local count = 0
    if mutation and mutationMultipliers[mutation] then
        table.insert(multipliers, mutationMultipliers[mutation])
        count = count + 1
    else
        table.insert(multipliers, 1)
        count = count + 1
    end
    if typeof(traits) == "table" then
        for _, trait in ipairs(traits) do
            local info = TraitsDataModule[trait]
            if info then
                table.insert(multipliers, 1 + (info.MultiplierModifier or 0))
                count = count + 1
            end
        end
    end
    if count == 0 then
        return 1
    end
    local sum = 0
    for _, mult in ipairs(multipliers) do
        sum = sum + mult
    end
    local total = sum - (count - 1)
    return total < 1 and 1 or total
end

local function computeGeneration(index, mutation, traits, owner)
    local entry = index and animalsLookup[sanitizeKey(index) or ""]
    if not entry then
        return 0
    end
    local baseGen = entry.Generation
        or ((entry.Price or 0) * (GameDataModule.Game and GameDataModule.Game.AnimalGanerationModifier or 0))
    local mult = calculateMultiplier(mutation, traits)
    local sleepy = false
    if typeof(traits) == "table" then
        for _, trait in ipairs(traits) do
            if trait == "Sleepy" then
                sleepy = true
                break
            end
        end
    end
    local gen = baseGen * mult
    if sleepy then
        gen = gen * 0.5
    end
    if owner then
        gen = gen * safePlayerMultiplier(owner)
    end
    return math.max(0, math.floor(gen + 0.5))
end

local function computeIncome(index, mutation, traits, owner, stand, model, entry, animalData)
    entry = entry or (index and animalsLookup[sanitizeKey(index) or ""])
    local income = nil

    if owner and typeof(owner) == "table" and owner.UserId and Players then
        owner = Players:GetPlayerByUserId(owner.UserId) or owner
    elseif owner and typeof(owner) == "table" and owner.Name and Players then
        owner = Players:FindFirstChild(owner.Name) or owner
    end

    local modelMutation, modelTraits = getMutationAndTraitsFromModel(model)
    mutation = mutation or modelMutation
    traits = traits or modelTraits or readTraits(stand)

    income = income or (model and getAttrNumber(model, { "IncomePerSecond", "Income", "Generation", "Gen" }))
    income = income or (stand and getAttrNumber(stand, { "IncomePerSecond", "Income", "Generation", "Gen" }))
    income = income or (animalData and tonumber(animalData.Generation))

    if (not income or income == 0) and AnimalsSharedModule and AnimalsSharedModule.GetGeneration and index then
        income = safeCall(AnimalsSharedModule.GetGeneration, AnimalsSharedModule, index, mutation, traits, owner)
    end

    if (not income or income == 0) and index then
        income = computeGeneration(index, mutation, traits, owner)
    end

    if (not income or income == 0) and entry and entry.Generation then
        income = entry.Generation
    end

    return income or 0
end

local function getStandSlot(stand)
    if not stand then
        return nil
    end
    local numeric = tonumber(stand.Name)
    if numeric then
        return numeric
    end
    local attr = stand:GetAttribute("Slot") or stand:GetAttribute("Index")
    return tonumber(attr)
end

local function resolveBrainrotName(stand, model, index)
    if index then
        local key = sanitizeKey(index)
        local entry = key and animalsLookup[key]
        if entry then
            return entry.DisplayName or index
        end
        return typeof(index) == "string" and index or tostring(index)
    end
    if stand then
        local attr = stand:GetAttribute("Animal") or stand:GetAttribute("Brainrot") or stand:GetAttribute("Pet")
        if attr and attr ~= "" then
            return attr
        end
    end
    if model then
        return model.Name
    end
    return "Brainrot"
end

local function getBaseChannel(base)
    if not base then
        return nil
    end
    if state.baseChannelCache[base] then
        return state.baseChannelCache[base]
    end
    local channel = nil
    if Synchronizer and (Synchronizer.Get or Synchronizer.Wait) then
        channel = safeCall(function()
            return (Synchronizer.Get and Synchronizer:Get(base.Name)) or nil
        end) or safeCall(function()
            return Synchronizer:Wait(base.Name)
        end)
    end
    state.baseChannelCache[base] = channel
    return channel
end

function normalizeTraits(traits)
    if typeof(traits) == "table" then
        if traits[1] then
            return traits
        end
        local list = {}
        for _, value in pairs(traits) do
            table.insert(list, value)
        end
        return list
    end
    if typeof(traits) == "string" and traits ~= "" then
        local parsed = safeCall(function()
            return HttpService:JSONDecode(traits)
        end)
        if typeof(parsed) == "table" then
            return normalizeTraits(parsed)
        end
        return { traits }
    end
    return nil
end

local function buildStandBrainrotInfo(stand)
    if not stand or not stand.Parent then
        return nil
    end
    local base = getValidStandBase(stand)
    if not base then
        return nil
    end
    local channel = getBaseChannel(base)
    local slot = getStandSlot(stand)
    local animals
    local animalData
    if channel and type(channel.Get) == "function" then
        animals = channel:Get("AnimalList") or channel:Get("AnimalPodiums")
        animalData = animals and animals[slot]
    end
    local model, root = getStandRootPart(stand)
    if not root then
        return nil
    end
    local owner = channel and channel:Get("Owner")
    if isLocalOwner(owner)
        or isLocalOwner(base and base:GetAttribute("Owner"))
        or isLocalOwner(base and base:GetAttribute("OwnerName"))
        or isLocalOwner(base and base:GetAttribute("PlacedBy"))
    then
        return nil
    end
    local mutation = (animalData and (animalData.Mutation or animalData.Mut))
        or readMutation(model)
        or readMutation(stand)
    local traits = normalizeTraits(animalData and animalData.Traits)
        or readTraits(model)
        or readTraits(stand)
    local index = animalData and (animalData.Index or animalData.Animal or animalData.Name)
        or (stand:GetAttribute("Animal") or stand:GetAttribute("Brainrot"))
        or (model and model:GetAttribute("Animal"))
        or (model and model.Name)
        or stand.Name
    local resolvedName = resolveBrainrotName(stand, model, index)
    local key = sanitizeKey(index) or sanitizeKey(resolvedName)
    local entry = key and animalsLookup[key]
    if not model then
        local names = {
            resolvedName,
            index,
            entry and entry.DisplayName,
        }
        model, root = findBrainrotModelInBase(base, names)
        if model and root then
            -- refresh resolved name if we found a better match
            resolvedName = resolveBrainrotName(stand, model, index)
        end
    end
    key = sanitizeKey(index) or sanitizeKey(resolvedName)
    entry = key and animalsLookup[key]
    local moneyValue = computeIncome(index, mutation, traits, owner, stand, model, entry, animalData)
    if not model and moneyValue <= 0 then
        return nil
    end
    return {
        stand = stand,
        base = base,
        model = model,
        root = root,
        name = resolvedName,
        moneyValue = moneyValue,
    }
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

local function refreshMostExpensiveVisibility()
    local bestMeta = computeBestMeta()
    if not state.mostExpensiveOnly then
        for _, meta in pairs(state.tracked) do
            setVisualVisibility(meta, state.enabled)
        end
        setBeamTarget(nil)
        return
    end
    for _, meta in pairs(state.tracked) do
        local visible = bestMeta and meta == bestMeta
        setVisualVisibility(meta, visible and state.enabled)
    end
    setBeamTarget(bestMeta)
end

local function clearStandVisual(stand)
    local meta = state.tracked[stand]
    if not meta then
        return
    end
    if meta.highlight then
        meta.highlight:Destroy()
    end
    if meta.billboard then
        meta.billboard:Destroy()
    end
    if meta.targetAttachment then
        meta.targetAttachment:Destroy()
    end
    state.tracked[stand] = nil
    if state.bestMeta == meta then
        computeBestMeta()
    end
    state.bestDirty = true
end

local function untrackStand(stand)
    clearStandVisual(stand)
    state.knownStands[stand] = nil
    state.queueSet[stand] = nil
    state.forceSet[stand] = nil
    local conn = state.standConns[stand]
    if conn then
        safeCall(function()
            conn:Disconnect()
        end)
    end
    state.standConns[stand] = nil
end

local function applyStandInfo(meta, info)
    meta.income = info.moneyValue or 0
    meta.root = info.root
    meta.model = info.model
    meta.base = info.base
    meta.nameLabel.Text = info.name or "Brainrot"
    meta.rateLabel.Text = string.format("$%s/sec", formatNumber(meta.income))
    local adornee = info.root
    if adornee and adornee ~= meta.currentAdornee then
        meta.currentAdornee = adornee
        meta.billboard.Adornee = adornee
        meta.billboard.Parent = adornee
        meta.targetAttachment.Parent = adornee
    end
    local highlightTarget = info.model or adornee
    if highlightTarget then
        meta.highlight.Adornee = highlightTarget
        meta.highlight.Parent = highlightTarget
    end
end

local function createStandVisual(info)
    local adornee = info.root
    local highlight = Instance.new("Highlight")
    highlight.Name = "BrainrotESPHighlight"
    highlight.FillColor = state.accentColor
    highlight.FillTransparency = 0.12
    highlight.OutlineColor = Color3.new(state.accentColor.R * 0.45, state.accentColor.G * 0.45, state.accentColor.B * 0.45)
    highlight.OutlineTransparency = 0.25
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Enabled = true
    -- Prefer to adorn and parent the actual brainrot model so the whole model is filled blue.
    highlight.Adornee = info.model or adornee
    highlight.Parent = info.model or adornee or info.stand

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "BrainrotESPBillboard"
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0, 170, 0, 34)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
    billboard.MaxDistance = 1200
    billboard.LightInfluence = 0
    billboard.Enabled = true
    billboard.Adornee = adornee
    billboard.Parent = adornee

    local frame = Instance.new("Frame")
    frame.BackgroundColor3 = state.frameColor
    frame.BackgroundTransparency = 0.45
    frame.BorderSizePixel = 0
    frame.Size = UDim2.new(1, 0, 1, 0)
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
    nameLabel.BackgroundTransparency = 1
    nameLabel.Size = UDim2.new(1, -8, 0, 18)
    nameLabel.Position = UDim2.new(0, 4, 0, 3)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextColor3 = state.textColor
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.TextStrokeTransparency = 0.4
    nameLabel.TextScaled = false
    nameLabel.TextSize = 15
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.TextYAlignment = Enum.TextYAlignment.Top
    nameLabel.TextWrapped = true
    nameLabel.Parent = frame

    local rateLabel = Instance.new("TextLabel")
    rateLabel.BackgroundTransparency = 1
    rateLabel.Size = UDim2.new(1, -8, 0, 14)
    rateLabel.Position = UDim2.new(0, 4, 0, 20)
    rateLabel.Font = Enum.Font.GothamBold
    rateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    rateLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    rateLabel.TextStrokeTransparency = 0.3
    rateLabel.TextScaled = false
    rateLabel.TextSize = 13
    rateLabel.TextXAlignment = Enum.TextXAlignment.Center
    rateLabel.TextYAlignment = Enum.TextYAlignment.Top
    rateLabel.TextWrapped = true
    rateLabel.Parent = frame

    local attachment = Instance.new("Attachment")
    attachment.Name = "BrainrotESPTarget"
    attachment.Parent = adornee

    return {
        highlight = highlight,
        billboard = billboard,
        frame = frame,
        nameLabel = nameLabel,
        rateLabel = rateLabel,
        targetAttachment = attachment,
        currentAdornee = adornee,
        stand = info.stand,
    }
end

local function updateStandEsp(stand)
    if not state.enabled then
        return
    end
    local meta = state.tracked[stand]
    local now = os.clock()
    if meta and meta.nextUpdateAt and now < meta.nextUpdateAt then
        return
    end
    local info = safeCall(buildStandBrainrotInfo, stand)
    if not info then
        clearStandVisual(stand)
        return
    end
    if not meta then
        meta = createStandVisual(info)
        state.tracked[stand] = meta
    end
    applyStandInfo(meta, info)
    meta.nextUpdateAt = now + (state.standUpdateInterval or 2)
    state.bestDirty = true
end

local function enqueueStand(stand, force)
    if not (stand and stand.Parent) then
        return
    end
    if state.queueSet[stand] then
        if force then
            state.forceSet[stand] = true
        end
        return
    end
    state.queueSet[stand] = true
    if force then
        state.forceSet[stand] = true
    end
    state.queueTail = state.queueTail + 1
    state.queue[state.queueTail] = stand
end

local function dequeueStand()
    if state.queueHead > state.queueTail then
        return nil
    end
    local stand = state.queue[state.queueHead]
    state.queue[state.queueHead] = nil
    state.queueHead = state.queueHead + 1
    if state.queueHead > state.queueTail then
        state.queueHead = 1
        state.queueTail = 0
    end
    return stand
end

local function trackStand(stand)
    if not (stand and stand:IsA("Model") and stand.Parent) then
        return
    end
    if state.knownStands[stand] then
        return
    end
    state.knownStands[stand] = true
    local conn
    conn = stand.AncestryChanged:Connect(function(_, parent)
        if not parent then
            untrackStand(stand)
        end
    end)
    state.standConns[stand] = conn
    enqueueStand(stand, true)
end

local function unbindPodiums(podiums)
    local conns = state.podiumsConns[podiums]
    if conns then
        for _, conn in pairs(conns) do
            safeCall(function()
                conn:Disconnect()
            end)
        end
    end
    state.podiumsConns[podiums] = nil
    if podiums then
        for _, stand in ipairs(podiums:GetChildren()) do
            if stand:IsA("Model") then
                untrackStand(stand)
            end
        end
    end
end

local function bindPodiums(podiums)
    if not (podiums and podiums.Parent) then
        return
    end
    if state.podiumsConns[podiums] then
        return
    end
    local function onAdded(child)
        if child:IsA("Model") then
            trackStand(child)
        end
    end
    local function onRemoved(child)
        if child:IsA("Model") then
            untrackStand(child)
        end
    end
    for _, stand in ipairs(podiums:GetChildren()) do
        if stand:IsA("Model") then
            trackStand(stand)
        end
    end
    state.podiumsConns[podiums] = {
        added = podiums.ChildAdded:Connect(onAdded),
        removed = podiums.ChildRemoved:Connect(onRemoved),
        ancestry = podiums.AncestryChanged:Connect(function(_, parent)
            if not parent then
                unbindPodiums(podiums)
            end
        end),
    }
end

local function unbindBase(base)
    local conns = state.baseConns[base]
    if conns then
        for _, conn in pairs(conns) do
            safeCall(function()
                conn:Disconnect()
            end)
        end
    end
    state.baseConns[base] = nil
    if base then
        state.baseChannelCache[base] = nil
    end
    local podiums = base and base:FindFirstChild("AnimalPodiums")
    if podiums then
        unbindPodiums(podiums)
    end
end

local function bindBase(base)
    if not (base and base.Parent) then
        return
    end
    if state.baseConns[base] then
        return
    end
    local function onChildAdded(child)
        if child and child.Name == "AnimalPodiums" then
            bindPodiums(child)
        end
    end
    state.baseConns[base] = {
        added = base.ChildAdded:Connect(onChildAdded),
        ancestry = base.AncestryChanged:Connect(function(_, parent)
            if not parent then
                unbindBase(base)
            end
        end),
    }
    local podiums = base:FindFirstChild("AnimalPodiums")
    if podiums then
        bindPodiums(podiums)
    end
end

local function unbindPlots(plots)
    if state.connections.plotsChildAdded then
        safeCall(function()
            state.connections.plotsChildAdded:Disconnect()
        end)
        state.connections.plotsChildAdded = nil
    end
    if state.connections.plotsChildRemoved then
        safeCall(function()
            state.connections.plotsChildRemoved:Disconnect()
        end)
        state.connections.plotsChildRemoved = nil
    end
    for base in pairs(state.baseConns) do
        unbindBase(base)
    end
    state.boundPlots = nil
end

local function bindPlots(plots)
    if not plots then
        return
    end
    if state.boundPlots == plots then
        return
    end
    if state.boundPlots then
        unbindPlots(state.boundPlots)
    end
    state.boundPlots = plots
    for _, base in ipairs(plots:GetChildren()) do
        bindBase(base)
    end
    state.connections.plotsChildAdded = plots.ChildAdded:Connect(function(child)
        bindBase(child)
    end)
    state.connections.plotsChildRemoved = plots.ChildRemoved:Connect(function(child)
        if child then
            unbindBase(child)
        end
    end)
end

local function processQueue()
    local now = os.clock()
    local start = now
    local budget = state.queueBudget or 6
    while budget > 0 do
        local stand = dequeueStand()
        if not stand then
            break
        end
        state.queueSet[stand] = nil
        local force = state.forceSet[stand]
        state.forceSet[stand] = nil
        if stand and stand.Parent then
            if force then
                local meta = state.tracked[stand]
                if meta then
                    meta.nextUpdateAt = 0
                end
            end
            updateStandEsp(stand)
        else
            untrackStand(stand)
        end
        budget = budget - 1
        if (os.clock() - start) > (state.frameBudget or 0.003) then
            break
        end
    end
    if state.bestDirty and (now - (state.lastBestRefresh or 0)) >= 0.5 then
        refreshMostExpensiveVisibility()
        state.bestDirty = false
        state.lastBestRefresh = now
    end
end

local function heartbeatStep(dt)
    if not state.enabled then
        return
    end
    state.refreshAccumulator = (state.refreshAccumulator or 0) + dt
    if state.refreshAccumulator >= (state.refreshInterval or 3) then
        state.refreshAccumulator = 0
        if table.clear then
            table.clear(state.refreshList)
        else
            state.refreshList = {}
        end
        for stand in pairs(state.knownStands) do
            state.refreshList[#state.refreshList + 1] = stand
        end
        state.refreshIndex = 1
    end
    local batch = state.refreshBatch or 6
    while batch > 0 and state.refreshIndex <= #state.refreshList do
        local stand = state.refreshList[state.refreshIndex]
        state.refreshIndex = state.refreshIndex + 1
        enqueueStand(stand, false)
        batch = batch - 1
    end
    processQueue()
end

local function startEsp()
    if state.enabled then
        return
    end
    state.enabled = true
    if table.clear then
        table.clear(state.queue)
        table.clear(state.queueSet)
        table.clear(state.forceSet)
        table.clear(state.refreshList)
        table.clear(state.knownStands)
        table.clear(state.baseConns)
        table.clear(state.podiumsConns)
    else
        state.queue = {}
        state.queueSet = setmetatable({}, { __mode = "k" })
        state.forceSet = setmetatable({}, { __mode = "k" })
        state.refreshList = {}
        state.knownStands = setmetatable({}, { __mode = "k" })
        state.baseConns = setmetatable({}, { __mode = "k" })
        state.podiumsConns = setmetatable({}, { __mode = "k" })
    end
    state.queueHead = 1
    state.queueTail = 0
    state.refreshIndex = 1
    state.refreshAccumulator = 0
    state.bestDirty = true
    state.lastBestRefresh = 0
    local plots = getPlotsFolder()
    if plots then
        bindPlots(plots)
        state.connections.workspaceChildAdded = Workspace.ChildAdded:Connect(function(child)
            if child and child.Name == "Plots" then
                bindPlots(child)
            end
        end)
        state.connections.workspaceChildRemoved = Workspace.ChildRemoved:Connect(function(child)
            if child and child == state.boundPlots then
                unbindPlots(child)
            end
        end)
    else
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst.Name == "AnimalPodiums" then
                bindPodiums(inst)
            end
        end
        state.connections.descAdded = Workspace.DescendantAdded:Connect(function(inst)
            if inst and inst.Name == "AnimalPodiums" then
                bindPodiums(inst)
            end
        end)
    end
    state.connections.heartbeat = RunService.Heartbeat:Connect(heartbeatStep)
    state.notify("Brainrot ESP enabled")
end

local function stopEsp()
    if not state.enabled then
        return
    end
    state.enabled = false
    for _, conn in pairs(state.connections) do
        safeCall(function()
            conn:Disconnect()
        end)
    end
    state.connections = {}
    unbindPlots(state.boundPlots)
    for podiums in pairs(state.podiumsConns) do
        unbindPodiums(podiums)
    end
    for stand in pairs(state.knownStands) do
        untrackStand(stand)
    end
    for stand in pairs(state.tracked) do
        clearStandVisual(stand)
    end
    destroyBeam()
    state.baseChannelCache = {}
    state.bestMeta = nil
    state.notify("Brainrot ESP disabled")
end

local function setMostExpensive(value)
    state.mostExpensiveOnly = value and true or false
    state.bestDirty = true
    refreshMostExpensiveVisibility()
end

local function getBestBrainrot()
    local meta = computeBestMeta()
    if not meta then
        return nil
    end
    local target = meta.currentAdornee or meta.root
    if target and target.Parent then
        return target, meta
    end
    return nil
end

local function attachUi(section)
    if not section or type(section.CreateToggle) ~= "function" then
        return
    end
    local espToggle = section:CreateToggle({
        Title = "Brainrot ESP",
        Default = false,
        SaveKey = "brainrot_esp_enabled",
        Callback = function(enabled)
            if enabled then
                startEsp()
            else
                stopEsp()
            end
        end,
    })
    local expensiveToggle = section:CreateToggle({
        Title = "Most Expensive Only",
        Default = false,
        SaveKey = "brainrot_esp_most_expensive",
        Callback = function(val)
            setMostExpensive(val)
        end,
    })
    return espToggle, expensiveToggle
end

local function resolveSection()
    local env = nil
    pcall(function()
        env = getgenv and getgenv()
    end)
    if not env then
        return nil, nil, nil
    end
    local section = env.BrainrotESPSection
        or (env.sections and env.sections.esp)
        or env.ESPSection
    local theme = env.theme or (env.Library and env.Library.Theme) or {}
    local notify
    if typeof(env.notify) == "function" then
        notify = function(msg)
            env.notify("Brainrot ESP", msg)
        end
    elseif env.Library and typeof(env.Library.Notify) == "function" then
        notify = function(msg)
            env.Library:Notify({ Title = "Brainrot ESP", Text = msg, Duration = 3 })
        end
    end
    return section, theme, notify
end

function module.setup(opts)
    opts = opts or {}
    applyOptions(opts)
    local section = opts.section
    if not section then
        local resolvedSection, theme, notify = resolveSection()
        opts.theme = opts.theme or theme
        if notify then
            opts.notify = opts.notify or notify
        end
        applyOptions(opts)
        section = resolvedSection
    end
    local mainToggle, expensiveToggle = attachUi(section)
    if not mainToggle then
        startEsp()
    else
        if mainToggle.GetState and mainToggle:GetState() then
            startEsp()
        end
        if expensiveToggle and expensiveToggle.GetState then
            setMostExpensive(expensiveToggle:GetState())
        end
    end
    return {
        start = startEsp,
        stop = stopEsp,
        setMostExpensive = setMostExpensive,
        getBestBrainrot = getBestBrainrot,
        brainrotToggle = mainToggle,
        mostExpensiveToggle = expensiveToggle,
    }
end

function module.start(opts)
    opts = opts or {}
    applyOptions(opts)
    local controller = module.setup(opts)
    if opts.autoStart == false then
        stopEsp()
    end
    if typeof(opts.mostExpensiveOnly) == "boolean" then
        setMostExpensive(opts.mostExpensiveOnly)
    end
    module.controller = controller
    return controller
end

module.getBestBrainrot = getBestBrainrot

-- Auto attach if environment provides a section; otherwise auto-start.
local autoSection, autoTheme, autoNotify = resolveSection()
if autoSection then
    module.controller = module.setup({
        section = autoSection,
        theme = autoTheme,
        notify = autoNotify,
    })
else
    module.controller = module.start({ autoStart = true })
end

return module

