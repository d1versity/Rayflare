-- Rayflare by Vhyse | v2.4

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
            WallCheck = {
                Enabled = true
            }
        },

        FOV = {
            Visible = true,
            Radius = 150,
            Color = Color3.fromRGB(255, 255, 255),
            Chroma = false
        },
        
        TeamCheck = {
            Enabled = true
        },
        
        WallCheck = {
            Enabled = false
        },
        
        Prediction = {
            Enabled = false,
            X = 0.1,
            Y = 0.1,
            Dynamic = false
        }
    },
    
    Connections = {},
    CurrentTarget = nil,
    FOVCircle = nil,
    RayParams = RaycastParams.new()
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

local function IsTeamIgnored(player)
    if not Rayflare.Settings.TeamCheck.Enabled then return false end
    if not LocalPlayer.Team then return false end
    return player.Team == LocalPlayer.Team
end

local function CheckVisibility(targetPart, character)
    if not Rayflare.Settings.WallCheck.Enabled then return true end
    if not LocalPlayer.Character then return false end
    
    local origin = Camera.CFrame.Position
    Rayflare.RayParams.FilterDescendantsInstances = {LocalPlayer.Character, character}
    
    local result = Workspace:Raycast(origin, targetPart.Position - origin, Rayflare.RayParams)
    return not result
end

local function IsValidTarget(player, mousePos)
    if not player or player == LocalPlayer or not player.Character then return false end
    
    local targetPart = player.Character:FindFirstChild(Rayflare.Settings.AimPart)
    local humanoid = player.Character:FindFirstChild("Humanoid")
    
    if not targetPart or not humanoid or humanoid.Health <= 0 then return false end
    if IsTeamIgnored(player) then return false end
    
    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
    if not onScreen then return false end
    
    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
    if dist > Rayflare.Settings.FOV.Radius then return false end
    
    if not CheckVisibility(targetPart, player.Character) then return false end
    
    return true, dist, targetPart
end

local function GetClosestTarget(mousePos)
    local closestPlayer = nil
    local shortestDistance = Rayflare.Settings.FOV.Radius

    for _, player in ipairs(Players:GetPlayers()) do
        local isValid, dist = IsValidTarget(player, mousePos)
        if isValid and dist < shortestDistance then
            shortestDistance = dist
            closestPlayer = player
        end
    end
    
    return closestPlayer
end

local function GetPredictedPosition(targetPart)
    local pos = targetPart.Position
    
    if Rayflare.Settings.Prediction.Enabled then
        local velocity = targetPart.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
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

    local triggerRayParams = RaycastParams.new()
    triggerRayParams.IgnoreWater = true

    if Rayflare.Settings.TriggerBot.WallCheck.Enabled then
        triggerRayParams.FilterType = Enum.RaycastFilterType.Exclude
        triggerRayParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    else
        triggerRayParams.FilterType = Enum.RaycastFilterType.Include
        local characters = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                table.insert(characters, player.Character)
            end
        end
        triggerRayParams.FilterDescendantsInstances = characters
    end

    local result = Workspace:Raycast(origin, direction, triggerRayParams)

    if result and result.Instance then
        local targetCharacter = result.Instance:FindFirstAncestorOfClass("Model")
        if targetCharacter then
            local player = Players:GetPlayerFromCharacter(targetCharacter)
            if player and player ~= LocalPlayer then
                local humanoid = targetCharacter:FindFirstChild("Humanoid")
                if humanoid and humanoid.Health > 0 and not IsTeamIgnored(player) then
                    
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

        if self.FOVCircle then
            if self.Settings.Enabled and self.Settings.FOV.Visible then
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

        -- Triggerbot logic now runs entirely independent of Legitbot's master switch
        CheckTriggerBot(mousePos)

        if not self.Settings.Enabled then 
            self.CurrentTarget = nil
            self.Settings.Trigger.IsAiming = false
            return 
        end

        local shouldAim = (self.Settings.Trigger.TriggerMode == "Always") or self.Settings.Trigger.IsAiming
        if not shouldAim then
            self.CurrentTarget = nil
            return
        end

        if self.Settings.TargetLock and self.CurrentTarget then
            local isValid = IsValidTarget(self.CurrentTarget, mousePos)
            if not isValid then
                self.CurrentTarget = GetClosestTarget(mousePos)
            end
        else
            self.CurrentTarget = GetClosestTarget(mousePos)
        end
        
        if self.CurrentTarget and self.CurrentTarget.Character then
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
    self.Settings.Trigger.IsAiming = false
    self.Settings.TriggerBot.IsAiming = false
    print("[ Rayflare ] Engine unloaded and memory cleared.")
end

return Rayflare
