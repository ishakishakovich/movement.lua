--[[ Nyx Movement Suite v1.0 ]]--

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local lp = Players.LocalPlayer
local connections = {}
local gui, mainFrame
local state = {
    bhop = false,
    pixelSurf = false,
    airStrafe = false,
    fastLadder = false,
    bhopSpeed = 32,
    surfSpeed = 24,
    airMul = 1.02,
}

local function addConn(c) table.insert(connections, c) end

local function getHum()
    local char = lp.Character
    return char and char:FindFirstChildOfClass("Humanoid"), char
end

local function grounded(hum) return hum.FloorMaterial ~= Enum.Material.Air end

-- ================= CORE =================

addConn(RunService.Heartbeat:Connect(function()
    local hum, char = getHum()
    if not hum or hum.Health <= 0 then return end
    local root = hum.RootPart
    if not root then return end

    -- BHOP
    if state.bhop and grounded(hum) then
        hum.Jump = true
        hum.WalkSpeed = state.bhopSpeed
    end

    -- PIXEL SURF: скольжение без подъёма, фикс скорости, ноль Y
    if state.pixelSurf and not grounded(hum) then
        local vel = root.AssemblyLinearVelocity
        local flat = Vector3.new(vel.X, 0, vel.Z)
        if flat.Magnitude > 0.1 then
            local dir = flat.Unit
            root.AssemblyLinearVelocity = Vector3.new(
                dir.X * state.surfSpeed,
                0, -- ноль вертикали, не поднимаемся
                dir.Z * state.surfSpeed
            )
        end
    end

    -- AIR STRAFE (мягкий разгон)
    if state.airStrafe and not grounded(hum) and not state.pixelSurf then
        local vel = root.AssemblyLinearVelocity
        local flat = Vector3.new(vel.X, 0, vel.Z)
        local mag = flat.Magnitude
        if mag > 1 and mag < 60 then
            root.AssemblyLinearVelocity = Vector3.new(
                flat.X * state.airMul, vel.Y, flat.Z * state.airMul
            )
        end
    end

    -- FAST LADDER
    if state.fastLadder and hum:GetState() == Enum.HumanoidStateType.Climbing then
        local vel = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(vel.X, vel.Y * 2.5, vel.Z)
    end
end))

-- ================= UNLOAD =================

local function unload()
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    connections = {}
    if gui then gui:Destroy() end
    local hum = getHum()
    if hum then
        hum.WalkSpeed = 16
        hum.JumpPower = 50
    end
    print("[Nyx] unloaded")
end

-- ================= UI =================

local function makeToggle(parent, text, key, yPos)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -20, 0, 34)
    row.Position = UDim2.new(0, 10, 0, yPos)
    row.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    row.BorderSizePixel = 0
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -60, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(220, 220, 230)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 40, 0, 20)
    btn.Position = UDim2.new(1, -50, 0.5, -10)
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Parent = row
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = UDim2.new(0, 2, 0.5, -8)
    knob.BackgroundColor3 = Color3.fromRGB(150, 150, 160)
    knob.BorderSizePixel = 0
    knob.Parent = btn
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    btn.MouseButton1Click:Connect(function()
        state[key] = not state[key]
        local on = state[key]
        TweenService:Create(btn, TweenInfo.new(0.15), {
            BackgroundColor3 = on and Color3.fromRGB(90, 160, 255) or Color3.fromRGB(45, 45, 55)
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = on and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
            BackgroundColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 150, 160)
        }):Play()
    end)
    return row
end

local function buildUI()
    gui = Instance.new("ScreenGui")
    gui.Name = "NyxMovement"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = lp:WaitForChild("PlayerGui")

    mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 260, 0, 380)
    mainFrame.Position = UDim2.new(0.5, -130, 0.5, -190)
    mainFrame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Parent = gui
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(90, 160, 255)
    stroke.Thickness = 1
    stroke.Transparency = 0.4
    stroke.Parent = mainFrame

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 160, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 90, 255)),
    }
    grad.Rotation = 45
    grad.Parent = stroke

    -- header
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 46)
    header.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    header.BorderSizePixel = 0
    header.Parent = mainFrame
    local hc = Instance.new("UICorner", header); hc.CornerRadius = UDim.new(0, 10)
    -- маска снизу чтобы углы не скруглялись
    local headerMask = Instance.new("Frame")
    headerMask.Size = UDim2.new(1, 0, 0, 10)
    headerMask.Position = UDim2.new(0, 0, 1, -10)
    headerMask.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    headerMask.BorderSizePixel = 0
    headerMask.Parent = header

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -50, 1, 0)
    title.Position = UDim2.new(0, 16, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "Nyx  ·  Movement"
    title.TextColor3 = Color3.fromRGB(230, 230, 240)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 24, 0, 24)
    close.Position = UDim2.new(1, -32, 0.5, -12)
    close.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    close.Text = "×"
    close.TextColor3 = Color3.fromRGB(220, 220, 230)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 16
    close.BorderSizePixel = 0
    close.Parent = header
    Instance.new("UICorner", close).CornerRadius = UDim.new(1, 0)
    close.MouseButton1Click:Connect(function() mainFrame.Visible = false end)

    -- toggles
    local toggles = Instance.new("Frame")
    toggles.Size = UDim2.new(1, 0, 1, -56)
    toggles.Position = UDim2.new(0, 0, 0, 50)
    toggles.BackgroundTransparency = 1
    toggles.Parent = mainFrame

    makeToggle(toggles, "Auto Bhop", "bhop", 6)
    makeToggle(toggles, "Pixel Surf", "pixelSurf", 46)
    makeToggle(toggles, "Air Strafe", "airStrafe", 86)
    makeToggle(toggles, "Fast Ladder", "fastLadder", 126)

    -- unload button
    local unloadBtn = Instance.new("TextButton")
    unloadBtn.Size = UDim2.new(1, -20, 0, 34)
    unloadBtn.Position = UDim2.new(0, 10, 1, -44)
    unloadBtn.BackgroundColor3 = Color3.fromRGB(160, 60, 60)
    unloadBtn.Text = "Unload"
    unloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    unloadBtn.Font = Enum.Font.GothamBold
    unloadBtn.TextSize = 14
    unloadBtn.BorderSizePixel = 0
    unloadBtn.Parent = mainFrame
    Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0, 6)
    unloadBtn.MouseButton1Click:Connect(unload)

    -- toggle ui bind
    UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            mainFrame.Visible = not mainFrame.Visible
        end
    end)
end

buildUI()
print("[Nyx] loaded — RightShift to toggle menu, Unload button to remove.")
