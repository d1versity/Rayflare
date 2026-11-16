-- Rayflare by Vhyse | v3.2

local Rayflare = {
    Settings = {
        Enabled = false,
        AimPart = "Head", 
        AimType = "Camera",
        Smoothness = 5, 
        TargetLock = true, 
        
        Trigger = {
            TriggerKey = Enum.UserInputType.MouseButton2, 
            TriggerMode = "Hold", 
            IsAiming = false 
        },
        
        TriggerBot = {
            Enabled = false,
            Mode = "Camera",
            TriggerKey = Enum.UserInputType.MouseButton2,
            TriggerMode = "Hold",
            IsAiming = false,
            Delay = 0,
            TeamCheck = { Enabled = false },
            WallCheck = { Enabled = false }
        },
        
        SilentAim = {
            Enabled = true,
            HitChance = 100
        },

        FOV = {
            Visible = true,
            Radius = 150,
            Color = Color3.fromRGB(255, 255, 255),
            Chroma = false
        },
        
        TeamCheck = { Enabled = true },
        WallCheck = { Enabled = false },
        
        Prediction = {
            Enabled = false,
            X = 0.1,
            Y = 0.1,
            Dynamic = false
        },
        
        Flick = { Enabled = false }
    },
    
    Connections = {},
    CurrentTarget = nil,
    FOVCircle = nil,
    RayParams = RaycastParams.new(),
    
    wasAiming = false,
    savedCameraCFrame = nil,
    hooksLoaded = false
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local PlayerMouse = LocalPlayer:GetMouse() -- Defined OUTSIDE the hook to prevent crashes

if Drawing then
    Rayflare.FOVCircle = Drawing.new("Circle")
    Rayflare.FOVCircle.Thickness = 1.5
    Rayflare.FOVCircle.Filled = false
    Rayflare.FOVCircle.Transparency = 0
    Rayflare.FOVCircle.Visible = false
    Rayflare.FOVCircle.Radius = 0
    Rayflare.FOVCircle.Position = Vector2.new(-9999, -9999) 
end

Rayflare.RayParams.FilterType = Enum.RaycastFilterType.Exclude
Rayflare.RayParams.IgnoreWater = true
local sharedIgnoreList = {}

local function SimulateClick()
    task.spawn(function()
        if mouse1press and mouse1release then
            mouse1press() task.wait(0.03) mouse1release()
        elseif mouse1click then
            mouse1click()
        else
            pcall(function()
                local center = Camera.ViewportSize / 2
                VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
                task.wait(0.03)
                VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
            end)
        end
    end)
end

local function CheckVisibility(targetPart, character)
    if not Rayflare.Settings.WallCheck.Enabled then return true end
    if not LocalPlayer.Character then return false end
    
    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin
    
    table.clear(sharedIgnoreList)
    sharedIgnoreList[1] = LocalPlayer.Character
    sharedIgnoreList[2] = character
    
    Rayflare.RayParams.FilterDescendantsInstances = sharedIgnoreList
    local result = Workspace:Raycast(origin, direction, Rayflare.RayParams)
    
    local safety = 0
    while result and not result.Instance.CanCollide and safety < 10 do
        safety = safety + 1
        table.insert(sharedIgnoreList, result.Instance)
        Rayflare.RayParams.FilterDescendantsInstances = sharedIgnoreList
        result = Workspace:Raycast(origin, direction, Rayflare.RayParams)
    end
    return not result
end

local function GetAimOrigin()
    -- Perfectly centers FOV and targeting based on your aim type
    if Rayflare.Settings.AimType == "Camera" then
        return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    else
        return UserInputService:GetMouseLocation()
    end
end

local function IsValidTarget(player, aimOrigin)
    if not player or player == LocalPlayer or not player.Character then return false end
    
    local targetPart = player.Character:FindFirstChild(Rayflare.Settings.AimPart)
    local humanoid = player.Character:FindFirstChild("Humanoid")
    if not targetPart or not humanoid or humanoid.Health <= 0 then return false end
    if Rayflare.Settings.TeamCheck.Enabled and LocalPlayer.Team and player.Team == LocalPlayer.Team then return false end
    
    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
    if not onScreen then return false end
    
    local dist = (Vector2.new(screenPos.X, screenPos.Y) - aimOrigin).Magnitude
    if dist > Rayflare.Settings.FOV.Radius then return false end
    
    return true, dist, targetPart
end

local function GetClosestTarget(aimOrigin)
    local closestPlayer = nil
    local shortestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local isValid, dist = IsValidTarget(player, aimOrigin)
        if isValid and dist < shortestDistance then
            shortestDistance = dist
            closestPlayer = player
        end
    end
    
    if closestPlayer and closestPlayer.Character then
        local targetPart = closestPlayer.Character:FindFirstChild(Rayflare.Settings.AimPart)
        if targetPart and CheckVisibility(targetPart, closestPlayer.Character) then
            return closestPlayer
        end
    end
    return nil
end

local function GetPredictedPosition(targetPart)
    local pos = targetPart.Position
    if Rayflare.Settings.Prediction.Enabled then
        local velocity = targetPart.AssemblyLinearVelocity or Vector3.zero
        local predX, predY = Rayflare.Settings.Prediction.X, Rayflare.Settings.Prediction.Y
        
        if Rayflare.Settings.Prediction.Dynamic then
            local speed = velocity.Magnitude
            local dynamicFactor = math.clamp(speed / 150, 0.05, 0.5)
            predX, predY = dynamicFactor, dynamicFactor
        end
        pos = pos + Vector3.new(velocity.X * predX, velocity.Y * predY, velocity.Z * predX)
    end
    return pos
end

local lastTrigger = 0
local function CheckTriggerBot(aimOrigin)
    if not Rayflare.Settings.TriggerBot.Enabled then return end
    
    local shouldAim = (Rayflare.Settings.TriggerBot.TriggerMode == "Always") or Rayflare.Settings.TriggerBot.IsAiming
    if not shouldAim then return end
    
    local origin, direction
    if Rayflare.Settings.TriggerBot.Mode == "Camera" then
        local ray = Camera:ViewportPointToRay(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        origin, direction = ray.Origin, ray.Direction * 1000
    elseif Rayflare.Settings.TriggerBot.Mode == "Cursor" then
        local ray = Camera:ScreenPointToRay(aimOrigin.X, aimOrigin.Y)
        origin, direction = ray.Origin, ray.Direction * 1000
    else return end

    table.clear(sharedIgnoreList)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then table.insert(sharedIgnoreList, player.Character) end
    end
    
    local triggerRayParams = RaycastParams.new()
    triggerRayParams.IgnoreWater = true
    triggerRayParams.FilterType = Enum.RaycastFilterType.Include
    triggerRayParams.FilterDescendantsInstances = sharedIgnoreList

    local result = Workspace:Raycast(origin, direction, triggerRayParams)
    if result and result.Instance then
        local targetCharacter = result.Instance:FindFirstAncestorOfClass("Model")
        if targetCharacter then
            local player = Players:GetPlayerFromCharacter(targetCharacter)
            if player and player ~= LocalPlayer then
                if Rayflare.Settings.TriggerBot.TeamCheck.Enabled and LocalPlayer.Team and player.Team == LocalPlayer.Team then return end
                local humanoid = targetCharacter:FindFirstChild("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    local isVisible = Rayflare.Settings.TriggerBot.WallCheck.Enabled and CheckVisibility(result.Instance, targetCharacter) or true
                    if isVisible and (tick() - lastTrigger >= Rayflare.Settings.TriggerBot.Delay) then
                        lastTrigger = tick()
                        SimulateClick()
                    end
                end
            end
        end
    end
end

-- ==========================================
-- OPTIMIZED SILENT AIM HOOKS
-- ==========================================
local oldNamecall
local oldIndex

local function InitHooks()
    if Rayflare.hooksLoaded then return end
    if not hookmetamethod then return warn("[ Rayflare ] Executor does not support hookmetamethod.") end

    -- NAMECALL HOOK
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        
        -- Prevent hooking our own scripts and only check relevant methods to stop lag
        if not checkcaller() and Rayflare.Settings.Enabled and Rayflare.Settings.SilentAim.Enabled and Rayflare.CurrentTarget then
            if method == "Raycast" or method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
                
                local shouldAim = (Rayflare.Settings.Trigger.TriggerMode == "Always") or Rayflare.Settings.Trigger.IsAiming
                
                if shouldAim and math.random(1, 100) <= Rayflare.Settings.SilentAim.HitChance then
                    local targetPart = Rayflare.CurrentTarget.Character and Rayflare.CurrentTarget.Character:FindFirstChild(Rayflare.Settings.AimPart)
                    
                    if targetPart then
                        local predictedPos = GetPredictedPosition(targetPart)
                        local args = {...}

                        if method == "Raycast" and self == Workspace then
                            local origin = args[1]
                            args[2] = (predictedPos - origin).Unit * args[2].Magnitude
                            return oldNamecall(self, unpack(args))
                        elseif self == Workspace then
                            local origin = args[1].Origin
                            args[1] = Ray.new(origin, (predictedPos - origin).Unit * args[1].Direction.Magnitude)
                            return oldNamecall(self, unpack(args))
                        end
                    end
                end
            end
        end
        return oldNamecall(self, ...)
    end))

    -- INDEX HOOK (CRASH FIXED)
    oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
        if not checkcaller() and Rayflare.Settings.Enabled and Rayflare.Settings.SilentAim.Enabled and Rayflare.CurrentTarget then
            local shouldAim = (Rayflare.Settings.Trigger.TriggerMode == "Always") or Rayflare.Settings.Trigger.IsAiming
            
            if shouldAim and self == PlayerMouse then
                -- Only do calculations if the game specifically asks for Hit or Target
                if key == "Target" or key == "Hit" then
                    if math.random(1, 100) <= Rayflare.Settings.SilentAim.HitChance then
                        local targetPart = Rayflare.CurrentTarget.Character and Rayflare.CurrentTarget.Character:FindFirstChild(Rayflare.Settings.AimPart)
                        if targetPart then
                            if key == "Target" then
                                return targetPart
                            elseif key == "Hit" then
                                return CFrame.new(GetPredictedPosition(targetPart))
                            end
                        end
                    end
                end
            end
        end
        return oldIndex(self, key)
    end))

    Rayflare.hooksLoaded = true
end

function Rayflare:Load()
    if self.Connections.RenderLoop then return end 
    InitHooks()
    
    self.Connections.InputBegan = UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        local isAimKey = (input.UserInputType == self.Settings.Trigger.TriggerKey) or (input.KeyCode == self.Settings.Trigger.TriggerKey)
        if isAimKey and self.Settings.Enabled then
            self.Settings.Trigger.IsAiming = (self.Settings.Trigger.TriggerMode == "Toggle") and not self.Settings.Trigger.IsAiming or true
        end
        
        local isTbKey = (input.UserInputType == self.Settings.TriggerBot.TriggerKey) or (input.KeyCode == self.Settings.TriggerBot.TriggerKey)
        if isTbKey and self.Settings.TriggerBot.Enabled then
            self.Settings.TriggerBot.IsAiming = (self.Settings.TriggerBot.TriggerMode == "Toggle") and not self.Settings.TriggerBot.IsAiming or true
        end
    end)

    self.Connections.InputEnded = UserInputService.InputEnded:Connect(function(input)
        local isAimKey = (input.UserInputType == self.Settings.Trigger.TriggerKey) or (input.KeyCode == self.Settings.Trigger.TriggerKey)
        if isAimKey and self.Settings.Trigger.TriggerMode == "Hold" then self.Settings.Trigger.IsAiming = false end
        
        local isTbKey = (input.UserInputType == self.Settings.TriggerBot.TriggerKey) or (input.KeyCode == self.Settings.TriggerBot.TriggerKey)
        if isTbKey and self.Settings.TriggerBot.TriggerMode == "Hold" then self.Settings.TriggerBot.IsAiming = false end
    end)

    self.Connections.RenderLoop = RunService.RenderStepped:Connect(function()
        local aimOrigin = GetAimOrigin()

        if self.FOVCircle then
            if self.Settings.Enabled and self.Settings.FOV.Visible then
                self.FOVCircle.Visible = true
                self.FOVCircle.Transparency = 1
                self.FOVCircle.Radius = self.Settings.FOV.Radius
                self.FOVCircle.Position = aimOrigin
                self.FOVCircle.Color = self.Settings.FOV.Chroma and Color3.fromHSV(os.clock() % 5 / 5, 1, 1) or self.Settings.FOV.Color
            else
                self.FOVCircle.Visible = false
                self.FOVCircle.Position = Vector2.new(-9999, -9999) 
            end
        end

        CheckTriggerBot(aimOrigin)

        if not self.Settings.Enabled then 
            self.CurrentTarget = nil self.wasAiming = false self.savedCameraCFrame = nil
            return 
        end

        local shouldAim = (self.Settings.Trigger.TriggerMode == "Always") or self.Settings.Trigger.IsAiming
        
        if not shouldAim then
            if self.wasAiming then
                if self.Settings.Flick.Enabled and self.savedCameraCFrame and self.Settings.AimType == "Camera" and not self.Settings.SilentAim.Enabled then
                    Camera.CFrame = self.savedCameraCFrame
                end
                self.wasAiming = false self.savedCameraCFrame = nil
            end
            self.CurrentTarget = nil
            return
        end

        if self.Settings.TargetLock and self.CurrentTarget then
            local isValid = IsValidTarget(self.CurrentTarget, aimOrigin)
            local targetPart = self.CurrentTarget.Character and self.CurrentTarget.Character:FindFirstChild(self.Settings.AimPart)
            if not targetPart or not isValid or not CheckVisibility(targetPart, self.CurrentTarget.Character) then
                self.CurrentTarget = GetClosestTarget(aimOrigin)
            end
        else
            self.CurrentTarget = GetClosestTarget(aimOrigin)
        end
        
        if self.CurrentTarget and self.CurrentTarget.Character then
            if not self.wasAiming then self.savedCameraCFrame = Camera.CFrame self.wasAiming = true end
            
            local targetPart = self.CurrentTarget.Character:FindFirstChild(self.Settings.AimPart)
            if not targetPart then return end
            
            if self.Settings.SilentAim.Enabled then return end -- Silent Aim handles its own math in hooks

            local predictedPos = GetPredictedPosition(targetPart)
            
            if self.Settings.AimType == "Camera" then
                local currentCFrame = Camera.CFrame
                local targetCFrame = CFrame.new(currentCFrame.Position, predictedPos)
                Camera.CFrame = self.Settings.Smoothness <= 0 and targetCFrame or currentCFrame:Lerp(targetCFrame, math.clamp(1 / (self.Settings.Smoothness + 1), 0.01, 1))
                
            elseif self.Settings.AimType == "Cursor" then
                if mousemoverel then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(predictedPos)
                    if onScreen then
                        local mousePos = UserInputService:GetMouseLocation()
                        local deltaX, deltaY = screenPos.X - mousePos.X, screenPos.Y - mousePos.Y
                        
                        if self.Settings.Smoothness <= 0 then
                            mousemoverel(deltaX, deltaY)
                        else
                            local moveX, moveY = deltaX / self.Settings.Smoothness, deltaY / self.Settings.Smoothness
                            if math.abs(deltaX) > 0 and math.abs(deltaX) <= self.Settings.Smoothness then moveX = deltaX end
                            if math.abs(deltaY) > 0 and math.abs(deltaY) <= self.Settings.Smoothness then moveY = deltaY end
                            mousemoverel(moveX, moveY)
                        end
                    end
                end
            end
        else
            if self.wasAiming then
                if self.Settings.Flick.Enabled and self.savedCameraCFrame and self.Settings.AimType == "Camera" and not self.Settings.SilentAim.Enabled then
                    Camera.CFrame = self.savedCameraCFrame
                end
                self.wasAiming = false self.savedCameraCFrame = nil
            end
        end
    end)
    print("[ Rayflare ] Engine loaded successfully.")
end

function Rayflare:Unload()
    for _, connection in pairs(self.Connections) do
        if typeof(connection) == "RBXScriptConnection" and connection.Connected then connection:Disconnect() end
    end
    self.Connections = {}
    if self.FOVCircle then self.FOVCircle:Remove() self.FOVCircle = nil end
    self.CurrentTarget = nil self.wasAiming = false self.savedCameraCFrame = nil
    self.Settings.Trigger.IsAiming = false self.Settings.TriggerBot.IsAiming = false
    print("[ Rayflare ] Engine unloaded.")
end

return Rayflare
