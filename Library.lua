-- Rayflare by Vhyse | v2.8

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
            TeamCheck = {
                Enabled = false
            },
            WallCheck = {
                Enabled = false
            }
        },

        FOV = {
            Visible = true,
            Radius = 150,
            Color = Color3.fromRGB(255, 255, 255),
            Chroma = false,
            Full360 = false -- 360 Degree FOV Switch
        },
        
        TeamCheck = {
            Enabled = true
        },
        
        WallCheck = {
            Enabled = false
        },
        
        AutoWall = {
            Enabled = false,
            MaxThickness = 2 
        },
        
        Prediction = {
            Enabled = false,
            X = 0.1,
            Y = 0.1,
            Dynamic = false
        },
        
        Flick = {
            Enabled = false
        }
    },
    
    Connections = {},
    CurrentTarget = nil,
    FOVCircle = nil,
    RayParams = RaycastParams.new(),
    RevRayParams = RaycastParams.new(),
    
    wasAiming = false,
    savedCameraCFrame = nil
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

if Drawing then
    Rayflare.FOVCircle = Drawing.new("Circle")
    Rayflare.FOVCircle.Thickness = 1.5
    Rayflare.FOVCircle.Filled = false
    Rayflare.FOVCircle.Transparency = 0
    Rayflare.FOVCircle.Visible = false
    Rayflare.FOVCircle.Radius = 0
    Rayflare.FOVCircle.Position = Vector2.new(-9999, -9999) 
else
    warn("[ Rayflare ] Executor does not support Drawing API. FOV Circle will not render.")
end

Rayflare.RayParams.FilterType = Enum.RaycastFilterType.Exclude
Rayflare.RayParams.IgnoreWater = true

Rayflare.RevRayParams.FilterType = Enum.RaycastFilterType.Exclude
Rayflare.RevRayParams.IgnoreWater = true

-- Reusable buffer table to avoid GC overhead
local sharedIgnoreList = {}

local function CheckVisibility(targetPart, character)
    if not Rayflare.Settings.WallCheck.Enabled then return true end
    if not LocalPlayer.Character then return false end
    
    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin
    
    -- Fast buffer clear
    table.clear(sharedIgnoreList)
    sharedIgnoreList[1] = LocalPlayer.Character
    sharedIgnoreList[2] = character
    
    Rayflare.RayParams.FilterDescendantsInstances = sharedIgnoreList
    local result = Workspace:Raycast(origin, direction, Rayflare.RayParams)
    
    -- Filter non-collidable parts quickly
    local safety = 0
    while result and not result.Instance.CanCollide and safety < 10 do
        safety = safety + 1
        table.insert(sharedIgnoreList, result.Instance)
        Rayflare.RayParams.FilterDescendantsInstances = sharedIgnoreList
        result = Workspace:Raycast(origin, direction, Rayflare.RayParams)
    end
    
    -- Front ray hit a solid wall
    if result then
        if Rayflare.Settings.AutoWall and Rayflare.Settings.AutoWall.Enabled then
            local maxThick = Rayflare.Settings.AutoWall.MaxThickness
            local dirUnit = direction.Unit
            
            -- Early exit test: sample max penetration depth ahead of the front hit
            local samplePos = result.Position + (dirUnit * (maxThick + 0.05))
            local distToTarget = (targetPart.Position - result.Position).Magnitude
            
            -- If the target is closer than the wall penetration sample, target is inside the wall
            if distToTarget < maxThick then
                samplePos = targetPart.Position
            end
            
            -- Cast backwards from sample point toward the front hit
            Rayflare.RevRayParams.FilterDescendantsInstances = sharedIgnoreList
            local revDir = result.Position - samplePos
            local revResult = Workspace:Raycast(samplePos, revDir, Rayflare.RevRayParams)
            
            local revSafety = 0
            while revResult and not revResult.Instance.CanCollide and revSafety < 10 do
                revSafety = revSafety + 1
                table.insert(sharedIgnoreList, revResult.Instance)
                Rayflare.RevRayParams.FilterDescendantsInstances = sharedIgnoreList
                revResult = Workspace:Raycast(samplePos, revDir, Rayflare.RevRayParams)
            end
            
            if revResult then
                local thickness = (result.Position - revResult.Position).Magnitude
                if thickness <= maxThick then
                    return true
                end
            end
        end
        return false
    end
    
    return true
end

local function IsValidTarget(player, mousePos)
    if not player or player == LocalPlayer or not player.Character then return false end
    
    local targetPart = player.Character:FindFirstChild(Rayflare.Settings.AimPart)
    local humanoid = player.Character:FindFirstChild("Humanoid")
    
    if not targetPart or not humanoid or humanoid.Health <= 0 then return false end
    
    if Rayflare.Settings.TeamCheck.Enabled and LocalPlayer.Team and player.Team == LocalPlayer.Team then 
        return false 
    end
    
    -- 360 Degree FOV Evaluation
    if Rayflare.Settings.FOV.Full360 then
        -- In 360 FOV, calculate direct world distance from the camera
        local dist3D = (targetPart.Position - Camera.CFrame.Position).Magnitude
        return true, dist3D, targetPart
    end
    
    -- Standard 2D Viewport Evaluation
    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
    if not onScreen then return false end
    
    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
    if dist > Rayflare.Settings.FOV.Radius then return false end
    
    return true, dist, targetPart
end

local function GetClosestTarget(mousePos)
    local closestPlayer = nil
    local shortestDistance = math.huge

    -- 1. Cheap loop: Find candidate by distance only
    for _, player in ipairs(Players:GetPlayers()) do
        local isValid, dist = IsValidTarget(player, mousePos)
        if isValid and dist < shortestDistance then
            shortestDistance = dist
            closestPlayer = player
        end
    end
    
    -- 2. Expensive check: Only raycast against the single closest candidate
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
            local dynamicFactor = speed / 150 
            predX = math.clamp(dynamicFactor, 0.05, 0.5)
            predY = math.clamp(dynamicFactor, 0.05, 0.5)
        end
        
        pos = pos + Vector3.new(velocity.X * predX, velocity.Y * predY, velocity.Z * predX)
    end
    
    return pos
end

local lastTrigger = 0
local function CheckTriggerBot(mousePos)
    if not Rayflare.Settings.TriggerBot.Enabled then return end
    
    local shouldAim = (Rayflare.Settings.TriggerBot.TriggerMode == "Always") or Rayflare.Settings.TriggerBot.IsAiming
    if not shouldAim then return end
    
    local origin, direction
    if Rayflare.Settings.TriggerBot.Mode == "Camera" then
        local viewportSize = Camera.ViewportSize
        local ray = Camera:ViewportPointToRay(viewportSize.X / 2, viewportSize.Y / 2)
        origin = ray.Origin
        direction = ray.Direction * 1000
    elseif Rayflare.Settings.TriggerBot.Mode == "Cursor" then
        local ray = Camera:ScreenPointToRay(mousePos.X, mousePos.Y)
        origin = ray.Origin
        direction = ray.Direction * 1000
    else
        return
    end

    table.clear(sharedIgnoreList)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            table.insert(sharedIgnoreList, player.Character)
        end
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
                
                if Rayflare.Settings.TriggerBot.TeamCheck.Enabled and LocalPlayer.Team and player.Team == LocalPlayer.Team then
                    return
                end

                local humanoid = targetCharacter:FindFirstChild("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    local isVisible = true
                    if Rayflare.Settings.TriggerBot.WallCheck.Enabled then
                        isVisible = CheckVisibility(result.Instance, targetCharacter)
                    end
                    
                    if isVisible then
                        if tick() - lastTrigger >= Rayflare.Settings.TriggerBot.Delay then
                            lastTrigger = tick()
                            if mouse1press then pcall(mouse1press) end
                            if mouse1release then pcall(mouse1release) end
                            if mouse1click then pcall(mouse1click) end
                        end
                    end
                end
            end
        end
    end
end

function Rayflare:Load()
    if self.Connections.RenderLoop then return end 
    
    self.Connections.InputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        local isAimKey = (input.UserInputType == self.Settings.Trigger.TriggerKey) or (input.KeyCode == self.Settings.Trigger.TriggerKey)
        if isAimKey and self.Settings.Enabled then
            if self.Settings.Trigger.TriggerMode == "Toggle" then
                self.Settings.Trigger.IsAiming = not self.Settings.Trigger.IsAiming
            elseif self.Settings.Trigger.TriggerMode == "Hold" then
                self.Settings.Trigger.IsAiming = true
            end
        end
        
        local isTriggerBotKey = (input.UserInputType == self.Settings.TriggerBot.TriggerKey) or (input.KeyCode == self.Settings.TriggerBot.TriggerKey)
        if isTriggerBotKey and self.Settings.TriggerBot.Enabled then
            if self.Settings.TriggerBot.TriggerMode == "Toggle" then
                self.Settings.TriggerBot.IsAiming = not self.Settings.TriggerBot.IsAiming
            elseif self.Settings.TriggerBot.TriggerMode == "Hold" then
                self.Settings.TriggerBot.IsAiming = true
            end
        end
    end)

    self.Connections.InputEnded = UserInputService.InputEnded:Connect(function(input)
        local isAimKey = (input.UserInputType == self.Settings.Trigger.TriggerKey) or (input.KeyCode == self.Settings.Trigger.TriggerKey)
        if isAimKey then
            if self.Settings.Trigger.TriggerMode == "Hold" then
                self.Settings.Trigger.IsAiming = false
            end
        end
        
        local isTriggerBotKey = (input.UserInputType == self.Settings.TriggerBot.TriggerKey) or (input.KeyCode == self.Settings.TriggerBot.TriggerKey)
        if isTriggerBotKey then
            if self.Settings.TriggerBot.TriggerMode == "Hold" then
                self.Settings.TriggerBot.IsAiming = false
            end
        end
    end)

    self.Connections.RenderLoop = RunService.RenderStepped:Connect(function(deltaTime)
        local mousePos = UserInputService:GetMouseLocation()

        -- Hide circle if 360 FOV is active
        if self.FOVCircle then
            if self.Settings.Enabled and self.Settings.FOV.Visible and not self.Settings.FOV.Full360 then
                self.FOVCircle.Visible = true
                self.FOVCircle.Transparency = 1
                self.FOVCircle.Radius = self.Settings.FOV.Radius
                self.FOVCircle.Position = mousePos
                
                if self.Settings.FOV.Chroma then
                    self.FOVCircle.Color = Color3.fromHSV(os.clock() % 5 / 5, 1, 1)
                else
                    self.FOVCircle.Color = self.Settings.FOV.Color
                end
            else
                self.FOVCircle.Visible = false
                self.FOVCircle.Radius = 0
                self.FOVCircle.Transparency = 0
                self.FOVCircle.Position = Vector2.new(-9999, -9999) 
            end
        end

        CheckTriggerBot(mousePos)

        if not self.Settings.Enabled then 
            self.CurrentTarget = nil
            self.Settings.Trigger.IsAiming = false
            self.wasAiming = false
            self.savedCameraCFrame = nil
            return 
        end

        local shouldAim = (self.Settings.Trigger.TriggerMode == "Always") or self.Settings.Trigger.IsAiming
        
        if not shouldAim then
            if self.wasAiming then
                if self.Settings.Flick.Enabled and self.savedCameraCFrame and self.Settings.AimType == "Camera" then
                    Camera.CFrame = self.savedCameraCFrame
                end
                self.wasAiming = false
                self.savedCameraCFrame = nil
            end
            
            self.CurrentTarget = nil
            return
        end

        if self.Settings.TargetLock and self.CurrentTarget then
            local isValid = IsValidTarget(self.CurrentTarget, mousePos)
            local targetPart = self.CurrentTarget.Character and self.CurrentTarget.Character:FindFirstChild(self.Settings.AimPart)
            if not isValid or not (targetPart and CheckVisibility(targetPart, self.CurrentTarget.Character)) then
                self.CurrentTarget = GetClosestTarget(mousePos)
            end
        else
            self.CurrentTarget = GetClosestTarget(mousePos)
        end
        
        if self.CurrentTarget and self.CurrentTarget.Character then
            if not self.wasAiming then
                self.savedCameraCFrame = Camera.CFrame
                self.wasAiming = true
            end
            
            local targetPart = self.CurrentTarget.Character:FindFirstChild(self.Settings.AimPart)
            if not targetPart then return end
            
            local predictedPos = GetPredictedPosition(targetPart)
            
            if self.Settings.AimType == "Camera" then
                local currentCFrame = Camera.CFrame
                local targetCFrame = CFrame.new(currentCFrame.Position, predictedPos)
                
                if self.Settings.Smoothness <= 0 then
                    Camera.CFrame = targetCFrame
                else
                    local alpha = math.clamp(1 / (self.Settings.Smoothness + 1), 0.01, 1)
                    Camera.CFrame = currentCFrame:Lerp(targetCFrame, alpha)
                end
                
            elseif self.Settings.AimType == "Cursor" then
                if mousemoverel then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(predictedPos)
                    if onScreen then
                        local deltaX = screenPos.X - mousePos.X
                        local deltaY = screenPos.Y - mousePos.Y
                        
                        if self.Settings.Smoothness <= 0 then
                            mousemoverel(deltaX, deltaY)
                        else
                            local smoothFactor = self.Settings.Smoothness
                            local moveX = deltaX / smoothFactor
                            local moveY = deltaY / smoothFactor
                            
                            if math.abs(deltaX) > 0 and math.abs(deltaX) <= smoothFactor then moveX = deltaX end
                            if math.abs(deltaY) > 0 and math.abs(deltaY) <= smoothFactor then moveY = deltaY end
                            
                            mousemoverel(moveX, moveY)
                        end
                    end
                else
                    warn("[ Rayflare ] 'mousemoverel' is not supported by your executor. Cursor aim will not work.")
                    self.Settings.AimType = "Camera" 
                end
            end
        else
            if self.wasAiming then
                if self.Settings.Flick.Enabled and self.savedCameraCFrame and self.Settings.AimType == "Camera" then
                    Camera.CFrame = self.savedCameraCFrame
                end
                self.wasAiming = false
                self.savedCameraCFrame = nil
            end
        end
    end)
    
    print("[ Rayflare ] Engine loaded successfully.")
end

function Rayflare:Unload()
    for name, connection in pairs(self.Connections) do
        if typeof(connection) == "RBXScriptConnection" and connection.Connected then
            connection:Disconnect()
        end
    end
    self.Connections = {}
    
    if self.FOVCircle then
        self.FOVCircle:Remove()
        self.FOVCircle = nil
    end
    
    self.CurrentTarget = nil
    self.wasAiming = false
    self.savedCameraCFrame = nil
    self.Settings.Trigger.IsAiming = false
    self.Settings.TriggerBot.IsAiming = false
    print("[ Rayflare ] Engine unloaded and memory cleared.")
end

return Rayflare
