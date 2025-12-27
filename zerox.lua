local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- [[ 1. Create Window ]] --
local Window = Fluent:CreateWindow({
    Title = "CFrame Hub V 10.0", 
    SubTitle = "Spectate Updated (Clean Version)",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true, 
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
})

-- [[ 2. System Logic & Variables ]] --
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local espObjects = {}
local flySpeed = 50
local flyEnabled = false
local flyConnection
local noclipEnabled = false
local noclipConnection
local spectating = false

-- [Anti-AFK System]
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- [Get Player List]
local function getPlayerList()
    local list = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(list, p.Name) end
    end
    return list
end

-- [ESP Function]
local function createESP(player)
    if player == LocalPlayer then return end
    local function addESP(character)
        pcall(function()
            if espObjects[player.UserId] then espObjects[player.UserId]:Destroy() end
            local highlight = Instance.new("Highlight")
            highlight.Name = "GeminiESP"
            highlight.FillColor = Color3.fromRGB(255, 0, 0)
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.FillTransparency = 0.5
            highlight.OutlineTransparency = 0
            highlight.Parent = character
            espObjects[player.UserId] = highlight
        end)
    end
    if player.Character then addESP(player.Character) end
    player.CharacterAdded:Connect(addESP)
end

local function removeESP(player)
    pcall(function()
        if espObjects[player.UserId] then 
            espObjects[player.UserId]:Destroy() 
            espObjects[player.UserId] = nil
        end
    end)
end

-- [Fly Function]
local function toggleFly(state)
    flyEnabled = state
    if state then
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local root = char:WaitForChild("HumanoidRootPart")
        local bv = Instance.new("BodyVelocity", root)
        local bg = Instance.new("BodyGyro", root)
        bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        
        flyConnection = RunService.RenderStepped:Connect(function()
            local cam = workspace.CurrentCamera
            local dir = Vector3.new(0,0,0)
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0,1,0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.new(0,1,0) end
            bv.Velocity = dir * flySpeed
            bg.CFrame = cam.CFrame
        end)
    else
        if flyConnection then flyConnection:Disconnect() end
        local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root then
            if root:FindFirstChild("BodyVelocity") then root.BodyVelocity:Destroy() end
            if root:FindFirstChild("BodyGyro") then root.BodyGyro:Destroy() end
        end
    end
end

-- [[ 3. Interface Layout ]] --
local Tabs = {
    Main = Window:AddTab({ Title = "Main Cheats", Icon = "home" }),
    Visuals = Window:AddTab({ Title = "Visuals", Icon = "eye" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "map-pin" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Options = Fluent.Options

do
    -- [[ TAB: MAIN CHEATS ]] --
    Tabs.Main:AddParagraph({ Title = "Character Stats", Content = "Adjust physical attributes" })

    Tabs.Main:AddSlider("WalkSpeed", {
        Title = "WalkSpeed",
        Default = 16,
        Min = 16,
        Max = 500,
        Rounding = 1,
        Callback = function(Value)
            if LocalPlayer.Character then 
                LocalPlayer.Character:FindFirstChildOfClass("Humanoid").WalkSpeed = Value 
            end
        end
    })

    Tabs.Main:AddSlider("JumpPower", {
        Title = "JumpPower",
        Default = 50,
        Min = 50,
        Max = 1000,
        Rounding = 1,
        Callback = function(Value)
            if LocalPlayer.Character then 
                local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                hum.UseJumpPower = true
                hum.JumpPower = Value 
            end
        end
    })

    Tabs.Main:AddParagraph({ Title = "Movement", Content = "Movement modifiers" })

    local NoclipToggle = Tabs.Main:AddToggle("Noclip", {Title = "Noclip", Default = false })
    NoclipToggle:OnChanged(function()
        local Value = Options.Noclip.Value
        if noclipConnection then noclipConnection:Disconnect() end
        if Value then
            noclipConnection = RunService.Stepped:Connect(function()
                if LocalPlayer.Character then
                    for _, v in pairs(LocalPlayer.Character:GetDescendants()) do
                        if v:IsA("BasePart") then v.CanCollide = false end
                    end
                end
            end)
        end
    end)

    local FlyToggle = Tabs.Main:AddToggle("Fly", {Title = "Enable Fly", Default = false })
    FlyToggle:OnChanged(function()
        toggleFly(Options.Fly.Value)
    end)

    Tabs.Main:AddSlider("FlySpeed", {
        Title = "Fly Speed",
        Default = 50,
        Min = 10,
        Max = 500,
        Rounding = 5,
        Callback = function(Value)
            flySpeed = Value
        end
    })

    -- [[ TAB: VISUALS ]] --
    Tabs.Visuals:AddParagraph({ Title = "Spectate Player", Content = "ดูมุมมองผู้เล่นคนอื่น" })

    local SpectateDropdown = Tabs.Visuals:AddDropdown("SpectateTarget", {
        Title = "Select Player to Spectate",
        Values = getPlayerList(),
        Multi = false,
        Default = nil,
    })

    Tabs.Visuals:AddButton({
        Title = "Refresh Spectate List",
        Callback = function()
            SpectateDropdown:SetValues(getPlayerList())
        end
    })

    Tabs.Visuals:AddToggle("SpectateToggle", {
        Title = "Enable Spectate", 
        Default = false,
        Callback = function(Value)
            spectating = Value
            if not Value then
                workspace.CurrentCamera.CameraSubject = LocalPlayer.Character:FindFirstChild("Humanoid")
            end
        end
    })

    -- [[ ส่วนของ Fullbright และ FOV ถูกลบออกแล้ว ]] --

    Tabs.Visuals:AddParagraph({ Title = "ESP Settings", Content = "See players through walls" })

    Tabs.Visuals:AddToggle("ESPAll", {Title = "ESP All Players", Default = false, Callback = function(Value)
        if Value then
            for _, p in pairs(Players:GetPlayers()) do createESP(p) end
        else
            for _, p in pairs(Players:GetPlayers()) do removeESP(p) end
            espObjects = {}
        end
    end})

    local EspDropdown = Tabs.Visuals:AddDropdown("EspTarget", {
        Title = "Select Player for ESP",
        Values = getPlayerList(),
        Multi = false,
        Default = nil,
    })

    Tabs.Visuals:AddButton({
        Title = "Refresh ESP List",
        Callback = function()
            EspDropdown:SetValues(getPlayerList())
        end
    })

    Tabs.Visuals:AddToggle("TargetESPToggle", {Title = "Target ESP Switch", Default = false })
    
    Options.TargetESPToggle:OnChanged(function()
        local Value = Options.TargetESPToggle.Value
        local selectedName = Options.EspTarget.Value
        if selectedName then
            local target = Players:FindFirstChild(selectedName)
            if target then
                if Value then createESP(target) else removeESP(target) end
            end
        else
            if Value then Options.TargetESPToggle:SetValue(false) end
        end
    end)

    -- [[ TAB: TELEPORT ]] --
    Tabs.Teleport:AddParagraph({ Title = "Click Teleport", Content = "Hold Key + Click to Teleport" })

    Tabs.Teleport:AddKeybind("ClickTP", {
        Title = "Click TP Keybind",
        Mode = "Hold",
        Default = "LeftControl",
        Callback = function(Value) end,
    })

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if Options.ClickTP:GetState() and Mouse.Target then
                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(Mouse.Hit.p + Vector3.new(0, 3, 0))
                end
            end
        end
    end)

    Tabs.Teleport:AddParagraph({ Title = "Player Teleport", Content = "Teleport to specific player" })

    local TpDropdown = Tabs.Teleport:AddDropdown("TpTarget", {
        Title = "Select Player to Teleport",
        Values = getPlayerList(),
        Multi = false,
        Default = nil,
    })

    Tabs.Teleport:AddButton({
        Title = "Refresh TP List",
        Callback = function()
            TpDropdown:SetValues(getPlayerList())
        end
    })

    Tabs.Teleport:AddButton({
        Title = "Teleport Now",
        Callback = function()
            local selectedName = Options.TpTarget.Value
            if selectedName then
                local target = Players:FindFirstChild(selectedName)
                local myChar = LocalPlayer.Character
                local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
                if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") and myRoot then
                    myRoot.CFrame = target.Character.HumanoidRootPart.CFrame * CFrame.new(0, 3, 0)
                end
            else
                Fluent:Notify({Title = "Warning", Content = "Select a player first!", Duration = 3})
            end
        end
    })

    -- [[ TAB: SETTINGS ]] --
    Tabs.Settings:AddButton({
        Title = "Rejoin Server",
        Description = "Rejoin the current server",
        Callback = function()
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        end
    })

    Tabs.Settings:AddButton({
        Title = "Reset Character",
        Description = "Kill/Reset your character",
        Callback = function()
            if LocalPlayer.Character then LocalPlayer.Character:BreakJoints() end
        end
    })
    
    InterfaceManager:SetLibrary(Fluent)
    InterfaceManager:BuildInterfaceSection(Tabs.Settings) 
end

-- [[ Loop for Spectate Logic ]] --
RunService.RenderStepped:Connect(function()
    if spectating then
        local selectedName = Options.SpectateTarget.Value
        if selectedName then
            local target = Players:FindFirstChild(selectedName)
            if target and target.Character and target.Character:FindFirstChild("Humanoid") then
                workspace.CurrentCamera.CameraSubject = target.Character.Humanoid
            end
        end
    end
end)

Fluent:Notify({
    Title = "Gemini Hub V9.1",
    Content = "Clean Version Loaded",
    Duration = 5
})

Window:SelectTab(1)
