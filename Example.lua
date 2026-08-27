-- 1. Load Both Libraries
local Fever = loadstring(game:HttpGet("https://raw.githubusercontent.com/d1versity/Fever/refs/heads/main/Library.lua"))()
local Rayflare = loadstring(game:HttpGet("https://raw.githubusercontent.com/d1versity/Rayflare/refs/heads/main/Library.lua"))()

-- Initialize the Aimbot Engine
Rayflare:Load()

-- 2. Create the Fever UI Window
local Window = Fever:CreateWindow("Rayflare Controller", true)

-- ========================================== --
--                MAIN AIMBOT                 --
-- ========================================== --
local MainTab = Window:CreateTab("Combat")

MainTab:CreateParagraph("Rayflare Engine", "Configure your primary targeting settings here.")

MainTab:CreateToggle("Enable Aimbot", Rayflare.Settings.Enabled, function(state)
    Rayflare.Settings.Enabled = state
end)

MainTab:CreateDropdown("Aim Part", {"Head", "HumanoidRootPart", "UpperTorso"}, Rayflare.Settings.AimPart, function(selected)
    Rayflare.Settings.AimPart = selected
end)

MainTab:CreateDropdown("Aiming Method", {"Camera", "Cursor"}, Rayflare.Settings.AimType, function(selected)
    Rayflare.Settings.AimType = selected
end)

MainTab:CreateSlider("Smoothing (Legit Mode)", 0, 20, Rayflare.Settings.Smoothness, function(value)
    Rayflare.Settings.Smoothness = value
end)

MainTab:CreateToggle("Target Lock-On", Rayflare.Settings.TargetLock, function(state)
    Rayflare.Settings.TargetLock = state
end)

-- ========================================== --
--             TRIGGER & FOV                  --
-- ========================================== --
local FOVTab = Window:CreateTab("Trigger & FOV")

FOVTab:CreateDropdown("Trigger Mode", {"Hold", "Toggle", "Always"}, Rayflare.Settings.Trigger.TriggerMode, function(selected)
    Rayflare.Settings.Trigger.TriggerMode = selected
end)

FOVTab:CreateKeybind("Trigger Key", Rayflare.Settings.Trigger.TriggerKey, function(newKey)
    Rayflare.Settings.Trigger.TriggerKey = newKey
end)

FOVTab:CreateLabel("Field of View Settings")

FOVTab:CreateToggle("Show FOV Circle", Rayflare.Settings.FOV.Visible, function(state)
    Rayflare.Settings.FOV.Visible = state
end)

FOVTab:CreateSlider("FOV Radius", 10, 800, Rayflare.Settings.FOV.Radius, function(value)
    Rayflare.Settings.FOV.Radius = value
end)

FOVTab:CreateToggle("RGB Chroma Circle", Rayflare.Settings.FOV.Chroma, function(state)
    Rayflare.Settings.FOV.Chroma = state
end)

FOVTab:CreateColorPicker("FOV Color", Rayflare.Settings.FOV.Color, function(color)
    Rayflare.Settings.FOV.Color = color
end)

-- ========================================== --
--          CHECKS & PREDICTION               --
-- ========================================== --
local AdvancedTab = Window:CreateTab("Advanced")

AdvancedTab:CreateToggle("Team Check", Rayflare.Settings.TeamCheck.Enabled, function(state)
    Rayflare.Settings.TeamCheck.Enabled = state
end)

AdvancedTab:CreateToggle("Wall Check (Visibility)", Rayflare.Settings.WallCheck.Enabled, function(state)
    Rayflare.Settings.WallCheck.Enabled = state
end)

AdvancedTab:CreateLabel("Movement Prediction")

AdvancedTab:CreateToggle("Enable Prediction", Rayflare.Settings.Prediction.Enabled, function(state)
    Rayflare.Settings.Prediction.Enabled = state
end)

AdvancedTab:CreateToggle("Dynamic Prediction Scaling", Rayflare.Settings.Prediction.Dynamic, function(state)
    Rayflare.Settings.Prediction.Dynamic = state
end)

AdvancedTab:CreateSlider("Manual X Prediction", 0, 10, Rayflare.Settings.Prediction.X * 10, function(value)
    Rayflare.Settings.Prediction.X = value / 10
end)

AdvancedTab:CreateSlider("Manual Y Prediction", 0, 10, Rayflare.Settings.Prediction.Y * 10, function(value)
    Rayflare.Settings.Prediction.Y = value / 10
end)

-- ========================================== --
--                  SETTINGS                  --
-- ========================================== --
local SettingsTab = Window:CreateTab("Settings")

SettingsTab:CreateButton("Unload Scripts", function()
    Rayflare:Unload()
    Fever:Unload()
end)

-- Initialize built-in cinematic settings
Window:CreateSettingsTab()
