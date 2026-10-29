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
}

local function characterParts()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil end
    return char, char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function cleanup()
    if S.dead then return end
    S.dead = true
    S.auto, S.fly, S.speed = false, false, false
    S.route = nil
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
    {"infinito", 1000}, {"infinite", 1000}, {"???", 1000}, {"secret", 900}, {"secreto", 900},
    {"mythical", 820}, {"mythic", 800}, {"mitico", 800}, {"mítico", 800},
    {"celestial", 760}, {"divine", 750}, {"divino", 750}, {"godly", 720},
    {"legendary", 650}, {"lendario", 650}, {"lendário", 650}, {"lendária", 650}, {"legend", 640},
    {"epic", 520}, {"epico", 520}, {"épico", 520}, {"rare", 420}, {"raro", 420},
    {"uncommon", 300}, {"incomum", 300}, {"common", 200}, {"comum", 200},
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
    return { prompt = prompt, part = part, model = model, label = label, rarity = rarity, position = part.Position }
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
    S.route = position
    local started = os.clock()
    local lastMove = 0
    while not S.dead and S.auto and os.clock() - started < timeout do
        local _, humanoid, root = characterParts()
        if not root or not humanoid then break end
        local distance = (position - root.Position).Magnitude
        if distance <= tolerance then
            S.route = nil
            return true
        end
        if not S.fly and os.clock() - lastMove > 0.35 then
            pcall(function() humanoid:MoveTo(position) end)
            lastMove = os.clock()
        end
        task.wait(0.1)
    end
    S.route = nil
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
        setStatus("Procurando Exu de maior raridade identificável...")
        task.spawn(function()
            while S.auto and not S.dead do
                local target = bestExuPrompt()
                if not target then
                    setStatus("Não achei prompt de Exu reconhecível. Tentando de novo...")
                    task.wait(1.5)
                else
                    local name = target.model and target.model.Name or target.prompt.ObjectText
                    setStatus("Indo buscar: " .. tostring(name) .. " (raridade estimada " .. target.rarity .. ")")
                    local reached = travelTo(target.position, math.max(4, target.prompt.MaxActivationDistance * 0.8), 40)
                    if not S.auto then break end
                    if reached and target.prompt.Parent and target.prompt.Enabled then
                        setStatus("Tentando roubar " .. tostring(name) .. "...")
                        activatePrompt(target.prompt)
                        S.usedPrompts[target.prompt] = os.clock()
                        task.wait(1.4)
                        setStatus("Voltando para a base marcada...")
                        local back = travelTo(S.base, 9, 45)
                        if back then
                            tryDepositAtBase()
                            setStatus("Cheguei à base. Confirme se o jogo guardou o Exu.")
                        else
                            setStatus("Não consegui chegar à base. Tente ativar Voo.")
                        end
                        task.wait(1.5)
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
            humanoid.WalkSpeed = 80
        elseif S.savedSpeeds[humanoid] then
            humanoid.WalkSpeed = S.savedSpeeds[humanoid]
            S.savedSpeeds[humanoid] = nil
        end
    end

    if S.fly and root then
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
        if S.route then
            local delta = S.route - root.Position
            if delta.Magnitude > 1 then direction = delta.Unit end
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
        S.velocity.Velocity = direction.Magnitude > 0 and direction.Unit * 80 or Vector3.zero
    elseif S.velocity then
        S.velocity:Destroy()
        S.velocity = nil
    end
end)

setStatus("Exu Hub pronto. Marque sua base primeiro.")
