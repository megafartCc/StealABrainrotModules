-- Anti-ragdoll module with start/stop controls.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local ragdollModule = nil
local ragdollRemote = nil

local BLOCKED_STATES = {
    [Enum.HumanoidStateType.Physics] = true,
    [Enum.HumanoidStateType.Ragdoll] = true,
    [Enum.HumanoidStateType.FallingDown] = true,
}

local function safeDisconnect(conn)
    if conn and typeof(conn) == "RBXScriptConnection" then
        conn:Disconnect()
    end
end

local AntiRagdoll = {
    enabled = false,
    character = player and player.Character or nil,
    humanoid = nil,
    stateConn = nil,
    charConn = nil,
    remoteConn = nil,
    heartbeatConn = nil,
    remoteRetry = nil,
    dampUntil = 0,
    trackedHumanoids = setmetatable({}, { __mode = "k" }),
    stateBackup = setmetatable({}, { __mode = "k" }),
}

function AntiRagdoll:loadRagdollAssets()
    if ragdollModule and ragdollRemote then
        return
    end
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if not packages then
        return
    end
    local ragdollScript = packages:FindFirstChild("Ragdoll") or packages:WaitForChild("Ragdoll", 5)
    if not ragdollScript then
        return
    end
    ragdollRemote = ragdollRemote or ragdollScript:FindFirstChild("Ragdoll") or ragdollScript:WaitForChild("Ragdoll", 5)
    if not ragdollModule then
        local ok, mod = pcall(require, ragdollScript)
        if ok and type(mod) == "table" then
            ragdollModule = mod
        end
    end
end

function AntiRagdoll:cleanRagdoll(char)
    if not (self.enabled and char) then
        return
    end

    local hum = self.humanoid or char:FindFirstChildOfClass("Humanoid")
    if hum then
        self.humanoid = hum
        hum.BreakJointsOnDeath = false

        if BLOCKED_STATES[hum:GetState()] and hum.Health > 0 then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end

        hum.PlatformStand = false
        hum.Sit = false
        hum.AutoRotate = true

        if player:GetAttribute("RagdollEndTime") ~= 0 then
            pcall(player.SetAttribute, player, "RagdollEndTime", 0)
        end

        local cam = Workspace.CurrentCamera
        if cam and cam.CameraSubject ~= hum then
            cam.CameraSubject = hum
        end
    end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.Anchored = false
        if self.dampUntil > os.clock() then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end

    self:loadRagdollAssets()
    if ragdollModule and type(ragdollModule.Unragdoll) == "function" then
        pcall(ragdollModule.Unragdoll, char)
    end

    for _, inst in ipairs(char:GetDescendants()) do
        if inst:IsA("Motor6D") and inst.Enabled == false then
            inst.Enabled = true
        elseif inst:IsA("BallSocketConstraint") or inst:IsA("HingeConstraint") then
            pcall(inst.Destroy, inst)
        elseif inst:IsA("NoCollisionConstraint") then
            local p0 = inst.Part0
            local p1 = inst.Part1
            if (p0 and p0:IsDescendantOf(char)) or (p1 and p1:IsDescendantOf(char)) then
                pcall(inst.Destroy, inst)
            end
        elseif inst:IsA("Attachment") then
            local parent = inst.Parent
            if parent and parent:IsA("BasePart") then
                local hasConstraint = parent:FindFirstChildWhichIsA("BallSocketConstraint")
                    or parent:FindFirstChildWhichIsA("HingeConstraint")
                local hasDisabledMotor = false
                for _, child in ipairs(parent:GetChildren()) do
                    if child:IsA("Motor6D") and child.Enabled == false then
                        hasDisabledMotor = true
                        break
                    end
                end
                if hasConstraint or hasDisabledMotor then
                    pcall(inst.Destroy, inst)
                end
            end
        end
    end
end

function AntiRagdoll:bindHumanoid(hum)
    if not hum then
        return
    end
    self.trackedHumanoids[hum] = true
    self.stateBackup[hum] = self.stateBackup[hum] or {}
    for state in pairs(BLOCKED_STATES) do
        if self.stateBackup[hum][state] == nil then
            self.stateBackup[hum][state] = hum:GetStateEnabled(state)
        end
        pcall(hum.SetStateEnabled, hum, state, false)
    end

    safeDisconnect(self.stateConn)
    self.stateConn = hum.StateChanged:Connect(function(_, newState)
        if not self.enabled then
            return
        end
        if BLOCKED_STATES[newState] then
            self.dampUntil = os.clock() + 0.35
            self:cleanRagdoll(self.character)
        end
    end)
end

function AntiRagdoll:bindCharacter(char)
    self.character = char
    self.humanoid = char and char:WaitForChild("Humanoid", 5) or nil
    if not self.humanoid then
        return
    end
    self:bindHumanoid(self.humanoid)
    self:cleanRagdoll(char)
end

function AntiRagdoll:connectRemote()
    if self.remoteConn then
        return
    end
    self:loadRagdollAssets()
    if not ragdollRemote then
        return
    end
    self.remoteConn = ragdollRemote.OnClientEvent:Connect(function()
        if not self.enabled then
            return
        end
        self.dampUntil = os.clock() + 0.35
        self:cleanRagdoll(self.character)
    end)
end

function AntiRagdoll:start()
    if self.enabled then
        return
    end
    self.enabled = true
    self:loadRagdollAssets()

    if self.character then
        self:bindCharacter(self.character)
    elseif player and player.Character then
        self:bindCharacter(player.Character)
    end

    safeDisconnect(self.charConn)
    self.charConn = player.CharacterAdded:Connect(function(newChar)
        if not self.enabled then
            return
        end
        self:bindCharacter(newChar)
    end)

    self:connectRemote()
    if not self.remoteConn then
        self.remoteRetry = task.spawn(function()
            while self.enabled and not self.remoteConn do
                task.wait(1)
                self:connectRemote()
            end
        end)
    end

    safeDisconnect(self.heartbeatConn)
    self.heartbeatConn = RunService.Heartbeat:Connect(function()
        if not self.enabled then
            return
        end
        if self.character and self.character.Parent then
            self:cleanRagdoll(self.character)
        end
    end)
end

function AntiRagdoll:stop()
    if not self.enabled then
        return
    end
    self.enabled = false
    safeDisconnect(self.stateConn)
    safeDisconnect(self.remoteConn)
    safeDisconnect(self.charConn)
    safeDisconnect(self.heartbeatConn)
    if self.remoteRetry and coroutine.status(self.remoteRetry) ~= "dead" then
        task.cancel(self.remoteRetry)
    end
    self.stateConn = nil
    self.remoteConn = nil
    self.charConn = nil
    self.heartbeatConn = nil
    self.remoteRetry = nil

    for hum in pairs(self.trackedHumanoids) do
        if hum and hum.Parent then
            local saved = self.stateBackup[hum]
            if saved then
                for state, enabled in pairs(saved) do
                    pcall(hum.SetStateEnabled, hum, state, enabled)
                end
            else
                for state in pairs(BLOCKED_STATES) do
                    pcall(hum.SetStateEnabled, hum, state, true)
                end
            end
            hum.PlatformStand = false
            hum.Sit = false
            hum.AutoRotate = true
        end
    end

    self.trackedHumanoids = setmetatable({}, { __mode = "k" })
    self.stateBackup = setmetatable({}, { __mode = "k" })
    self.dampUntil = 0
end

return AntiRagdoll
