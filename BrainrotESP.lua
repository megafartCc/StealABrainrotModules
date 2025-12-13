
local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Workspace = game:GetService('Workspace')
local RunService = game:GetService('RunService')

local BrainrotESP = {}
local singleton

local function createFallbackSection()
    local stub = {}
    function stub:CreateToggle(definition)
        definition = definition or {}
        local callback = typeof(definition.Callback) == 'function' and definition.Callback or function() end
        local toggle = { _state = definition.Default and true or false }
        function toggle:SetState(value)
            self._state = value and true or false
            task.defer(callback, self._state)
        end
        if definition.Default ~= nil then
            task.defer(callback, definition.Default and true or false)
        end
        return toggle
    end
    return stub
end

local function toTitleCase(s)
    if type(s) ~= 'string' then
        return ''
    end
    return s:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

local function clean(str)
    return tostring(str or ''):gsub('%+', ''):gsub('^%s*(.-)%s*$', '%1')
end

local function parseMoney(moneyStr)
    if not moneyStr or moneyStr == 'TBA' then
        return 0
    end
    local cleaned = clean(moneyStr):gsub(',', '')
    local num, suffix = cleaned:match('^%$?([%d%.]+)([MKBT]?)')
    num = tonumber(num)
    if not num then
        return 0
    end
    if suffix == 'B' then
        return num * 1e9
    elseif suffix == 'M' then
        return num * 1e6
    elseif suffix == 'K' then
        return num * 1e3
    elseif suffix == 'T' then
        return num * 1e12
    end
    return num
end

local function formatMoney(num)
    if not num or num == 0 then
        return '$0'
    end
    if num >= 1e12 then
        return string.format('$%.1fT', num / 1e12)
    end
    if num >= 1e9 then
        return string.format('$%.1fB', num / 1e9)
    end
    if num >= 1e6 then
        return string.format('$%.1fM', num / 1e6)
    end
    if num >= 1e3 then
        return string.format('$%.0fK', num / 1e3)
    end
    return '$' .. tostring(num)
end

local function safeDisconnectConn(conn)
    if conn and typeof(conn) == 'RBXScriptConnection' then
        pcall(function()
            conn:Disconnect()
        end)
    end
end

local function safeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

local function getHRP()
    local player = Players.LocalPlayer
    local char = player and player.Character
    return char and char:FindFirstChild('HumanoidRootPart')
end

local function createController(opts)
    opts = opts or {}
    local section = opts.section
    if not (section and section.CreateToggle) then
        section = createFallbackSection()
    end
    local theme = opts.theme or {}
    local notify = opts.notify or function(title, text)
        warn(title or 'Brainrot ESP', text or '')
    end
    local player = Players.LocalPlayer

    local THEME = {
        accentA = theme.accentA or theme.accent or Color3.fromRGB(64, 156, 255),
        accentB = theme.accentB or theme.accent or Color3.fromRGB(0, 204, 204),
        panel2 = theme.panel2 or Color3.fromRGB(22, 24, 30),
        text = theme.text or Color3.fromRGB(230, 235, 240),
        gold = theme.gold or Color3.fromRGB(255, 215, 0),
    }

    local BRAINROT_DATA_UPDATE_INTERVAL = 1.5
    local brainrotESPEnabled = false
    local mostExpensiveOnlyEnabled = false
    local brainrotDict = {}
    local brainrotLookup = {}
    local activeBrainrotVisuals = {}
    local brainrotESP_connections = {}
    local brainrotCharConn = nil
    local myPlayerBase = nil
    local mostExpensiveBrainrot = nil
    local sharedAnimals = nil
    local Synchronizer = require(ReplicatedStorage.Packages.Synchronizer)
    local NumberUtils = require(ReplicatedStorage.Utils.NumberUtils)
    local AnimalsData = require(ReplicatedStorage.Datas.Animals)
    local MutationsData = require(ReplicatedStorage.Datas.Mutations)
    local TraitsData = require(ReplicatedStorage.Datas.Traits)
    local GameData = require(ReplicatedStorage.Datas.Game).Game
    local baseChannelCache = {}
    local mutationMultipliers = {}
    local traitMultipliers = {}
    local modifiersLoaded = false
    local fallbackMutationMultipliers = {
        Gold = 1.25,
        Diamond = 1.5,
        Rainbow = 10,
        Lava = 6,
        Bloodrot = 2,
        Celestial = 4,
        Candy = 4,
        Galaxy = 6,
    }
    local fallbackTraitMultipliers = {
        Taco = 3,
        Nyan = 6,
        Galactic = 4,
        Fireworks = 6,
        Zombie = 5,
        Claws = 5,
        Glitched = 5,
        Bubblegum = 4,
        Fire = 6,
        Wet = 2.5,
        Snowy = 3,
        Cometstruck = 3.5,
        Explosive = 4,
        Disco = 5,
        ['10B'] = 3,
        Rain = 3,
        Starfall = 3.5,
        Golden = 6,
        ['Golden Shine'] = 6,
    }

    local function applyTheme(newTheme)
        if newTheme then
            theme = newTheme
        end
        THEME.accentA = theme.accentA or theme.accent or THEME.accentA
        THEME.accentB = theme.accentB or theme.accent or THEME.accentB
        THEME.panel2 = theme.panel2 or THEME.panel2
        THEME.text = theme.text or THEME.text
        THEME.gold = theme.gold or THEME.gold
        for _, visuals in pairs(activeBrainrotVisuals) do
            if visuals.hl then
                visuals.hl.FillColor = THEME.accentA
                visuals.hl.OutlineColor = THEME.accentB
            end
            if visuals.tracer then
                visuals.tracer.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, THEME.accentA),
                    ColorSequenceKeypoint.new(1, THEME.accentB),
                })
            end
            if visuals.esp then
                local bg = visuals.esp:FindFirstChildWhichIsA('Frame')
                if bg then
                    bg.BackgroundColor3 = THEME.panel2
                    local stroke = bg:FindFirstChildOfClass('UIStroke')
                    if stroke then
                        stroke.Color = THEME.accentA
                    end
                end
            end
            if visuals.labelStroke then
                visuals.labelStroke.Color = THEME.accentB
            end
        end
    end
    applyTheme(theme)

    local function loadGameModifiers()
        if modifiersLoaded then
            return
        end
        modifiersLoaded = true
        local okMut, mutations = pcall(function()
            return require(ReplicatedStorage.Datas.Mutations)
        end)
        if okMut and type(mutations) == 'table' then
            for name, data in pairs(mutations) do
                if type(data) == 'table' and data.Modifier then
                    mutationMultipliers[name] = 1 + (tonumber(data.Modifier) or 0)
                end
            end
        end
        local okTraits, traits = pcall(function()
            return require(ReplicatedStorage.Datas.Traits)
        end)
        if okTraits and type(traits) == 'table' then
            for name, data in pairs(traits) do
                if type(data) == 'table' and data.MultiplierModifier then
                    traitMultipliers[name] = 1 + (tonumber(data.MultiplierModifier) or 0)
                end
            end
        end
        for k, v in pairs(fallbackMutationMultipliers) do
            if not mutationMultipliers[k] then
                mutationMultipliers[k] = v
            end
        end
        for k, v in pairs(fallbackTraitMultipliers) do
            if not traitMultipliers[k] then
                traitMultipliers[k] = v
            end
        end
    end

    local function buildDynamicDictionary()
        loadGameModifiers()
        if not sharedAnimals then
            local okSA, mod = pcall(function()
                return require(ReplicatedStorage.Shared.Animals)
            end)
            if okSA and mod then
                sharedAnimals = mod
            end
        end
        local datasFolder = ReplicatedStorage:WaitForChild('Datas', 20)
        if not datasFolder then
            return false
        end
        local animalsModule = datasFolder:WaitForChild('Animals', 20)
        if not animalsModule then
            return false
        end
        local success, gameAnimals = pcall(function()
            return require(animalsModule)
        end)
        if success and type(gameAnimals) == 'table' then
            for _, animalData in pairs(gameAnimals) do
                local displayName = animalData['DisplayName']
                local internalName = animalData['Name'] or animalData['Id']
                local dpsValue = animalData['Generation'] or 0
                if displayName then
                    brainrotDict[displayName] = {
                        rarity = animalData['Rarity'] or 'Unknown',
                        dps = dpsValue,
                        displayName = displayName,
                    }
                    brainrotLookup[displayName:lower()] = brainrotDict[displayName]
                end
                if internalName and not brainrotDict[internalName] then
                    brainrotDict[internalName] = {
                        rarity = animalData['Rarity'] or 'Unknown',
                        dps = dpsValue,
                        displayName = displayName or internalName,
                    }
                end
                if internalName then
                    brainrotLookup[internalName:lower()] = brainrotDict[internalName]
                end
            end
            return true
        end
        return false
    end
    local function getBrainrotEntryByName(name)
        if not name then
            return nil
        end
        return brainrotLookup[name:lower()]
    end

    local function safePlayerMultiplier(targetPlayer)
        local ok, mod = pcall(function()
            return require(ReplicatedStorage.Shared.Game)
        end)
        if not ok or not mod or type(mod.GetPlayerCashMultiplayer) ~= 'function' then
            return 1
        end
        local okMult, mult = pcall(mod.GetPlayerCashMultiplayer, mod, targetPlayer)
        return okMult and tonumber(mult) or 1
    end

    local function getMutationAndTraits(model)
        local mutation, traits
        pcall(function()
            mutation = model:GetAttribute('Mutation')
        end)
        if not mutation then
            local v = model:FindFirstChild('Mutation')
            if v and v:IsA('StringValue') then
                mutation = v.Value
            end
        end
        if not mutation then
            local folder = model:FindFirstChild('MutationFolder') or model:FindFirstChild('Mutations')
            if folder then
                for _, child in ipairs(folder:GetChildren()) do
                    if child:IsA('StringValue') then
                        mutation = child.Value
                        break
                    end
                end
            end
        end
        pcall(function()
            if model:GetAttribute('Traits') then
                traits = model:GetAttribute('Traits')
            elseif model:GetAttribute('Trait') then
                traits = { model:GetAttribute('Trait') }
            end
        end)
        if not traits then
            local t = model:FindFirstChild('Traits') or model:FindFirstChild('TraitsFolder')
            if t and t:IsA('Folder') then
                traits = {}
                for _, v in ipairs(t:GetChildren()) do
                    if v:IsA('StringValue') then
                        table.insert(traits, v.Value)
                    end
                end
            end
        end
        if type(traits) == 'string' then
            traits = { traits }
        end
        return mutation, traits
    end

    local function calculateMultiplier(mutation, traits)
        local multipliers, n = {}, 0
        if mutation and mutationMultipliers[mutation] then
            table.insert(multipliers, mutationMultipliers[mutation])
            n = n + 1
        else
            table.insert(multipliers, 1)
            n = n + 1
        end
        if traits then
            for _, trait in ipairs(traits) do
                if traitMultipliers[trait] then
                    table.insert(multipliers, traitMultipliers[trait])
                    n = n + 1
                end
            end
        end
        if n == 0 then
            return 1
        end
        local sum = 0
        for _, mult in ipairs(multipliers) do
            sum = sum + mult
        end
        local total = sum - (n - 1)
        return total < 1 and 1 or total
    end

    local function computeGeneration(index, mutation, traits, owner)
        local animal = index and AnimalsData[index]
        if not animal then
            return 0
        end
        local baseGen = animal.Generation or ((animal.Price or 0) * (GameData.AnimalGanerationModifier or 0))
        local mult = calculateMultiplier(mutation, traits)
        local sleepy = false
        if typeof(traits) == 'table' then
            for _, trait in ipairs(traits) do
                if TraitsData[trait] and trait == 'Sleepy' then
                    sleepy = true
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

    local function getPlayerBase()
        local plots = Workspace:FindFirstChild('Plots')
        if not plots then
            return nil
        end
        local fallback = nil
        for _, plot in ipairs(plots:GetChildren()) do
            local sign = plot:FindFirstChild('PlotSign')
            local yourBase = sign and sign:FindFirstChild('YourBase')
            if yourBase then
                local isMine = (yourBase:IsA('BoolValue') and yourBase.Value == true)
                    or (yourBase:IsA('BaseScript') and yourBase.Enabled == true)
                    or yourBase.Enabled == true
                if isMine then
                    return plot
                end
            end
            local ownerValue = sign and (sign:FindFirstChild('Owner') or sign:FindFirstChild('Player') or sign:FindFirstChild('Username'))
            if ownerValue then
                if ownerValue:IsA('ObjectValue') and ownerValue.Value == player then
                    return plot
                end
                if ownerValue:IsA('StringValue') and ownerValue.Value == player.Name then
                    return plot
                end
            end
            local attrOwner = plot:GetAttribute('Owner') or plot:GetAttribute('OwnerName')
            if attrOwner and tostring(attrOwner) == player.Name then
                fallback = plot
            end
        end
        return fallback
    end
    local function getStandBase(stand)
        if not stand or not stand.Parent then
            return nil
        end
        if stand.Parent.Name == 'AnimalPodiums' then
            return stand.Parent.Parent
        end
        return stand:FindFirstAncestorOfClass('Model')
    end

    local function getValidStandBase(stand)
        if not stand then
            return nil
        end
        local plots = Workspace:FindFirstChild('Plots')
        if not plots then
            return nil
        end
        local base = getStandBase(stand)
        if not base or not base:IsDescendantOf(plots) then
            return nil
        end
        if not base:FindFirstChild('PlotSign') then
            return nil
        end
        return base
    end

    local function getStandSpawnAttachment(stand)
        if not stand then
            return nil
        end
        local base = stand and stand:FindFirstChild('Base')
        local spawn = base and base:FindFirstChild('Spawn')
        if not spawn then
            return nil
        end
        return spawn:FindFirstChildWhichIsA('Attachment')
    end

    local function getStandOverhead(stand)
        local attachment = getStandSpawnAttachment(stand)
        if not attachment then
            return nil
        end
        return attachment:FindFirstChild('AnimalOverhead')
    end

    local function getStandSlot(stand)
        if not stand then
            return nil
        end
        local n = tonumber(stand.Name)
        if n then
            return n
        end
        local attr = stand:GetAttribute('Slot') or stand:GetAttribute('Index')
        return tonumber(attr)
    end

    local function getStandOwnerName(base)
        if not base then
            return nil
        end
        local sign = base:FindFirstChild('PlotSign')
        if sign then
            local ownerValue = sign:FindFirstChild('Owner') or sign:FindFirstChild('Player') or sign:FindFirstChild('Username')
            if ownerValue and ownerValue:IsA('ObjectValue') and ownerValue.Value then
                return ownerValue.Value.Name
            end
            if ownerValue and ownerValue:IsA('StringValue') then
                return ownerValue.Value
            end
        end
        local attrOwner = base:GetAttribute('Owner') or base:GetAttribute('OwnerName')
        if attrOwner then
            return tostring(attrOwner)
        end
        if base.Name and base.Name ~= '' then
            local uid = tonumber(base.Name)
            if uid then
                local plr = Players:GetPlayerByUserId(uid)
                if plr then
                    return plr.Name
                end
            end
            return base.Name
        end
    end

    local function findLabelMatching(overhead, matcher)
        if not overhead then
            return nil
        end
        for _, lbl in ipairs(overhead:GetDescendants()) do
            if lbl:IsA('TextLabel') and matcher(lbl) then
                return lbl
            end
        end
    end

    local function normalizeMoneyText(text)
        if not text or text == '' then
            return nil
        end
        if text:lower():find('ready') then
            return nil
        end
        local cleaned = text:gsub('%s*/%s*s', '')
        if cleaned:find('$') then
            cleaned = cleaned
        elseif tonumber(cleaned) then
            cleaned = '$' .. cleaned
        end
        if cleaned:find('/s') then
            return cleaned
        end
        return cleaned .. '/s'
    end

    local function resolveOverheadInfo(stand)
        local attachment = getStandSpawnAttachment(stand)
        if not attachment then
            return nil, nil
        end
        local overhead = attachment:FindFirstChild('AnimalOverhead', true) or attachment:FindFirstChildWhichIsA('BillboardGui')
        if not overhead then
            return nil, nil
        end
        local nameLabel = overhead:FindFirstChild('DisplayName', true)
            or findLabelMatching(overhead, function(lbl)
                local lname = lbl.Name:lower()
                return lname:find('display') or lname:find('name')
            end)
        local genLabel = overhead:FindFirstChild('Generation', true)
            or findLabelMatching(overhead, function(lbl)
                return lbl.Name:lower():find('gen') or (lbl.Text and lbl.Text:find('%$'))
            end)
        local moneyText = genLabel and genLabel.Text or nil
        moneyText = normalizeMoneyText(moneyText)
        local brainrotName = nameLabel and clean(nameLabel.Text) or nil
        return brainrotName, moneyText
    end

    local function findBrainrotModelOnStand(stand)
        if not stand or not stand.Parent then
            return nil
        end
        for _, desc in ipairs(stand:GetDescendants()) do
            if desc:IsA('Model') then
                local root = desc:FindFirstChild('RootPart') or desc:FindFirstChild('HumanoidRootPart') or desc.PrimaryPart
                if root and (getBrainrotEntryByName(desc.Name) or desc:FindFirstChild('Mutation') or desc:GetAttribute('Mutation')) then
                    return desc, root
                end
            end
        end
    end

    local function getStandRootPart(stand)
        if not stand or not stand.Parent then
            return nil
        end
        local model, root = findBrainrotModelOnStand(stand)
        if root then
            return model, root
        end
        local base = stand and stand:FindFirstChild('Base')
        if base then
            local spawn = base:FindFirstChild('Spawn')
            if spawn and spawn:IsA('BasePart') then
                return nil, spawn
            end
        end
        local fallback = stand and (stand.PrimaryPart or stand:FindFirstChildWhichIsA('BasePart'))
        return nil, fallback
    end

    local function resolveBrainrotName(stand, model)
        local overheadName = stand and select(1, resolveOverheadInfo(stand))
        if overheadName and overheadName ~= '' then
            return overheadName
        end
        if stand then
            local attributeName = stand:GetAttribute('Animal') or stand:GetAttribute('Brainrot') or stand:GetAttribute('Pet')
            if attributeName and attributeName ~= '' then
                return attributeName
            end
        end
        if model then
            return model.Name
        end
    end

    local calculateBrainrotStats

    local function resolveMoneyForStand(stand, model, resolvedName)
        local _, overheadMoney = resolveOverheadInfo(stand)
        local moneyText = overheadMoney
        local moneyValue = moneyText and parseMoney(moneyText) or 0
        if moneyValue <= 0 then
            local attrIncome = stand and (stand:GetAttribute('IncomePerSecond') or stand:GetAttribute('Income') or stand:GetAttribute('Gen') or stand:GetAttribute('Generation'))
            if not attrIncome and model then
                attrIncome = model:GetAttribute('IncomePerSecond') or model:GetAttribute('Income') or model:GetAttribute('Gen') or model:GetAttribute('Generation')
            end
            if attrIncome then
                moneyValue = tonumber(attrIncome) or parseMoney(tostring(attrIncome))
            end
        end
        if moneyValue <= 0 and stand then
            local incomeValue = stand:FindFirstChild('Income') or stand:FindFirstChild('MoneyPerSecond')
            if incomeValue and incomeValue.Value then
                moneyValue = tonumber(incomeValue.Value) or parseMoney(tostring(incomeValue.Value))
            end
        end
        if moneyValue <= 0 and model then
            local mutation, traits = getMutationAndTraits(model)
            local computed = calculateBrainrotStats(model, resolvedName)
            if computed == 0 then
                computed = computeGeneration(resolvedName, mutation, traits, nil)
            end
            moneyValue = computed
            moneyText = normalizeMoneyText(formatMoney(computed))
        end
        if moneyValue <= 0 and sharedAnimals and resolvedName then
            local computed = sharedAnimals:GetGeneration(resolvedName, nil, nil, nil) or 0
            moneyValue = computed
            moneyText = normalizeMoneyText(formatMoney(computed))
        end
        if moneyValue <= 0 then
            moneyText = '$0/s'
        elseif moneyValue > 0 and not moneyText then
            moneyText = normalizeMoneyText(formatMoney(moneyValue))
        end
        return moneyText, moneyValue or 0
    end

    calculateBrainrotStats = function(model, overrideName)
        if not model then
            return 0
        end
        local baseName = overrideName or (model and model.Name)
        local entry = baseName and getBrainrotEntryByName(baseName)
        local baseDPS = entry and entry.dps or 0
        local mutation, traits = getMutationAndTraits(model)
        local multiplier = calculateMultiplier(mutation, traits)
        return baseDPS * multiplier
    end

    local function isModelHeldByPlayer(model)
        if not model then
            return false
        end
        local root = model:FindFirstChild('RootPart') or model:FindFirstChild('HumanoidRootPart') or model.PrimaryPart
        if not root then
            return false
        end
        local weld = root:FindFirstChildOfClass('WeldConstraint')
        if weld and weld.Part1 and weld.Part1.Parent and weld.Part1.Parent:FindFirstChildOfClass('Humanoid') then
            return true
        end
        return false
    end

    local function getBaseChannel(base)
        if not base then
            return nil
        end
        if baseChannelCache[base] then
            return baseChannelCache[base]
        end
        local channel = Synchronizer:Get(base.Name) or Synchronizer:Wait(base.Name)
        baseChannelCache[base] = channel
        return channel
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
        local slotNum = getStandSlot(stand)
        local animals = channel and (channel:Get('AnimalList') or channel:Get('AnimalPodiums')) or nil
        local animalData = animals and animals[slotNum] or nil
        if type(animalData) ~= 'table' then
            return nil
        end
        local model, root = getStandRootPart(stand)
        if not root then
            return nil
        end
        local resolvedName
        if animalData.Index and AnimalsData[animalData.Index] then
            local entry = AnimalsData[animalData.Index]
            resolvedName = entry.DisplayName or animalData.Index
        else
            resolvedName = animalData.Index or resolveBrainrotName(stand, model) or 'Brainrot'
        end
        local computedGen = computeGeneration(animalData.Index, animalData.Mutation, animalData.Traits, channel and channel:Get('Owner'))
        local moneyValue = tonumber(computedGen) or 0
        local moneyText = ('$%s/s'):format(NumberUtils:ToString(moneyValue, 1))
        local ownerName = nil
        do
            local owner = channel and channel:Get('Owner')
            if owner and typeof(owner) == 'Instance' and owner:IsA('Player') then
                ownerName = owner.Name
            elseif type(owner) == 'table' then
                ownerName = owner.Username or owner.Name
            elseif type(owner) == 'string' then
                ownerName = owner
            end
        end
        local isFusing = stand.Name:lower():find('fuse') or (stand:GetAttribute('Fusing') == true)
        return {
            key = stand,
            stand = stand,
            base = base,
            model = model,
            root = root,
            owner = ownerName or (function()
                local o = getStandOwnerName(base)
                if o == 'YOUR BASE' then
                    return nil
                end
                return o
            end)(),
            name = resolvedName or 'Brainrot',
            moneyText = moneyText,
            moneyValue = moneyValue,
            isFusing = isFusing,
            isStand = true,
        }
    end

    local function buildLooseBrainrotInfo(model)
        return nil
    end

    local function cleanupBrainrotVisuals(target)
        local visuals = activeBrainrotVisuals[target]
        if not visuals then
            return
        end
        pcall(function()
            visuals.hl:Destroy()
        end)
        pcall(function()
            visuals.esp:Destroy()
        end)
        pcall(function()
            visuals.tracer:Destroy()
        end)
        pcall(function()
            visuals.att0:Destroy()
        end)
        pcall(function()
            visuals.att1:Destroy()
        end)
        activeBrainrotVisuals[target] = nil
    end

    local function createOrUpdateBrainrotVisuals(info)
        if not info or not info.root then
            return
        end
        local target = info.key
        local visuals = activeBrainrotVisuals[target]
        if not visuals then
            visuals = {
                cachedMoneyPerSec = '$0/s',
                cachedMoneyValue = 0,
                brainrotName = 'Brainrot',
                isStand = info.isStand,
            }
            visuals.hl = Instance.new('Highlight')
            visuals.hl.FillColor = THEME.accentA
            visuals.hl.OutlineColor = THEME.accentB
            visuals.hl.FillTransparency = 0.35
            visuals.hl.OutlineTransparency = 0.1
            visuals.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            visuals.hl.Adornee = info.model or info.root
            visuals.hl.Parent = info.model or info.root
            visuals.esp = Instance.new('BillboardGui')
            visuals.esp.Name = 'ESPName'
            visuals.esp.AlwaysOnTop = true
            visuals.esp.Adornee = info.root
            visuals.esp.Size = UDim2.new(0, 150, 0, 34)
            visuals.esp.Parent = info.root
            local bgFrame = Instance.new('Frame', visuals.esp)
            bgFrame.Size = UDim2.new(1, 0, 1, 0)
            bgFrame.BackgroundColor3 = THEME.panel2
            bgFrame.BackgroundTransparency = 0.2
            Instance.new('UICorner', bgFrame).CornerRadius = UDim.new(0, 6)
            local stroke = Instance.new('UIStroke', bgFrame)
            stroke.Color = THEME.accentA
            stroke.Thickness = 1
            visuals.label = Instance.new('TextLabel', bgFrame)
            visuals.label.Size = UDim2.new(1, -6, 1, -4)
            visuals.label.Position = UDim2.new(0, 3, 0, 2)
            visuals.label.BackgroundTransparency = 1
            visuals.label.TextColor3 = THEME.text
            visuals.label.Font = Enum.Font.GothamBold
            visuals.label.RichText = true
            visuals.label.TextScaled = false
            visuals.label.TextSize = 13
            visuals.label.TextWrapped = true
            visuals.labelStroke = Instance.new('UIStroke', visuals.label)
            visuals.labelStroke.Thickness = 1
            visuals.labelStroke.Color = THEME.accentB
            visuals.labelStroke.Transparency = 0.15
            visuals.att0 = Instance.new('Attachment', getHRP())
            visuals.att1 = Instance.new('Attachment', info.root)
            visuals.tracer = Instance.new('Beam', info.root)
            visuals.tracer.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, THEME.accentA),
                ColorSequenceKeypoint.new(1, THEME.accentB),
            })
            visuals.tracer.Width0 = 0.2
            visuals.tracer.Width1 = 0.1
            visuals.tracer.FaceCamera = true
            visuals.tracer.Transparency = NumberSequence.new(0.35)
            visuals.tracer.Attachment0 = visuals.att0
            visuals.tracer.Attachment1 = visuals.att1
            activeBrainrotVisuals[target] = visuals
        end
        visuals.key = target
        visuals.model = info.model
        visuals.root = info.root
        visuals.base = info.base
        visuals.owner = info.owner
        visuals.brainrotName = info.name or 'Brainrot'
        visuals.cachedMoneyPerSec = info.moneyText or '$0/s'
        visuals.cachedMoneyValue = info.moneyValue or 0
        visuals.isStand = info.isStand and true or false
        visuals.isFusing = info.isFusing
        if visuals.att1.Parent ~= info.root then
            visuals.att1.Parent = info.root
        end
        visuals.tracer.Attachment1 = visuals.att1
        visuals.esp.Adornee = info.root
        visuals.esp.Parent = info.root
        visuals.hl.Adornee = info.model or info.root or target
        visuals.hl.Parent = info.model or target or info.root
    end

    local function cleanupBrainrotVisualsForRemoved(target)
        if activeBrainrotVisuals[target] then
            cleanupBrainrotVisuals(target)
        end
    end
    local function handleStandAdded(descendant)
        if not descendant or not descendant:IsA('Model') then
            return
        end
        if descendant.Parent and descendant.Parent.Name == 'AnimalPodiums' then
            if not getValidStandBase(descendant) then
                return
            end
            local info = safeCall(buildStandBrainrotInfo, descendant)
            if info then
                safeCall(createOrUpdateBrainrotVisuals, info)
            end
        end
    end

    local function handleStandRemoving(descendant)
        if descendant and descendant.Parent and descendant.Parent.Name == 'AnimalPodiums' then
            if not getValidStandBase(descendant) then
                return
            end
            cleanupBrainrotVisualsForRemoved(descendant)
        end
    end

    local function initialBrainrotScan()
        local plots = Workspace:FindFirstChild('Plots')
        if plots then
            for _, base in ipairs(plots:GetChildren()) do
                local podiums = base:FindFirstChild('AnimalPodiums')
                if podiums then
                    for _, stand in ipairs(podiums:GetChildren()) do
                        safeCall(handleStandAdded, stand)
                    end
                end
            end
        end
    end

    local function cleanupInvalidVisuals()
        for target, visuals in pairs(activeBrainrotVisuals) do
            if not visuals.root or not visuals.root.Parent then
                cleanupBrainrotVisuals(target)
            end
        end
    end

    local function updateBrainrotInfo()
        safeCall(initialBrainrotScan)
        myPlayerBase = getPlayerBase()
        local maxMoney = -1
        local bestTarget = nil
        for target, visuals in pairs(activeBrainrotVisuals) do
            local info
            if visuals.isStand then
                info = safeCall(buildStandBrainrotInfo, target)
            else
                cleanupBrainrotVisuals(target)
                visuals = nil
            end
            if info and info.root then
                info.isHeld = isModelHeldByPlayer(info.model)
                info.shouldBeVisible = not info.isHeld
                    and not info.isFusing
                    and not (info.base and myPlayerBase and info.base == myPlayerBase)
                safeCall(createOrUpdateBrainrotVisuals, info)
                visuals.shouldBeVisible = info.shouldBeVisible
                visuals.cachedMoneyPerSec = info.moneyText or visuals.cachedMoneyPerSec
                visuals.cachedMoneyValue = info.moneyValue or visuals.cachedMoneyValue
                if visuals.cachedMoneyValue > maxMoney then
                    maxMoney = visuals.cachedMoneyValue
                    bestTarget = target
                end
            else
                cleanupBrainrotVisuals(target)
            end
        end
        mostExpensiveBrainrot = bestTarget
    end

    local function startBrainrotVisualLoop()
        brainrotESP_connections.render = RunService.RenderStepped:Connect(function()
            local playerRoot = getHRP()
            if not playerRoot then
                return
            end
            for target, visuals in pairs(activeBrainrotVisuals) do
                if not (visuals.root and visuals.root.Parent) then
                    cleanupBrainrotVisuals(target)
                    continue
                end
                if visuals.att0.Parent ~= playerRoot then
                    visuals.att0.Parent = playerRoot
                end
                local shouldBeVisible = visuals.shouldBeVisible
                if mostExpensiveOnlyEnabled and target ~= mostExpensiveBrainrot then
                    shouldBeVisible = false
                end
                if visuals.esp.Enabled ~= shouldBeVisible then
                    visuals.esp.Enabled = shouldBeVisible
                    visuals.hl.Enabled = shouldBeVisible
                    visuals.tracer.Enabled = shouldBeVisible
                end
                if shouldBeVisible then
                    local dist = (playerRoot.Position - visuals.root.Position).Magnitude
                    visuals.esp.StudsOffset = Vector3.new(0, math.clamp(4 + (dist / 50), 4, 10), 0)
                    visuals.label.Text = string.format(
                        '%s\n<font color="#%s">%s</font>',
                        toTitleCase(visuals.brainrotName),
                        THEME.gold:ToHex(),
                        visuals.cachedMoneyPerSec
                    )
                end
            end
        end)
    end

    local function startBrainrotDataLoop()
        brainrotESP_connections.data = task.spawn(function()
            while brainrotESPEnabled do
                updateBrainrotInfo()
                cleanupInvalidVisuals()
                task.wait(BRAINROT_DATA_UPDATE_INTERVAL)
            end
        end)
    end

    local function stopBrainrotESP()
        brainrotESPEnabled = false
        for _, conn in pairs(brainrotESP_connections) do
            safeDisconnectConn(conn)
        end
        brainrotESP_connections = {}
        safeDisconnectConn(brainrotCharConn)
        brainrotCharConn = nil
        baseChannelCache = {}
        for target in pairs(activeBrainrotVisuals) do
            cleanupBrainrotVisuals(target)
        end
        mostExpensiveBrainrot = nil
    end

    local function startBrainrotESP()
        if next(brainrotESP_connections) then
            return
        end
        brainrotESPEnabled = true
        if buildDynamicDictionary() then
            myPlayerBase = getPlayerBase()
            initialBrainrotScan()
            safeDisconnectConn(brainrotCharConn)
            brainrotCharConn = player and player.CharacterAdded:Connect(function()
                task.wait(0.5)
                if brainrotESPEnabled then
                    myPlayerBase = getPlayerBase()
                    initialBrainrotScan()
                end
            end)
            brainrotESP_connections.added = Workspace.DescendantAdded:Connect(function(desc)
                handleStandAdded(desc)
            end)
            brainrotESP_connections.removed = Workspace.DescendantRemoving:Connect(function(desc)
                handleStandRemoving(desc)
                cleanupBrainrotVisualsForRemoved(desc)
            end)
            startBrainrotVisualLoop()
            startBrainrotDataLoop()
        else
            notify('ESP Error', 'Could not build Brainrot dictionary!', 5)
            if brainrotToggle and brainrotToggle.SetState then
                brainrotToggle:SetState(false)
            end
        end
    end

    local brainrotToggle = section:CreateToggle({
        Title = 'Brainrot ESP',
        Default = false,
        SaveKey = 'brainrot_esp_enabled',
        Callback = function(value)
            if value then
                startBrainrotESP()
            else
                stopBrainrotESP()
            end
        end,
    })

    local mostExpensiveToggle = section:CreateToggle({
        Title = 'Most Expensive Only',
        Default = false,
        SaveKey = 'most_expensive_only_enabled',
        Callback = function(value)
            mostExpensiveOnlyEnabled = value
        end,
    })

    return {
        start = startBrainrotESP,
        stop = stopBrainrotESP,
        brainrotToggle = brainrotToggle,
        mostExpensiveToggle = mostExpensiveToggle,
        setTheme = applyTheme,
    }
end

function BrainrotESP.setup(opts)
    singleton = createController(opts)
    BrainrotESP.controller = singleton
    return singleton
end

function BrainrotESP.new(opts)
    return BrainrotESP.setup(opts)
end

function BrainrotESP.start(opts)
    opts = opts or {}
    local autoStart = opts.autoStart
    if not singleton then
        singleton = createController(opts)
    else
        if opts.theme then
            singleton.setTheme(opts.theme)
        end
    end
    if typeof(opts.mostExpensiveOnly) == 'boolean' then
        BrainrotESP.setMostExpensiveOnly(opts.mostExpensiveOnly)
    end
    if singleton and singleton.start and autoStart ~= false then
        singleton.start()
    end
    BrainrotESP.controller = singleton
    return singleton
end

function BrainrotESP.stop()
    if singleton and singleton.stop then
        singleton.stop()
    end
end

function BrainrotESP.setTheme(theme)
    if singleton and singleton.setTheme then
        singleton.setTheme(theme)
    end
end

function BrainrotESP.setMostExpensiveOnly(state)
    if singleton and singleton.mostExpensiveToggle and singleton.mostExpensiveToggle.SetState then
        singleton.mostExpensiveToggle:SetState(state and true or false)
    end
end

local autoConfig = {}
pcall(function()
    local env = getgenv and getgenv()
    if type(env) == 'table' and type(env.StealaBrainrotESPConfig) == 'table' then
        for key, value in pairs(env.StealaBrainrotESPConfig) do
            autoConfig[key] = value
        end
    end
end)

if next(autoConfig) ~= nil and autoConfig.autoStart ~= false then
    BrainrotESP.controller = BrainrotESP.start(autoConfig)
end

return BrainrotESP

