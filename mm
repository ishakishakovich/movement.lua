--[[ Nyx Movement Suite v3.0 ]]--

local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting     = game:GetService("Lighting")
local StarterGui   = game:GetService("StarterGui")

local lp = Players.LocalPlayer
local conns = {}
local gui, mainFrame
local listeningForBind = false

local state = {
    bhop        = true,
    pixelSurf   = true,
    airStrafe   = true,
    fastLadder  = true,
    edgeBug     = true,
    doubleJump  = true,
    longJump    = false,
    slide       = false,
    autoStrafe  = false,
    cinematic   = false,
    speed       = 32,
    jumpPower   = 50,
    surfSpeed   = 24,
    airMul      = 1.02,
    gravity     = 196.2,
    fov         = 70,
    surfBind    = Enum.KeyCode.Q,
}

local function addConn(c) table.insert(conns, c) end
local function getHum()
    local char = lp.Character
    return char and char:FindFirstChildOfClass("Humanoid"), char
end
local function grounded(hum)
    return hum.FloorMaterial ~= Enum.Material.Air
end

-- ================= CORE =================

local spaceDown, surfDown = false, false
local lastJump, jumpsLeft, sliding = 0, 1, false
local rShiftHeld = false

addConn(UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.Space then
        spaceDown = true
        -- double jump — второй прыжок в воздухе
        if state.doubleJump and jumpsLeft > 0 then
            local hum = getHum()
            if hum and not grounded(hum) then
                hum.Jump = true
                jumpsLeft = jumpsLeft - 1
            end
        end
    end
    if input.KeyCode == state.surfBind then surfDown = true end
end))

addConn(UIS.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Space then spaceDown = false end
    if input.KeyCode == state.surfBind then surfDown = false end
    if input.KeyCode == Enum.KeyCode.LeftControl then sliding = false end
end))

addConn(RunService.Heartbeat:Connect(function()
    local hum, char = getHum()
    if not hum or hum.Health <= 0 then return end
    local root = hum.RootPart
    if not root then return end
    local now = tick()
    local onGround = grounded(hum)

    if onGround then jumpsLeft = 1 end

    -- BHOP — только при зажатом пробеле
    if state.bhop and spaceDown and onGround and now - lastJump > 0.06 then
        hum.Jump = true
        hum.WalkSpeed = state.speed
        lastJump = now
    end

    -- PIXEL SURF — по бинду, горизонталь фикс, ноль Y
    if state.pixelSurf and surfDown and not onGround then
        local vel = root.AssemblyLinearVelocity
        local flat = Vector3.new(vel.X, 0, vel.Z)
        if flat.Magnitude > 0.1 then
            local dir = flat.Unit
            root.AssemblyLinearVelocity = Vector3.new(dir.X * state.surfSpeed, 0, dir.Z * state.surfSpeed)
        end
    end

    -- AIR STRAFE — мягкий контроль направления в воздухе
    if state.airStrafe and not onGround and not (state.pixelSurf and surfDown) then
        local vel = root.AssemblyLinearVelocity
        local flat = Vector3.new(vel.X, 0, vel.Z)
        local mag = flat.Magnitude
        if mag > 1 and mag < 80 then
            root.AssemblyLinearVelocity = Vector3.new(flat.X * state.airMul, vel.Y, flat.Z * state.airMul)
        end
    end

    -- AUTO STRAFE — сам добавляет боковое ускорение в сторону движения
    if state.autoStrafe and not onGround then
        local vel = root.AssemblyLinearVelocity
        local flat = Vector3.new(vel.X, 0, vel.Z)
        if flat.Magnitude > 1 then
            local moveDir = hum.MoveDirection
            if moveDir.Magnitude > 0.1 then
                local perp = Vector3.new(-flat.Unit.Z, 0, flat.Unit.X)
                local side = math.sign(perp:Dot(moveDir))
                local add = perp * side * 3
                root.AssemblyLinearVelocity = flat + add + Vector3.new(0, vel.Y, 0)
            end
        end
    end

    -- FAST LADDER
    if state.fastLadder and hum:GetState() == Enum.HumanoidStateType.Climbing then
        local vel = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(vel.X, vel.Y * 2.5, vel.Z)
    end

    -- EDGE BUG — держит вертикаль у края
    if state.edgeBug and not onGround then
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {char}
        params.FilterType = Enum.RaycastFilterType.Exclude
        local hit = workspace:Raycast(root.Position, Vector3.new(0, -3.5, 0), params)
        if hit and hit.Distance < 1.6 then
            local vel = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
        end
    end

    -- LONG JUMP — при приседании+прыжок даёт импульс вперёд
    if state.longJump and UIS:IsKeyDown(Enum.KeyCode.LeftControl) and spaceDown and onGround then
        local dir = hum.MoveDirection
        if dir.Magnitude > 0.1 and now - lastJump > 0.2 then
            root.AssemblyLinearVelocity = Vector3.new(dir.X * state.speed * 1.8, 60, dir.Z * state.speed * 1.8)
            lastJump = now
        end
    end

    -- SLIDE — присед + скорость x1.6, hipHeight вниз
    if state.slide and UIS:IsKeyDown(Enum.KeyCode.LeftControl) and onGround then
        if not sliding then
            sliding = true
            hum.HipHeight = 0.2
            hum.WalkSpeed = state.speed * 1.6
        end
    elseif sliding then
        sliding = false
        hum.HipHeight = 2
        hum.WalkSpeed = state.speed
    end
end))

-- ================= VISUAL (cinematic) =================

local origFOV, origGravity = workspace.CurrentCamera.FieldOfView, workspace.Gravity

local function applyVisuals()
    local cam = workspace.CurrentCamera
    if state.cinematic then
        cam.FieldOfView = state.fov
        pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
        end)
        local shake = Lighting:FindFirstChild("CameraShake")
        if shake then shake:Destroy() end
    else
        cam.FieldOfView = origFOV
        pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
        end)
    end
end

addConn(RunService.RenderStepped:Connect(function()
    if state.cinematic then
        workspace.CurrentCamera.FieldOfView = state.fov
    end
end))

-- ================= UNLOAD =================

local function unload()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    if gui then gui:Destroy() end
    local hum = getHum()
    if hum then hum.WalkSpeed = 16; hum.JumpPower = 50; hum.HipHeight = 2 end
    workspace.Gravity = origGravity
    workspace.CurrentCamera.FieldOfView = origFOV
    pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
    print("[Nyx] unloaded")
end

-- ================= UI =================

local function makeToggle(parent, text, key, hint, yPos)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -20, 0, 34)
    row.Position = UDim2.new(0, 10, 0, yPos)
    row.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    row.BorderSizePixel = 0
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -110, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(220, 220, 230)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    if hint then
        local h = Instance.new("TextLabel")
        h.Size = UDim2.new(0, 60, 1, 0)
        h.Position = UDim2.new(1, -112, 0, 0)
        h.BackgroundTransparency = 1
        h.Text = hint
        h.TextColor3 = Color3.fromRGB(110, 110, 130)
        h.Font = Enum.Font.Gotham
        h.TextSize = 11
        h.TextXAlignment = Enum.TextXAlignment.Right
        h.Parent = row
    end

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 40, 0, 20)
    btn.Position = UDim2.new(1, -50, 0.5, -10)
    btn.BackgroundColor3 = state[key] and Color3.fromRGB(90, 160, 255) or Color3.fromRGB(45, 45, 55)
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Parent = row
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = state[key] and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    knob.BackgroundColor3 = state[key] and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 150, 160)
    knob.BorderSizePixel = 0
    knob.Parent = btn
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    btn.MouseButton1Click:Connect(function()
        state[key] = not state[key]
        TweenService:Create(btn, TweenInfo.new(0.15), {
            BackgroundColor3 = state[key] and Color3.fromRGB(90, 160, 255) or Color3.fromRGB(45, 45, 55)
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = state[key] and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        }):Play()
        if key == "cinematic" then applyVisuals() end
    end)
end

local function makeSlider(parent, text, key, min, max, yPos, onChange)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -20, 0, 44)
    row.Position = UDim2.new(0, 10, 0, yPos)
    row.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    row.BorderSizePixel = 0
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 0, 20)
    label.Position = UDim2.new(0, 12, 0, 4)
    label.BackgroundTransparency = 1
    label.Text = text .. ": " .. tostring(state[key])
    label.TextColor3 = Color3.fromRGB(220, 220, 230)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -24, 0, 6)
    track.Position = UDim2.new(0, 12, 0, 30)
    track.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    track.BorderSizePixel = 0
    track.Parent = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((state[key] - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(90, 160, 255)
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local dragging = false
    local function setFromX(x)
        local p = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local val = math.floor(min + (max - min) * p)
        state[key] = val
        fill.Size = UDim2.new(p, 0, 1, 0)
        label.Text = text .. ": " .. tostring(val)
        if onChange then onChange(val) end
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; setFromX(input.Position.X) end
    end)
    addConn(UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then setFromX(input.Position.X) end
    end))
    addConn(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end))
end

local function makeCategoryLabel(parent, text, yPos)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -20, 0, 20)
    lbl.Position = UDim2.new(0, 10, 0, yPos)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(120, 130, 160)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent
end

local function buildUI()
    gui = Instance.new("ScreenGui")
    gui.Name = "NyxMovement"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = lp:WaitForChild("PlayerGui")

    mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 290, 0, 520)
    mainFrame.Position = UDim2.new(0.5, -145, 0.5, -260)
    mainFrame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
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

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 46)
    header.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    header.BorderSizePixel = 0
    header.Parent = mainFrame
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)
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

    -- drag
    local draggingH, dragStart, startPos
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingH = true; dragStart = input.Position; startPos = mainFrame.Position
        end
    end)
    addConn(UIS.InputChanged:Connect(function(input)
        if draggingH and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    addConn(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then draggingH = false end
    end))

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, -100)
    scroll.Position = UDim2.new(0, 0, 0, 50)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = Color3.fromRGB(90, 160, 255)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 900)
    scroll.Parent = mainFrame

    local y = 6

    makeCategoryLabel(scroll, "MOVEMENT", y); y = y + 22
    makeToggle(scroll, "Auto Bhop", "bhop", "hold space", y); y = y + 40
    makeToggle(scroll, "Pixel Surf", "pixelSurf", "bind", y); y = y + 40
    makeToggle(scroll, "Air Strafe", "airStrafe", nil, y); y = y + 40
    makeToggle(scroll, "Auto Strafe", "autoStrafe", nil, y); y = y + 40
    makeToggle(scroll, "Fast Ladder", "fastLadder", nil, y); y = y + 40
    makeToggle(scroll, "Edge Bug", "edgeBug", nil, y); y = y + 40
    makeToggle(scroll, "Double Jump", "doubleJump", "space air", y); y = y + 40
    makeToggle(scroll, "Long Jump", "longJump", "ctrl+space", y); y = y + 40
    makeToggle(scroll, "Slide", "slide", "hold ctrl", y); y = y + 40

    y = y + 8
    makeCategoryLabel(scroll, "TUNING", y); y = y + 22
    makeSlider(scroll, "Speed", "speed", 16, 200, y, function(v)
        local hum = getHum(); if hum then hum.WalkSpeed = v end
    end); y = y + 50
    makeSlider(scroll, "Jump Power", "jumpPower", 50, 300, y, function(v)
        local hum = getHum(); if hum then hum.JumpPower = v end
    end); y = y + 50
    makeSlider(scroll, "Surf Speed", "surfSpeed", 8, 100, y); y = y + 50
    makeSlider(scroll, "Air Mul", "airMul", 100, 120, y, function(v)
        state.airMul = v / 100
    end); y = y + 50
    makeSlider(scroll, "Gravity", "gravity", 20, 400, y, function(v)
        workspace.Gravity = v
    end); y = y + 50

    y = y + 8
    makeCategoryLabel(scroll, "VISUAL", y); y = y + 22
    makeToggle(scroll, "Cinematic", "cinematic", "no hud", y); y = y + 40
    makeSlider(scroll, "FOV", "fov", 40, 120, y, function(v)
        if state.cinematic then workspace.CurrentCamera.FieldOfView = v end
    end); y = y + 50

    -- bind row
    local bindRow = Instance.new("Frame")
    bindRow.Size = UDim2.new(1, -20, 0, 44)
    bindRow.Position = UDim2.new(0, 10, 0, y)
    bindRow.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    bindRow.BorderSizePixel = 0
    bindRow.Parent = scroll
    Instance.new("UICorner", bindRow).CornerRadius = UDim.new(0, 6)

    local bindText = Instance.new("TextLabel")
    bindText.Size = UDim2.new(1, -100, 1, 0)
    bindText.Position = UDim2.new(0, 12, 0, 0)
    bindText.BackgroundTransparency = 1
    bindText.Text = "Pixel Surf Bind"
    bindText.TextColor3 = Color3.fromRGB(220, 220, 230)
    bindText.Font = Enum.Font.GothamMedium
    bindText.TextSize = 13
    bindText.TextXAlignment = Enum.TextXAlignment.Left
    bindText.Parent = bindRow

    local bindButton = Instance.new("TextButton")
    bindButton.Size = UDim2.new(0, 80, 0, 26)
    bindButton.Position = UDim2.new(1, -90, 0.5, -13)
    bindButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    bindButton.Text = state.surfBind.Name
    bindButton.TextColor3 = Color3.fromRGB(220, 220, 230)
    bindButton.Font = Enum.Font.GothamBold
    bindButton.TextSize = 12
    bindButton.BorderSizePixel = 0
    bindButton.Parent = bindRow
    Instance.new("UICorner", bindButton).CornerRadius = UDim.new(0, 6)

    bindButton.MouseButton1Click:Connect(function()
        listeningForBind = true
        bindButton.Text = "..."
        bindButton.BackgroundColor3 = Color3.fromRGB(90, 160, 255)
    end)

    addConn(UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if listeningForBind and input.UserInputType == Enum.UserInputType.Keyboard then
            state.surfBind = input.KeyCode
            bindButton.Text = input.KeyCode.Name
            bindButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
            listeningForBind = false
        end
    end))

    -- unload
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

    addConn(UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            mainFrame.Visible = not mainFrame.Visible
        end
    end))
end

buildUI()
print("[Nyx] v3.0 loaded — RightShift toggle menu.")
