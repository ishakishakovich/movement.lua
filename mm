--[[ Nyx Suite v9.0 — Movement + Combat + Visual ]]--

local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VIM          = game:GetService("VirtualInputManager")

local lp = Players.LocalPlayer
local cam = workspace.CurrentCamera
local conns = {}
local gui, mainFrame, speedoGui, speedoLabel, statusLabel, accLabel, toastGui
local listeningForBind = nil
local drawingSupported = pcall(function() local d = Drawing.new("Line"); d:Remove() end)

local CONFIG_PATH = "nyx_suite_cfg.json"

local state = {
    -- movement
    bhop        = true,
    pixelSurf   = true,
    airStrafe   = true,
    fastLadder  = true,
    edgeBug     = false,
    doubleJump  = true,
    longJump    = false,
    slide       = false,
    slopeGuard  = true,
    speedometer = true,
    speed         = 40,
    jumpPower     = 52,
    surfSpeed     = 26,
    gravity       = 196.2,
    strafeAccel   = 8,
    maxAirSpeed   = 55,
    hopInc        = 2.5,
    maxBhopSpeed  = 68,
    surfBind      = Enum.KeyCode.Q,

    -- combat
    aimbot      = false,
    silentAim   = false,
    triggerBot  = false,
    aimFov      = 150,
    aimSmooth   = 20,
    aimPart     = "Head",
    wallCheck   = true,
    teamCheck   = true,
    friendCheck = false,
    aimFovCircle = true,
    trigDelay   = 0.05,

    -- visual
    espBox      = true,
    espName     = true,
    espDistance = true,
    espHealth   = true,
    espTracer   = false,
}

local strafeGain = 0
local bhopSpeed = state.speed
local lastHopTime = 0

-- ============ CONFIG ============

local function saveConfig()
    local data = {}
    for k, v in pairs(state) do
        if typeof(v) == "EnumItem" then data[k] = v.Name else data[k] = v end
    end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(data) end)
    if not ok then return false end
    return pcall(function() writefile(CONFIG_PATH, enc) end)
end

local function loadConfig()
    local ok, raw = pcall(function() return readfile(CONFIG_PATH) end)
    if not ok or not raw then return false end
    local ok2, data = pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
    if not ok2 or type(data) ~= "table" then return false end
    for k, v in pairs(data) do
        if state[k] ~= nil then
            if typeof(state[k]) == "EnumItem" then
                local kc = Enum.KeyCode[v]
                if kc then state[k] = kc end
            else state[k] = v end
        end
    end
    return true
end

-- ============ HELPERS ============

local function addConn(c) table.insert(conns, c) end
local function getHum()
    local char = lp.Character
    return char and char:FindFirstChildOfClass("Humanoid"), char
end
local function grounded(hum) return hum.FloorMaterial ~= Enum.Material.Air end

local function getWishDir(hum)
    local cf = cam.CFrame
    local fwd = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
    if fwd.Magnitude < 0.01 then return nil end
    fwd = fwd.Unit
    local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z).Unit
    local f = (UIS:IsKeyDown(Enum.KeyCode.W) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
    local s = (UIS:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
    local wish = fwd * f + right * s
    if wish.Magnitude > 0.01 then return wish.Unit end
    return nil
end

-- ============ TOAST ============

local function toast(text)
    if not toastGui then return end
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 220, 0, 36)
    frame.Position = UDim2.new(1, -240, 1, -80)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Parent = toastGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(90, 160, 255)
    stroke.Thickness = 1
    stroke.Transparency = 0.3
    stroke.Parent = frame

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -20, 1, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(230, 230, 240)
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = frame

    TweenService:Create(frame, TweenInfo.new(0.3), {
        Position = UDim2.new(1, -240, 1, -130)
    }):Play()

    task.delay(1.5, function()
        TweenService:Create(frame, TweenInfo.new(0.3), {
            Position = UDim2.new(1, -240, 1, -80),
            BackgroundTransparency = 1
        }):Play()
        TweenService:Create(lbl, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
        task.delay(0.35, function() frame:Destroy() end)
    end)
end

-- ============ MOVEMENT CORE ============

local spaceDown, surfDown = false, false
local lastJump, jumpsLeft, sliding = 0, 1, false

local function slopeAngle(char, root)
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Exclude
    local hit = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), params)
    if not hit then return 0 end
    return math.deg(math.acos(math.clamp(hit.Normal.Y, -1, 1)))
end

addConn(UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.Space then
        spaceDown = true
        if state.doubleJump and jumpsLeft > 0 then
            local hum = getHum()
            if hum and not grounded(hum) then
                hum.Jump = true
                jumpsLeft -= 1
            end
        end
    end
    if input.KeyCode == state.surfBind then surfDown = true end
end))

addConn(UIS.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Space then spaceDown = false end
    if input.KeyCode == state.surfBind then surfDown = false end
end))

addConn(lp.CharacterAdded:Connect(function()
    sliding = false
    jumpsLeft = 1
    lastJump = 0
    bhopSpeed = state.speed
end))

addConn(RunService.Heartbeat:Connect(function(dt)
    local hum, char = getHum()
    if not hum or hum.Health <= 0 then return end
    local root = hum.RootPart
    if not root then return end

    local now = tick()
    local onGround = grounded(hum)
    local vel = root.AssemblyLinearVelocity
    local bhopActive = state.bhop and spaceDown
    local ctrlDown = UIS:IsKeyDown(Enum.KeyCode.LeftControl)

    if onGround then jumpsLeft = 1 end

    if sliding and (not state.slide or not ctrlDown or not onGround) then
        sliding = false
        hum.HipHeight = 2
    end
    if state.slide and ctrlDown and onGround and not sliding then
        sliding = true
        hum.HipHeight = 0.2
    end

    if not bhopActive then
        if now - lastHopTime > 0.35 then
            bhopSpeed = bhopSpeed + (state.speed - bhopSpeed) * math.min(dt * 6, 1)
        end
    end
    if math.abs(bhopSpeed - state.speed) < 0.2 then bhopSpeed = state.speed end

    hum.WalkSpeed = sliding and (state.speed * 1.5) or math.max(state.speed, bhopSpeed)

    if not onGround then
        local flat = Vector3.new(vel.X, 0, vel.Z)
        local hardCap = math.max(state.maxBhopSpeed, state.maxAirSpeed) * 1.15
        if flat.Magnitude > hardCap then
            flat = flat.Unit * hardCap
            root.AssemblyLinearVelocity = Vector3.new(flat.X, vel.Y, flat.Z)
            vel = root.AssemblyLinearVelocity
        end
    end

    if bhopActive and onGround and now - lastJump > 0.04 then
        local slopeDeg = slopeAngle(char, root)
        if not (state.slopeGuard and slopeDeg > 45) then
            local flat = Vector3.new(vel.X, 0, vel.Z)
            local curSpeed = flat.Magnitude
            local curDir
            local md = hum.MoveDirection

            if curSpeed > 1.0 then
                curDir = flat.Unit
            elseif md.Magnitude > 0.1 then
                curDir = Vector3.new(md.X, 0, md.Z).Unit
                curSpeed = state.speed
            else
                local lv = root.CFrame.LookVector
                curDir = Vector3.new(lv.X, 0, lv.Z).Unit
                curSpeed = state.speed
            end

            local newSpeed = math.min(curSpeed + state.hopInc, state.maxBhopSpeed)
            bhopSpeed = newSpeed

            local newDir = curDir
            if md.Magnitude > 0.1 then
                local wishDir = Vector3.new(md.X, 0, md.Z).Unit
                local blended = curDir * 0.85 + wishDir * 0.15
                if blended.Magnitude > 0.01 then newDir = blended.Unit end
            end

            root.AssemblyLinearVelocity = Vector3.new(
                newDir.X * newSpeed, math.max(vel.Y, 0), newDir.Z * newSpeed
            )
            hum.Jump = true
            lastJump = now
            lastHopTime = now
        end
    end

    if onGround and not bhopActive and not sliding then
        if now - lastHopTime > 0.5 then
            local flat = Vector3.new(vel.X, 0, vel.Z)
            if flat.Magnitude > state.speed + 2 then
                local dir = flat.Unit
                root.AssemblyLinearVelocity = Vector3.new(dir.X * state.speed, vel.Y, dir.Z * state.speed)
            end
        end
    end

    strafeGain = 0
    if state.airStrafe and not onGround and not (state.pixelSurf and surfDown) then
        local wishdir = getWishDir(hum)
        if wishdir then
            local flat = Vector3.new(vel.X, 0, vel.Z)
            local currentSpeed = flat:Dot(wishdir)
            local addSpeed = state.maxAirSpeed - currentSpeed
            if addSpeed > 0 then
                local accelSpeed = state.strafeAccel * state.maxAirSpeed * dt
                if accelSpeed > addSpeed then accelSpeed = addSpeed end
                local newFlat = flat + wishdir * accelSpeed
                if newFlat.Magnitude > state.maxAirSpeed then
                    newFlat = newFlat.Unit * state.maxAirSpeed
                end
                strafeGain = (newFlat - flat).Magnitude
                root.AssemblyLinearVelocity = Vector3.new(newFlat.X, vel.Y, newFlat.Z)
            end
        end
    end

    if state.pixelSurf and surfDown and not onGround then
        local flat = Vector3.new(vel.X, 0, vel.Z)
        if flat.Magnitude > 0.1 then
            local dir = flat.Unit
            root.AssemblyLinearVelocity = Vector3.new(dir.X * state.surfSpeed, 0, dir.Z * state.surfSpeed)
        end
    end

    if state.fastLadder and hum:GetState() == Enum.HumanoidStateType.Climbing then
        root.AssemblyLinearVelocity = Vector3.new(vel.X, vel.Y * 2.5, vel.Z)
    end

    if state.edgeBug and not onGround and not bhopActive and vel.Y < 0 then
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {char}
        params.FilterType = Enum.RaycastFilterType.Exclude
        local h = workspace:Raycast(root.Position, Vector3.new(0, -1.2, 0), params)
        if h and h.Distance < 0.8 then
            root.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
        end
    end

    if state.longJump and ctrlDown and spaceDown and onGround and now - lastJump > 0.2 then
        local dir = hum.MoveDirection
        if dir.Magnitude > 0.1 then
            root.AssemblyLinearVelocity = Vector3.new(dir.X * state.speed * 1.7, 58, dir.Z * state.speed * 1.7)
            lastJump = now
        end
    end
end))

-- ============ COMBAT ============

local function isPlayerValid(plr)
    if plr == lp then return false end
    if state.teamCheck and plr.Team and plr.Team == lp.Team then return false end
    if state.friendCheck and plr.FriendStatus == Enum.FriendStatus.Friend then return false end
    local char = plr.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    return true
end

local function getAimPart(plr)
    local char = plr.Character
    if not char then return nil end
    if state.aimPart == "Head" then
        return char:FindFirstChild("Head")
    elseif state.aimPart == "Torso" then
        return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    end
    return char:FindFirstChild("Head")
end

local function canSee(plr, part)
    if not state.wallCheck then return true end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {lp.Character, cam}
    params.FilterType = Enum.RaycastFilterType.Exclude
    local hit = workspace:Raycast(cam.CFrame.Position, part.Position - cam.CFrame.Position, params)
    return hit == nil or hit.Instance:IsDescendantOf(plr.Character)
end

local function getAimTarget()
    local camPos = cam.CFrame.Position
    local camLook = cam.CFrame.LookVector
    local best, bestAngle = nil, math.rad(state.aimFov)

    for _, plr in ipairs(Players:GetPlayers()) do
        if not isPlayerValid(plr) then continue end
        local part = getAimPart(plr)
        if not part then continue end
        if not canSee(plr, part) then continue end

        local dir = (part.Position - camPos).Unit
        local angle = math.acos(math.clamp(dir:Dot(camLook), -1, 1))
        if angle < bestAngle then
            bestAngle = angle
            best = {player = plr, pos = part.Position, part = part}
        end
    end
    return best
end

-- Aimbot (BindToRenderStep after camera)
RunService:BindToRenderStep("NyxAim", Enum.RenderPriority.Camera.Value + 1, function()
    if not state.aimbot then return end
    if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
    local target = getAimTarget()
    if not target then return end
    local targetCF = CFrame.lookAt(cam.CFrame.Position, target.pos)
    local alpha = math.clamp(1 - (state.aimSmooth / 100), 0.02, 1)
    cam.CFrame = cam.CFrame:Lerp(targetCF, alpha)
end)

-- Silent aim (snap on fire)
local function silentAimFire()
    if not state.silentAim then return end
    local target = getAimTarget()
    if not target then return end
    local orig = cam.CFrame
    cam.CFrame = CFrame.lookAt(cam.CFrame.Position, target.pos)
    task.delay(0.06, function()
        if cam and cam.Parent then cam.CFrame = orig end
    end)
end

addConn(UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        silentAimFire()
    end
end))

-- Trigger bot
local lastTrig = 0
addConn(RunService.Heartbeat:Connect(function()
    if not state.triggerBot then return end
    if not UIS:IsKeyDown(Enum.KeyCode.X) then return end
    local now = tick()
    if now - lastTrig < state.trigDelay then return end
    local target = getAimTarget()
    if not target then return end
    lastTrig = now
    pcall(function()
        VIM:SendMouseButtonEvent(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2, 0, true, game, 0)
        task.wait(0.02)
        VIM:SendMouseButtonEvent(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2, 0, false, game, 0)
    end)
end))

-- FOV circle
local fovCircle
if drawingSupported then
    fovCircle = Drawing.new("Circle")
    fovCircle.Thickness = 1
    fovCircle.Color = Color3.fromRGB(90, 160, 255)
    fovCircle.Filled = false
    fovCircle.Transparency = 0.6
    fovCircle.NumSides = 48
    fovCircle.Visible = false
end

addConn(RunService.RenderStepped:Connect(function()
    if not fovCircle then return end
    if state.aimbot and state.aimFovCircle then
        local viewport = cam.ViewportSize
        local fovPx = math.tan(math.rad(state.aimFov)) * (viewport.Y / 2)
        fovCircle.Radius = fovPx
        fovCircle.Position = viewport / 2
        fovCircle.Visible = true
    else
        fovCircle.Visible = false
    end
end))

-- ============ ESP ============

local espCache = {}

local function createESP(plr)
    if not drawingSupported then return end
    local box = Drawing.new("Square")
    box.Thickness = 1
    box.Filled = false
    box.Color = Color3.fromRGB(90, 160, 255)
    box.Visible = false

    local name = Drawing.new("Text")
    name.Size = 14
    name.Center = true
    name.Outline = true
    name.OutlineColor = Color3.new(0, 0, 0)
    name.Color = Color3.fromRGB(255, 255, 255)
    name.Visible = false

    local dist = Drawing.new("Text")
    dist.Size = 12
    dist.Center = true
    dist.Outline = true
    dist.OutlineColor = Color3.new(0, 0, 0)
    dist.Color = Color3.fromRGB(200, 200, 200)
    dist.Visible = false

    local healthBg = Drawing.new("Square")
    healthBg.Filled = true
    healthBg.Color = Color3.fromRGB(30, 30, 30)
    healthBg.Visible = false

    local healthFill = Drawing.new("Square")
    healthFill.Filled = true
    healthFill.Color = Color3.fromRGB(80, 220, 80)
    healthFill.Visible = false

    local tracer = Drawing.new("Line")
    tracer.Thickness = 1
    tracer.Color = Color3.fromRGB(90, 160, 255)
    tracer.Transparency = 0.6
    tracer.Visible = false

    espCache[plr] = {box=box, name=name, dist=dist, healthBg=healthBg, healthFill=healthFill, tracer=tracer}
end

local function hideESP(cache)
    for _, obj in pairs(cache) do obj.Visible = false end
end

local function getBox2D(char)
    local root = char:FindFirstChild("HumanoidRootPart")
    local head = char:FindFirstChild("Head")
    if not root or not head then return nil end

    local topPos = head.Position + Vector3.new(0, 0.8, 0)
    local bottomPos = root.Position - Vector3.new(0, 3.2, 0)

    local top, onTop = cam:WorldToViewportPoint(topPos)
    local bottom, onBottom = cam:WorldToViewportPoint(bottomPos)
    if not onTop or not onBottom then return nil end

    local height = math.abs(bottom.Y - top.Y)
    if height < 5 then return nil end
    local width = height * 0.55

    return {
        x = top.X - width/2, y = top.Y,
        w = width, h = height,
        cx = top.X, cy = top.Y + height/2,
    }
end

local function updateESP()
    if not drawingSupported then return end
    if not state.espBox and not state.espName and not state.espDistance
       and not state.espHealth and not state.espTracer then
        for _, cache in pairs(espCache) do hideESP(cache) end
        return
    end

    for plr, cache in pairs(espCache) do
        if plr == lp then hideESP(cache); continue end
        if not isPlayerValid(plr) then hideESP(cache); continue end
        local char = plr.Character
        if not char then hideESP(cache); continue end
        local box = getBox2D(char)
        if not box then hideESP(cache); continue end

        if state.espBox then
            cache.box.Size = Vector2.new(box.w, box.h)
            cache.box.Position = Vector2.new(box.x, box.y)
            cache.box.Color = Color3.fromRGB(90, 160, 255)
            cache.box.Visible = true
        else cache.box.Visible = false end

        if state.espName then
            cache.name.Text = plr.Name
            cache.name.Position = Vector2.new(box.cx, box.y - 18)
            cache.name.Visible = true
        else cache.name.Visible = false end

        if state.espDistance then
            local dist = (cam.CFrame.Position - char.HumanoidRootPart.Position).Magnitude
            cache.dist.Text = string.format("%d m", math.floor(dist))
            cache.dist.Position = Vector2.new(box.cx, box.y + box.h + 2)
            cache.dist.Visible = true
        else cache.dist.Visible = false end

        if state.espHealth then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                local hp = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                cache.healthBg.Size = Vector2.new(3, box.h)
                cache.healthBg.Position = Vector2.new(box.x - 6, box.y)
                cache.healthBg.Visible = true
                cache.healthFill.Size = Vector2.new(3, box.h * hp)
                cache.healthFill.Position = Vector2.new(box.x - 6, box.y + box.h * (1 - hp))
                cache.healthFill.Color = Color3.fromRGB(
                    math.floor(255 * (1 - hp)),
                    math.floor(255 * hp),
                    40
                )
                cache.healthFill.Visible = true
            else
                cache.healthBg.Visible = false
                cache.healthFill.Visible = false
            end
        else
            cache.healthBg.Visible = false
            cache.healthFill.Visible = false
        end

        if state.espTracer then
            local vp = cam.ViewportSize
            cache.tracer.From = Vector2.new(vp.X / 2, vp.Y)
            cache.tracer.To = Vector2.new(box.cx, box.cy)
            cache.tracer.Visible = true
        else cache.tracer.Visible = false end
    end
end

addConn(RunService.RenderStepped:Connect(updateESP))

addConn(Players.PlayerAdded:Connect(createESP))
addConn(Players.PlayerRemoving:Connect(function(plr)
    local cache = espCache[plr]
    if cache then
        for _, obj in pairs(cache) do pcall(function() obj:Remove() end) end
        espCache[plr] = nil
    end
end))

for _, plr in ipairs(Players:GetPlayers()) do createESP(plr) end

-- ============ SPEEDOMETER ============

local function buildSpeedo()
    speedoGui = Instance.new("ScreenGui")
    speedoGui.Name = "NyxSpeedo"
    speedoGui.ResetOnSpawn = false
    speedoGui.Parent = lp:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 180, 0, 86)
    frame.Position = UDim2.new(0, 20, 0, 20)
    frame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Parent = speedoGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(90, 160, 255)
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    stroke.Parent = frame

    speedoLabel = Instance.new("TextLabel")
    speedoLabel.Size = UDim2.new(1, 0, 0, 30)
    speedoLabel.Position = UDim2.new(0, 0, 0, 6)
    speedoLabel.BackgroundTransparency = 1
    speedoLabel.Text = "0  studs/s"
    speedoLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
    speedoLabel.Font = Enum.Font.GothamBold
    speedoLabel.TextSize = 18
    speedoLabel.Parent = frame

    accLabel = Instance.new("TextLabel")
    accLabel.Size = UDim2.new(1, 0, 0, 16)
    accLabel.Position = UDim2.new(0, 0, 0, 34)
    accLabel.BackgroundTransparency = 1
    accLabel.Text = "acc: 40"
    accLabel.TextColor3 = Color3.fromRGB(120, 130, 160)
    accLabel.Font = Enum.Font.Gotham
    accLabel.TextSize = 11
    accLabel.Parent = frame

    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 0, 20)
    statusLabel.Position = UDim2.new(0, 0, 0, 54)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "idle"
    statusLabel.TextColor3 = Color3.fromRGB(120, 130, 160)
    statusLabel.Font = Enum.Font.GothamMedium
    statusLabel.TextSize = 11
    statusLabel.Parent = frame
end

addConn(RunService.RenderStepped:Connect(function()
    if not state.speedometer then
        if speedoGui then speedoGui.Enabled = false end
        return
    end
    if speedoGui then speedoGui.Enabled = true end
    local hum = getHum()
    if not hum or not hum.RootPart then return end
    local v = hum.RootPart.AssemblyLinearVelocity
    local flat = Vector3.new(v.X, 0, v.Z).Magnitude
    speedoLabel.Text = string.format("%d  studs/s", math.floor(flat))
    accLabel.Text = string.format("acc: %.1f", bhopSpeed)
    if bhopSpeed > state.speed + 1 then
        accLabel.TextColor3 = Color3.fromRGB(255, 180, 90)
    else
        accLabel.TextColor3 = Color3.fromRGB(120, 130, 160)
    end

    local tag = "idle"
    local onGround = grounded(hum)
    if sliding then tag = "slide"
    elseif state.pixelSurf and surfDown and not onGround then tag = "surf"
    elseif not onGround and strafeGain > 0.5 then tag = "strafe+"
    elseif not onGround and state.bhop and spaceDown then tag = "bhop"
    elseif not onGround then tag = "air"
    elseif hum.MoveDirection.Magnitude > 0.1 then tag = "run"
    end
    statusLabel.Text = tag
    if tag == "strafe+" then statusLabel.TextColor3 = Color3.fromRGB(120, 220, 255)
    elseif tag ~= "idle" and tag ~= "run" then statusLabel.TextColor3 = Color3.fromRGB(90, 160, 255)
    else statusLabel.TextColor3 = Color3.fromRGB(120, 130, 160) end
end))

local function buildToast()
    toastGui = Instance.new("ScreenGui")
    toastGui.Name = "NyxToast"
    toastGui.ResetOnSpawn = false
    toastGui.Parent = lp:WaitForChild("PlayerGui")
end

-- ============ UNLOAD ============

local function unload()
    pcall(saveConfig)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    pcall(function() RunService:UnbindFromRenderStep("NyxAim") end)
    if fovCircle then pcall(function() fovCircle:Remove() end) end
    for _, cache in pairs(espCache) do
        for _, obj in pairs(cache) do pcall(function() obj:Remove() end) end
    end
    espCache = {}
    if gui then gui:Destroy() end
    if speedoGui then speedoGui:Destroy() end
    if toastGui then toastGui:Destroy() end
    local hum = getHum()
    if hum then hum.WalkSpeed = 16; hum.JumpPower = 50; hum.HipHeight = 2 end
    pcall(function() workspace.Gravity = 196.2 end)
    print("[Nyx] unloaded")
end

-- ============ UI HELPERS ============

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
        local pill = Instance.new("Frame")
        pill.Size = UDim2.new(0, 56, 0, 18)
        pill.Position = UDim2.new(1, -118, 0.5, -9)
        pill.BackgroundColor3 = Color3.fromRGB(30, 34, 44)
        pill.BorderSizePixel = 0
        pill.Parent = row
        Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
        local h = Instance.new("TextLabel")
        h.Size = UDim2.new(1, 0, 1, 0)
        h.BackgroundTransparency = 1
        h.Text = hint
        h.TextColor3 = Color3.fromRGB(130, 150, 190)
        h.Font = Enum.Font.GothamBold
        h.TextSize = 10
        h.Parent = pill
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
    end)
end

local function makeSlider(parent, text, key, min, max, yPos, onChange, isFloat)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -20, 0, 44)
    row.Position = UDim2.new(0, 10, 0, yPos)
    row.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    row.BorderSizePixel = 0
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

    local function fmt(v)
        if isFloat then return string.format("%.1f", v) end
        return tostring(v)
    end

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 0, 20)
    label.Position = UDim2.new(0, 12, 0, 4)
    label.BackgroundTransparency = 1
    label.Text = text .. ": " .. fmt(state[key])
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
        local val
        if isFloat then val = math.floor((min + (max - min) * p) * 10) / 10
        else val = math.floor(min + (max - min) * p) end
        state[key] = val
        fill.Size = UDim2.new(p, 0, 1, 0)
        label.Text = text .. ": " .. fmt(val)
        fill.BackgroundColor3 = Color3.fromRGB(140, 200, 255)
        task.delay(0.15, function()
            if fill and fill.Parent then
                TweenService:Create(fill, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(90, 160, 255)}):Play()
            end
        end)
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

-- ============ BUILD UI ============

local function buildUI()
    gui = Instance.new("ScreenGui")
    gui.Name = "NyxSuite"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = lp:WaitForChild("PlayerGui")

    mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 360, 0, 560)
    mainFrame.Position = UDim2.new(0.5, -180, 0.5, -280)
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
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160, 90, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 160, 255)),
    }
    grad.Rotation = 45
    grad.Parent = stroke
    addConn(RunService.RenderStepped:Connect(function()
        if stroke and stroke.Parent then grad.Rotation = (grad.Rotation + 0.4) % 360 end
    end))

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 46)
    header.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    header.BorderSizePixel = 0
    header.Parent = mainFrame
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)
    local hm = Instance.new("Frame")
    hm.Size = UDim2.new(1, 0, 0, 10); hm.Position = UDim2.new(0, 0, 1, -10)
    hm.BackgroundColor3 = Color3.fromRGB(20, 20, 26); hm.BorderSizePixel = 0
    hm.Parent = header

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -50, 1, 0)
    title.Position = UDim2.new(0, 16, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "Nyx  ·  Suite  v9"
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
    close.AutoButtonColor = false
    close.Parent = header
    Instance.new("UICorner", close).CornerRadius = UDim.new(1, 0)
    close.MouseButton1Click:Connect(function() mainFrame.Visible = false end)

    local dh, ds, dp
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dh = true; ds = input.Position; dp = mainFrame.Position
        end
    end)
    addConn(UIS.InputChanged:Connect(function(input)
        if dh and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - ds
            mainFrame.Position = UDim2.new(dp.X.Scale, dp.X.Offset + d.X, dp.Y.Scale, dp.Y.Offset + d.Y)
        end
    end))
    addConn(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dh = false end
    end))

    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -20, 0, 30)
    tabBar.Position = UDim2.new(0, 10, 0, 52)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = mainFrame
    local tabList = Instance.new("UIListLayout")
    tabList.FillDirection = Enum.FillDirection.Horizontal
    tabList.Padding = UDim.new(0, 5)
    tabList.Parent = tabBar

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, 0, 1, -142)
    content.Position = UDim2.new(0, 0, 0, 88)
    content.BackgroundTransparency = 1
    content.Parent = mainFrame

    local tabs = {}
    local tabButtons = {}

    local function makeTabButton(name)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 72, 1, 0)
        b.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
        b.Text = name
        b.TextColor3 = Color3.fromRGB(150, 150, 170)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.BorderSizePixel = 0
        b.AutoButtonColor = false
        b.Parent = tabBar
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)

        b.MouseEnter:Connect(function()
            if not b:GetAttribute("active") then
                TweenService:Create(b, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(32, 32, 42)}):Play()
            end
        end)
        b.MouseLeave:Connect(function()
            if not b:GetAttribute("active") then
                TweenService:Create(b, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(22, 22, 28)}):Play()
            end
        end)
        b.MouseButton1Click:Connect(function()
            for _, t in pairs(tabs) do t.page.Visible = false end
            for _, other in ipairs(tabButtons) do
                other:SetAttribute("active", false)
                TweenService:Create(other, TweenInfo.new(0.15), {
                    BackgroundColor3 = Color3.fromRGB(22, 22, 28),
                    TextColor3 = Color3.fromRGB(150, 150, 170),
                }):Play()
            end
            b:SetAttribute("active", true)
            TweenService:Create(b, TweenInfo.new(0.15), {
                BackgroundColor3 = Color3.fromRGB(90, 160, 255),
                TextColor3 = Color3.fromRGB(255, 255, 255),
            }):Play()
            tabs[name].page.Visible = true
        end)
        b:SetAttribute("active", false)
        table.insert(tabButtons, b)
        return b
    end

    local function createPage(name)
        local page = Instance.new("ScrollingFrame")
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 3
        page.ScrollBarImageColor3 = Color3.fromRGB(90, 160, 255)
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.Visible = false
        page.Parent = content
        tabs[name] = {page = page}
        return page
    end

    local pageMove = createPage("Move")
    local pageCombat = createPage("Combat")
    local pageVisual = createPage("Visual")
    local pageTune = createPage("Tune")
    local pageCfg  = createPage("Cfg")

    makeTabButton("Move")
    makeTabButton("Combat")
    makeTabButton("Visual")
    makeTabButton("Tune")
    makeTabButton("Cfg")

    -- MOVE
    local y = 6
    makeCategoryLabel(pageMove, "MOVEMENT", y); y = y + 22
    makeToggle(pageMove, "Auto Bhop", "bhop", "space", y); y = y + 40
    makeToggle(pageMove, "Air Strafe", "airStrafe", "a/d + turn", y); y = y + 40
    makeToggle(pageMove, "Pixel Surf", "pixelSurf", "bind", y); y = y + 40
    makeToggle(pageMove, "Fast Ladder", "fastLadder", nil, y); y = y + 40
    makeToggle(pageMove, "Edge Bug", "edgeBug", nil, y); y = y + 40
    makeToggle(pageMove, "Double Jump", "doubleJump", "space air", y); y = y + 40
    makeToggle(pageMove, "Long Jump", "longJump", "ctrl+jump", y); y = y + 40
    makeToggle(pageMove, "Slide", "slide", "ctrl", y); y = y + 40
    makeToggle(pageMove, "Slope Guard", "slopeGuard", "anti-slide", y); y = y + 40
    makeToggle(pageMove, "Speedometer", "speedometer", nil, y); y = y + 40
    pageMove.CanvasSize = UDim2.new(0, 0, 0, y + 10)

    -- COMBAT
    y = 6
    makeCategoryLabel(pageCombat, "AIMBOT", y); y = y + 22
    makeToggle(pageCombat, "Aimbot", "aimbot", "hold rmb", y); y = y + 40
    makeToggle(pageCombat, "Silent Aim", "silentAim", "on click", y); y = y + 40
    makeToggle(pageCombat, "Trigger Bot", "triggerBot", "hold x", y); y = y + 40
    makeSlider(pageCombat, "Aim FOV", "aimFov", 10, 400, y); y = y + 50
    makeSlider(pageCombat, "Aim Smooth", "aimSmooth", 1, 100, y); y = y + 50
    makeSlider(pageCombat, "Trigger Delay", "trigDelay", 1, 20, y, function(v)
        state.trigDelay = v / 100
    end, false); y = y + 50
    makeToggle(pageCombat, "Wall Check", "wallCheck", nil, y); y = y + 40
    makeToggle(pageCombat, "Team Check", "teamCheck", nil, y); y = y + 40
    makeToggle(pageCombat, "Friend Check", "friendCheck", nil, y); y = y + 40
    makeToggle(pageCombat, "FOV Circle", "aimFovCircle", nil, y); y = y + 40
    pageCombat.CanvasSize = UDim2.new(0, 0, 0, y + 10)

    -- VISUAL
    y = 6
    makeCategoryLabel(pageVisual, "ESP", y); y = y + 22
    makeToggle(pageVisual, "Box ESP", "espBox", nil, y); y = y + 40
    makeToggle(pageVisual, "Name", "espName", nil, y); y = y + 40
    makeToggle(pageVisual, "Distance", "espDistance", nil, y); y = y + 40
    makeToggle(pageVisual, "Health Bar", "espHealth", nil, y); y = y + 40
    makeToggle(pageVisual, "Tracer", "espTracer", nil, y); y = y + 40
    pageVisual.CanvasSize = UDim2.new(0, 0, 0, y + 10)

    -- TUNE
    y = 6
    makeCategoryLabel(pageTune, "BHOP", y); y = y + 22
    makeSlider(pageTune, "Hop Increment", "hopInc", 1, 8, y, nil, true); y = y + 50
    makeSlider(pageTune, "Max Bhop Speed", "maxBhopSpeed", 40, 120, y); y = y + 50

    makeCategoryLabel(pageTune, "STRAFE", y); y = y + 22
    makeSlider(pageTune, "Strafe Accel", "strafeAccel", 2, 30, y); y = y + 50
    makeSlider(pageTune, "Max Air Speed", "maxAirSpeed", 20, 120, y); y = y + 50

    makeCategoryLabel(pageTune, "BASE", y); y = y + 22
    makeSlider(pageTune, "Walk Speed", "speed", 16, 100, y, function(v)
        if bhopSpeed < v then bhopSpeed = v end
    end); y = y + 50
    makeSlider(pageTune, "Jump Power", "jumpPower", 50, 250, y, function(v)
        local hum = getHum(); if hum then hum.JumpPower = v end
    end); y = y + 50
    makeSlider(pageTune, "Surf Speed", "surfSpeed", 8, 100, y); y = y + 50
    makeSlider(pageTune, "Gravity", "gravity", 40, 400, y, function(v)
        workspace.Gravity = v
    end); y = y + 50
    pageTune.CanvasSize = UDim2.new(0, 0, 0, y + 10)

    -- CFG
    y = 6
    makeCategoryLabel(pageCfg, "BINDS", y); y = y + 22
    local bindRow = Instance.new("Frame")
    bindRow.Size = UDim2.new(1, -20, 0, 44)
    bindRow.Position = UDim2.new(0, 10, 0, y)
    bindRow.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    bindRow.BorderSizePixel = 0
    bindRow.Parent = pageCfg
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
        listeningForBind = "surfBind"
        bindButton.Text = "..."
        bindButton.BackgroundColor3 = Color3.fromRGB(90, 160, 255)
    end)

    addConn(UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if listeningForBind == "surfBind" and input.UserInputType == Enum.UserInputType.Keyboard then
            state.surfBind = input.KeyCode
            bindButton.Text = input.KeyCode.Name
            bindButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
            listeningForBind = nil
            toast("bind set: " .. input.KeyCode.Name)
        end
    end))

    y = y + 54
    makeCategoryLabel(pageCfg, "CONFIG", y); y = y + 22

    local function makeActionBtn(text, color, yPos, action)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -20, 0, 32)
        b.Position = UDim2.new(0, 10, 0, yPos)
        b.BackgroundColor3 = color
        b.Text = text
        b.TextColor3 = Color3.fromRGB(230, 230, 240)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.BorderSizePixel = 0
        b.AutoButtonColor = false
        b.Parent = pageCfg
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        b.MouseButton1Click:Connect(action)
        b.MouseEnter:Connect(function()
            TweenService:Create(b, TweenInfo.new(0.1), {
                BackgroundColor3 = color:Lerp(Color3.fromRGB(255,255,255), 0.1)
            }):Play()
        end)
        b.MouseLeave:Connect(function()
            TweenService:Create(b, TweenInfo.new(0.1), {BackgroundColor3 = color}):Play()
        end)
    end

    makeActionBtn("Save Config", Color3.fromRGB(50, 90, 60), y, function()
        if saveConfig() then toast("config saved") else toast("save failed") end
    end); y = y + 38
    makeActionBtn("Load Config", Color3.fromRGB(50, 60, 90), y, function()
        if loadConfig() then toast("config loaded") else toast("load failed") end
    end); y = y + 38

    y = y + 6
    makeCategoryLabel(pageCfg, "HELP", y); y = y + 22

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -20, 0, 150)
    info.Position = UDim2.new(0, 10, 0, y)
    info.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    info.BorderSizePixel = 0
    info.Text = "  RightShift — меню\n  Space — bhop / double jump\n  Ctrl — slide,  Ctrl+Space — long jump\n  Bind — pixel surf\n\n  Aimbot — держи ПКМ\n  Silent Aim — клик ЛКМ (снап на кадр)\n  Trigger Bot — держи X (авто-клик по цели)\n  FOV circle — в Combat"
    info.TextColor3 = Color3.fromRGB(180, 180, 200)
    info.Font = Enum.Font.Gotham
    info.TextSize = 11
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Top
    info.Parent = pageCfg
    Instance.new("UICorner", info).CornerRadius = UDim.new(0, 6)

    pageCfg.CanvasSize = UDim2.new(0, 0, 0, y + 165)

    local unloadBtn = Instance.new("TextButton")
    unloadBtn.Size = UDim2.new(1, -20, 0, 34)
    unloadBtn.Position = UDim2.new(0, 10, 1, -44)
    unloadBtn.BackgroundColor3 = Color3.fromRGB(160, 60, 60)
    unloadBtn.Text = "Unload"
    unloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    unloadBtn.Font = Enum.Font.GothamBold
    unloadBtn.TextSize = 14
    unloadBtn.BorderSizePixel = 0
    unloadBtn.AutoButtonColor = false
    unloadBtn.Parent = mainFrame
    Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0, 6)
    unloadBtn.MouseButton1Click:Connect(unload)
    unloadBtn.MouseEnter:Connect(function()
        TweenService:Create(unloadBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(200, 80, 80)}):Play()
    end)
    unloadBtn.MouseLeave:Connect(function()
        TweenService:Create(unloadBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(160, 60, 60)}):Play()
    end)

    tabs["Move"].page.Visible = true
    for _, b in ipairs(tabButtons) do
        if b.Text == "Move" then
            b:SetAttribute("active", true)
            b.BackgroundColor3 = Color3.fromRGB(90, 160, 255)
            b.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
    end

    addConn(UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            mainFrame.Visible = not mainFrame.Visible
        end
    end))
end

pcall(loadConfig)
bhopSpeed = state.speed
buildUI()
buildSpeedo()
buildToast()
print("[Nyx] v9.0 loaded — RightShift toggle menu.")
