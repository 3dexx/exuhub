-- ExuHub experimental - Roube um Exu (Roblox)
-- Ajustado para o ambiente Luau do Solara: usa getgenv/gethui quando presentes,
-- com fallback para _G/PlayerGui; não depende obrigatoriamente de fireproximityprompt.
-- Auto-roubo/raridade/depósito continuam heurísticos e dependem da estrutura do jogo.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Compatibility: use Solara's documented global environment when available,
-- but keep a safe fallback for environments where getgenv is absent.
local Env = _G
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then Env = result end
end

if Env.ExuHubCleanup then
    pcall(Env.ExuHubCleanup)
end

local S = {
    dead = false,
    speed = false,
    fly = false,
    auto = false,
    base = nil,
    route = nil,
    velocity = nil,
    conn = nil,
    usedPrompts = setmetatable({}, { __mode = "k" }),
    savedSpeeds = setmetatable({}, { __mode = "k" }),
    savedCollisions = setmetatable({}, { __mode = "k" }),
    walkSpeedValue = 350,
    flightSpeedValue = 650,
}

local function characterParts()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil end
    return char, char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function restoreCollisions()
    for part, oldValue in pairs(S.savedCollisions) do
        if part and part.Parent then
            pcall(function() part.CanCollide = oldValue end)
        end
        S.savedCollisions[part] = nil
    end
end

local function setNoclip(enabled)
    local char = LocalPlayer.Character
    if enabled and char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if S.savedCollisions[part] == nil then
                    S.savedCollisions[part] = part.CanCollide
                end
                pcall(function() part.CanCollide = false end)
            end
        end
    else
        restoreCollisions()
    end
end

local function cleanup()
    if S.dead then return end
    S.dead = true
    S.auto, S.fly, S.speed = false, false, false
    S.route = nil
    setNoclip(false)
    if S.conn then S.conn:Disconnect() end
    if S.dragConn then S.dragConn:Disconnect() end
    if S.velocity then S.velocity:Destroy() end
    for humanoid, oldSpeed in pairs(S.savedSpeeds) do
        if humanoid and humanoid.Parent then
            pcall(function() humanoid.WalkSpeed = oldSpeed end)
        end
    end
    if S.gui then S.gui:Destroy() end
    Env.ExuHubCleanup = nil
end
Env.ExuHubCleanup = cleanup

-- Interface
local gui = Instance.new("ScreenGui")
gui.Name = "ExuHub"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local parentOk, parent = pcall(function()
    if type(gethui) == "function" then return gethui() end
    return LocalPlayer:WaitForChild("PlayerGui")
end)
gui.Parent = (parentOk and parent) or LocalPlayer:WaitForChild("PlayerGui")
S.gui = gui

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(248, 278)
frame.Position = UDim2.new(0, 24, 0.38, 0)
frame.BackgroundColor3 = Color3.fromRGB(22, 23, 31)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(115, 75, 180)
stroke.Thickness = 1.4

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 32)
title.Position = UDim2.fromOffset(8, 4)
title.BackgroundTransparency = 1
title.Text = "EXU HUB  •  BETA"
title.TextColor3 = Color3.fromRGB(202, 166, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 34)
status.Position = UDim2.fromOffset(10, 238)
status.BackgroundTransparency = 1
status.Text = "Marque sua base antes do Auto Roubar."
status.TextColor3 = Color3.fromRGB(205, 205, 218)
status.Font = Enum.Font.Gotham
status.TextSize = 10
status.TextWrapped = true
status.Parent = frame
S.status = status

local function setStatus(text)
    if S.status and S.status.Parent then S.status.Text = text end
end

local function makeButton(text, y, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -20, 0, 32)
    button.Position = UDim2.fromOffset(10, y)
    button.BackgroundColor3 = Color3.fromRGB(46, 43, 61)
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = Color3.fromRGB(245, 245, 250)
    button.Font = Enum.Font.GothamSemibold
    button.TextSize = 12
    button.AutoButtonColor = true
    button.Parent = frame
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)
    button.MouseButton1Click:Connect(function()
        if not S.dead then callback(button) end
    end)
    return button
end

local function updateToggle(button, label, key)
    S[key] = not S[key]
    button.Text = label .. ": " .. (S[key] and "ON" or "OFF")
    button.BackgroundColor3 = S[key] and Color3.fromRGB(102, 65, 163) or Color3.fromRGB(46, 43, 61)
end

local function textLower(...)
    local out = {}
    for _, value in ipairs({...}) do
        if value ~= nil then table.insert(out, tostring(value)) end
    end
    return string.lower(table.concat(out, " "))
end

local rarityWords = {
    {"unobtainable", 1450}, {"impossible", 1425}, {"transcendent", 1400}, {"transcendente", 1400},
    {"prismatic", 1375}, {"prismático", 1375}, {"prismatico", 1375}, {"eternal", 1350}, {"eterno", 1350},
    {"admin", 1325}, {"infinito", 1300}, {"infinite", 1300}, {"omega", 1250}, {"apex", 1225}, {"???", 1200},
    {"exclusive", 1050}, {"exclusivo", 1050}, {"limited", 1020}, {"limitado", 1020},
    {"secret", 1000}, {"secreto", 1000}, {"cosmic", 950}, {"cósmico", 950}, {"cosmico", 950},
    {"mythical", 900}, {"mythic", 880}, {"mitico", 880}, {"mítico", 880},
    {"celestial", 850}, {"divine", 830}, {"divino", 830}, {"godly", 810}, {"supreme", 790},
    {"legendary", 750}, {"lendario", 750}, {"lendário", 750}, {"lendária", 750}, {"legend", 740},
    {"epic", 620}, {"epico", 620}, {"épico", 620}, {"rare", 500}, {"raro", 500},
    {"uncommon", 350}, {"incomum", 350}, {"common", 200}, {"comum", 200},
}

local function promptInfo(prompt)
    local parentObject = prompt.Parent
    if parentObject and parentObject:IsA("Attachment") then parentObject = parentObject.Parent end
    local model = prompt:FindFirstAncestorOfClass("Model")
    local part = parentObject and parentObject:IsA("BasePart") and parentObject or nil
    if not part and model then part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true) end
    if not part and parentObject and parentObject:IsA("Model") then
        part = parentObject.PrimaryPart or parentObject:FindFirstChildWhichIsA("BasePart", true)
    end
    if not part then return nil end

    local promptPosition = part.Position
    if prompt.Parent and prompt.Parent:IsA("Attachment") then
        promptPosition = prompt.Parent.WorldPosition
    elseif prompt.Parent and prompt.Parent:IsA("BasePart") then
        promptPosition = prompt.Parent.Position
    end

    local pieces = {prompt.Name, prompt.ActionText, prompt.ObjectText}
    if model then table.insert(pieces, model.Name) end
    local attributesText = {}
    local source = model or parentObject
    if source then
        for key, value in pairs(source:GetAttributes()) do
            if type(value) == "string" or type(value) == "number" then
                table.insert(attributesText, key .. " " .. tostring(value))
            end
        end
    end

    -- Some games show rarity only in a BillboardGui/TextLabel rather than
    -- in the model name. Read a limited amount of visible text when present.
    if model then
        local added = 0
        for _, child in ipairs(model:GetDescendants()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                local visibleText = tostring(child.Text or "")
                local lowerText = string.lower(visibleText)
                local relevant = lowerText:find("exu", 1, true) ~= nil
                for _, rarityEntry in ipairs(rarityWords) do
                    if lowerText:find(rarityEntry[1], 1, true) then
                        relevant = true
                        break
                    end
                end
                if relevant and #visibleText <= 100 then
                    table.insert(attributesText, visibleText)
                    added += 1
                    if added >= 12 then break end
                end
            end
        end
    end

    table.insert(pieces, table.concat(attributesText, " "))
    local label = textLower(table.unpack(pieces))
    local looksLikeExu = label:find("exu", 1, true) ~= nil
    local hasStealWord = label:find("roubar", 1, true) or label:find("steal", 1, true)
    if not looksLikeExu and not hasStealWord then return nil end
    if label:find("deposit", 1, true) or label:find("guardar", 1, true) or label:find("colocar", 1, true) then
        return nil
    end

    local rarity = 10
    for _, entry in ipairs(rarityWords) do
        if label:find(entry[1], 1, true) then rarity = math.max(rarity, entry[2]) end
    end
    return { prompt = prompt, part = part, model = model, label = label, rarity = rarity, position = promptPosition }
end

local function bestExuPrompt()
    local _, _, root = characterParts()
    if not root then return nil end
    local best, bestDistance
    for _, item in ipairs(Workspace:GetDescendants()) do
        if item:IsA("ProximityPrompt") and item.Enabled then
            local info = promptInfo(item)
            local usedAt = S.usedPrompts[item]
            if info and (not usedAt or os.clock() - usedAt > 35) then
                local distance = (info.position - root.Position).Magnitude
                if not best or info.rarity > best.rarity or (info.rarity == best.rarity and distance < bestDistance) then
                    info.distance = distance
                    best, bestDistance = info, distance
                end
            end
        end
    end
    return best
end

local function activatePrompt(prompt)
    if not prompt or not prompt.Parent or not prompt.Enabled then return false end

    -- Prefer the ProximityPrompt input methods; they do not depend on a
    -- non-standard executor helper. Fall back to fireproximityprompt if present.
    local ok = pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(0.15, tonumber(prompt.HoldDuration) or 0))
        prompt:InputHoldEnd()
    end)
    if ok then return true end

    if type(fireproximityprompt) == "function" then
        local fired = pcall(fireproximityprompt, prompt)
        return fired
    end
    return false
end

local function travelTo(position, tolerance, timeout)
    local started = os.clock()
    tolerance = tolerance or 3

    -- Auto Steal steers directly to the target's actual prompt height.
    -- The flight controller below follows S.route even if manual Fly is OFF.
    while not S.dead and S.auto and os.clock() - started < timeout do
        local _, humanoid, root = characterParts()
        if not root or not humanoid then break end

        local distance = (position - root.Position).Magnitude
        if distance <= tolerance then
            S.route = nil
            return true
        end

        S.route = position
        task.wait(0.035)
    end

    S.route = nil
    return false
end

-- Teleporte direto: o servidor do jogo pode corrigir a posição ou rejeitá-lo.
-- Por isso a função confere a posição após mover e permite fallback para voo.
local function teleportTo(position, verticalOffset, allowedError)
    local _, _, root = characterParts()
    if not root or typeof(position) ~= "Vector3" then return false end

    local destination = position + Vector3.new(0, verticalOffset or 1.5, 0)
    allowedError = allowedError or 10

    for attempt = 1, 3 do
        local _, _, currentRoot = characterParts()
        if not currentRoot then return false end
        pcall(function()
            currentRoot.AssemblyLinearVelocity = Vector3.zero
            currentRoot.AssemblyAngularVelocity = Vector3.zero
            currentRoot.CFrame = CFrame.new(destination) * CFrame.Angles(0, math.rad(currentRoot.Orientation.Y), 0)
        end)
        task.wait(0.18)
        local _, _, checkRoot = characterParts()
        if checkRoot and (checkRoot.Position - destination).Magnitude <= allowedError then
            return true
        end
    end
    return false
end

local function tryDepositAtBase()
    if not S.base then return end
    for _, prompt in ipairs(Workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
            local parentObject = prompt.Parent
            if parentObject and parentObject:IsA("Attachment") then parentObject = parentObject.Parent end
            local part = parentObject and parentObject:IsA("BasePart") and parentObject or nil
            local model = prompt:FindFirstAncestorOfClass("Model")
            if not part and model then part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true) end
            if part and (part.Position - S.base).Magnitude <= 24 then
                local label = textLower(prompt.Name, prompt.ActionText, prompt.ObjectText, model and model.Name)
                if label:find("deposit",1,true) or label:find("guardar",1,true) or label:find("colocar",1,true)
                    or label:find("store",1,true) or label:find("drop",1,true) or label:find("base",1,true) then
                    activatePrompt(prompt)
                    task.wait(0.4)
                    return
                end
            end
        end
    end
end

local speedButton = makeButton("Velocidade: OFF", 42, function(b)
    updateToggle(b, "Velocidade", "speed")
    if not S.speed then
        local _, h = characterParts()
        if h and S.savedSpeeds[h] then h.WalkSpeed = S.savedSpeeds[h] end
    end
end)

local flyButton = makeButton("Voo: OFF", 79, function(b)
    updateToggle(b, "Voo", "fly")
    if not S.fly and S.velocity then S.velocity:Destroy(); S.velocity = nil end
end)

local autoButton = makeButton("Auto roubar: OFF", 116, function(b)
    if not S.base then
        setStatus("Primeiro clique em Marcar base estando dentro dela.")
        return
    end
    updateToggle(b, "Auto roubar", "auto")
    if S.auto then
        setStatus("Auto Steal: voo 3D + noclip no trajeto; buscando maior raridade identificável...")
        task.spawn(function()
            while S.auto and not S.dead do
                local target = bestExuPrompt()
                if not target then
                    setStatus("Não achei prompt de Exu reconhecível. Tentando de novo...")
                    task.wait(1.5)
                else
                    local name = target.model and target.model.Name or target.prompt.ObjectText
                    setStatus("Teleportando até: " .. tostring(name) .. " (raridade estimada " .. target.rarity .. ")")
                    -- Auto Steal tenta teleporte antes de iniciar o voo, para não chegar abaixo/acima do prompt.
                    local activationRange = math.clamp(tonumber(target.prompt.MaxActivationDistance) or 6, 3, 10)
                    local reached = teleportTo(target.position, 1.5, activationRange + 3)
                    if not reached and S.auto then
                        setStatus("Teleporte bloqueado; usando voo rápido até o Exu...")
                        reached = travelTo(target.position, math.clamp(activationRange, 3, 6), 18)
                    end
                    if not S.auto then break end
                    if reached and target.prompt.Parent and target.prompt.Enabled then
                        setStatus("Tentando roubar " .. tostring(name) .. "...")
                        activatePrompt(target.prompt)
                        S.usedPrompts[target.prompt] = os.clock()
                        task.wait(0.65)
                        setStatus("Teleportando de volta à base...")
                        local back = teleportTo(S.base, 3, 12)
                        if not back and S.auto then
                            setStatus("Teleporte de retorno bloqueado; usando voo rápido para a base...")
                            back = travelTo(S.base + Vector3.new(0, 3, 0), 7, 18)
                        end
                        if back then
                            tryDepositAtBase()
                            setStatus("Cheguei à base. Confirme se o jogo guardou o Exu.")
                        else
                            setStatus("Não consegui chegar à base. O servidor pode estar bloqueando a movimentação.")
                        end
                        task.wait(1.0)
                    else
                        S.usedPrompts[target.prompt] = os.clock()
                        setStatus("Alvo inacessível; tentando outro.")
                        task.wait(0.8)
                    end
                end
            end
        end)
    else
        S.route = nil
        setStatus("Auto roubar desligado.")
    end
end)

local baseButton = makeButton("Marcar base atual", 153, function(b)
    local _, _, root = characterParts()
    if not root then setStatus("Personagem ainda não carregou."); return end
    S.base = root.Position
    b.Text = "Base marcada ✓"
    b.BackgroundColor3 = Color3.fromRGB(43, 105, 77)
    setStatus("Base marcada. Ative Auto roubar para começar.")
end)

local closeButton = makeButton("Fechar / parar tudo", 190, cleanup)
closeButton.BackgroundColor3 = Color3.fromRGB(95, 43, 54)

-- Arrastar a janela pela barra de título
local dragging, dragInput, dragStart, startPos
local function updateDrag(input)
    local delta = input.Position - dragStart
    frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
title.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
end)
S.dragConn = UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then updateDrag(input) end
end)

S.conn = RunService.Heartbeat:Connect(function()
    if S.dead then return end
    local _, humanoid, root = characterParts()
    if humanoid then
        if S.speed then
            if not S.savedSpeeds[humanoid] then S.savedSpeeds[humanoid] = humanoid.WalkSpeed end
            humanoid.WalkSpeed = S.walkSpeedValue
        elseif S.savedSpeeds[humanoid] then
            humanoid.WalkSpeed = S.savedSpeeds[humanoid]
            S.savedSpeeds[humanoid] = nil
        end
    end

    local autopilot = S.auto and S.route ~= nil
    -- Keep noclip enabled during the complete Auto Steal cycle, not only while following a flight waypoint.
    setNoclip(S.auto)

    if (S.fly or autopilot) and root then
        if not S.velocity or S.velocity.Parent ~= root then
            if S.velocity then S.velocity:Destroy() end
            local bv = Instance.new("BodyVelocity")
            bv.Name = "ExuHubVelocity"
            bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
            bv.P = 12000
            bv.Velocity = Vector3.zero
            bv.Parent = root
            S.velocity = bv
        end
        local direction = Vector3.zero
        local speedNow = S.flightSpeedValue
        if S.route then
            local delta = S.route - root.Position
            if delta.Magnitude > 0.6 then
                direction = delta.Unit
                -- Ease down close to the waypoint to avoid circling around
                -- tall Exus or overshooting the ProximityPrompt height.
                speedNow = math.min(S.flightSpeedValue, math.max(24, delta.Magnitude * 14))
            end
        else
            local camera = Workspace.CurrentCamera
            if camera then
                local look = camera.CFrame.LookVector
                local right = camera.CFrame.RightVector
                local forward = Vector3.new(look.X, 0, look.Z)
                local sideways = Vector3.new(right.X, 0, right.Z)
                if forward.Magnitude > 0 then forward = forward.Unit end
                if sideways.Magnitude > 0 then sideways = sideways.Unit end
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then direction += forward end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then direction -= forward end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then direction += sideways end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then direction -= sideways end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then direction += Vector3.yAxis end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then direction -= Vector3.yAxis end
            end
        end
        S.velocity.Velocity = direction.Magnitude > 0 and direction.Unit * speedNow or Vector3.zero
    elseif S.velocity then
        S.velocity:Destroy()
        S.velocity = nil
    end
end)

setStatus("Voo: 650 | velocidade: 350. Auto Steal tenta TP no Exu e na base; usa voo se TP falhar.")
