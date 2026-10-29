-- ExuHub experimental - Roube um Exu (Roblox)
-- Ajustado para o ambiente Luau do Solara: usa getgenv/gethui quando presentes,
-- com fallback para _G/PlayerGui; não depende obrigatoriamente de fireproximityprompt.
-- Auto-roubo/raridade/depósito continuam heurísticos e dependem da estrutura do jogo.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

-- Compatibility: use Solara's documented global environment when available,
-- but keep a safe fallback for environments where getgenv is absent.
local Env = _G
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then Env = result end
end

-- Resume flags are passed by queue_on_teleport when the Hub changes servers.
local resumeHunt = Env.ExuHubResumeHunt == true
local persistedAutoExec = Env.ExuHubAutoExec == true
local persistedScriptUrl = tostring(Env.ExuHubScriptUrl or "")
local persistedServerCursor = tostring(Env.ExuHubServerCursor or "")
local persistedVisitedCsv = tostring(Env.ExuHubVisitedCsv or "")

if Env.ExuHubCleanup then
    pcall(Env.ExuHubCleanup)
end

local S = {
    dead = false,
    speed = false,
    fly = false,
    antiRagdoll = false,
    auto = false,
    serverHunt = false,
    autoExec = persistedAutoExec,
    scriptUrl = persistedScriptUrl,
    serverCursor = persistedServerCursor,
    visitedServers = {},
    base = nil,
    route = nil,
    velocity = nil,
    conn = nil,
    usedPrompts = setmetatable({}, { __mode = "k" }),
    savedSpeeds = setmetatable({}, { __mode = "k" }),
    savedRagdollStates = setmetatable({}, { __mode = "k" }),
    savedCollisions = setmetatable({}, { __mode = "k" }),
    walkSpeedValue = 350,
    flightSpeedValue = 650,
}

for serverId in string.gmatch(persistedVisitedCsv, "[^,]+") do
    S.visitedServers[serverId] = true
end
if game.JobId and game.JobId ~= "" then
    S.visitedServers[game.JobId] = true
end
Env.ExuHubAutoExec = S.autoExec
Env.ExuHubScriptUrl = S.scriptUrl

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

local restoreAntiRagdoll -- forward declaration so cleanup can restore state before the UI closes

local function cleanup()
    if S.dead then return end
    S.dead = true
    S.auto, S.fly, S.speed, S.serverHunt, S.antiRagdoll = false, false, false, false, false
    Env.ExuHubResumeHunt = false
    S.route = nil
    setNoclip(false)
    restoreAntiRagdoll()
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
frame.Size = UDim2.fromOffset(290, 468)
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
status.Size = UDim2.new(1, -20, 0, 52)
status.Position = UDim2.fromOffset(10, 366)
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

-- Anti-ragdoll: disables local ragdoll/falling states and restores original settings when OFF.
-- Some games enforce ragdoll on the server, so this is best-effort only.
local blockedRagdollStates = {
    Enum.HumanoidStateType.Ragdoll,
    Enum.HumanoidStateType.FallingDown,
    Enum.HumanoidStateType.PlatformStanding,
}

local function applyAntiRagdoll(humanoid)
    if not humanoid or not humanoid.Parent then return end
    if not S.savedRagdollStates[humanoid] then
        local saved = { states = {}, platformStand = humanoid.PlatformStand }
        for _, state in ipairs(blockedRagdollStates) do
            local ok, enabled = pcall(function() return humanoid:GetStateEnabled(state) end)
            if ok then saved.states[state] = enabled end
        end
        S.savedRagdollStates[humanoid] = saved
    end
    for _, state in ipairs(blockedRagdollStates) do
        pcall(function() humanoid:SetStateEnabled(state, false) end)
    end
    pcall(function() humanoid.PlatformStand = false end)
    local currentState = humanoid:GetState()
    if currentState == Enum.HumanoidStateType.Ragdoll
        or currentState == Enum.HumanoidStateType.FallingDown
        or currentState == Enum.HumanoidStateType.PlatformStanding then
        pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
end

restoreAntiRagdoll = function()
    for humanoid, saved in pairs(S.savedRagdollStates) do
        if humanoid and humanoid.Parent then
            for state, wasEnabled in pairs(saved.states) do
                pcall(function() humanoid:SetStateEnabled(state, wasEnabled) end)
            end
            pcall(function() humanoid.PlatformStand = saved.platformStand end)
        end
        S.savedRagdollStates[humanoid] = nil
    end
end

local function textLower(...)
    local out = {}
    for _, value in ipairs({...}) do
        if value ~= nil then table.insert(out, tostring(value)) end
    end
    return string.lower(table.concat(out, " "))
end

local rarityWords = {
    {"mega raro", 1550}, {"megararo", 1550}, {"mega-raro", 1550}, {"mega rare", 1550}, {"mega-rare", 1550},
    {"ultra raro", 1500}, {"ultra rare", 1500}, {"super raro", 1480}, {"super rare", 1480},
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

-- A server's rare-item contents are not exposed by Roblox's public server list.
-- This Hub must visit servers one by one and inspect visible prompts locally.
local megaRareTerms = {"mega raro", "megararo", "mega-raro", "mega rare", "mega-rare", "ultra raro", "ultra rare"}

local function findMegaRareTarget()
    for _, item in ipairs(Workspace:GetDescendants()) do
        if item:IsA("ProximityPrompt") and item.Enabled then
            local info = promptInfo(item)
            if info then
                for _, term in ipairs(megaRareTerms) do
                    if info.label:find(term, 1, true) then
                        return info
                    end
                end
            end
        end
    end
    return nil
end

local function encodeVisited()
    local ids = {}
    for id, visited in pairs(S.visitedServers) do
        if visited and id and id ~= "" then table.insert(ids, id) end
    end
    table.sort(ids)
    return table.concat(ids, ",")
end

local function validRawUrl(url)
    return type(url) == "string" and (url:match("^https://") or url:match("^http://")) and #url < 1000
end

local function getHttpBody(url)
    local req = request or http_request or httpRequest
    if type(req) == "function" then
        local ok, response = pcall(req, { Url = url, Method = "GET" })
        if ok and type(response) == "table" and response.Body and (not response.StatusCode or response.StatusCode < 400) then
            return response.Body
        end
    end
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" then return body end
    error("Não foi possível acessar a lista pública de servidores.")
end

local function fetchServerPage(cursor)
    local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId)
        .. "/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"
    if cursor and cursor ~= "" then
        local ok, encoded = pcall(function() return HttpService:UrlEncode(cursor) end)
        url = url .. "&cursor=" .. (ok and encoded or cursor)
    end
    local ok, body = pcall(getHttpBody, url)
    if not ok then return nil, tostring(body) end
    local decodedOk, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if not decodedOk or type(decoded) ~= "table" then return nil, "A API retornou uma resposta inválida." end
    return decoded
end

local function getNextPublicServer()
    local cursor = S.serverCursor
    for _ = 1, 25 do
        local page, err = fetchServerPage(cursor)
        if not page then return nil, err end
        local candidates = {}
        for _, server in ipairs(page.data or {}) do
            if server.id and server.id ~= game.JobId and not S.visitedServers[server.id]
                and tonumber(server.playing) and tonumber(server.maxPlayers)
                and server.playing < server.maxPlayers then
                table.insert(candidates, server)
            end
        end
        if #candidates > 0 then
            table.sort(candidates, function(a, b)
                local ar = a.playing / math.max(1, a.maxPlayers)
                local br = b.playing / math.max(1, b.maxPlayers)
                if ar == br then return a.playing < b.playing end
                return ar < br
            end)
            S.serverCursor = cursor or ""
            return candidates[1]
        end
        if page.nextPageCursor and page.nextPageCursor ~= "" and page.nextPageCursor ~= cursor then
            cursor = page.nextPageCursor
            S.serverCursor = cursor
        else
            return nil, "Não encontrei mais servidores públicos disponíveis nessa busca."
        end
    end
    return nil, "A busca chegou ao limite de páginas nesta tentativa. Tente novamente."
end

local function queueNextLoad(continueHunt)
    if not S.autoExec or not validRawUrl(S.scriptUrl) then
        return false, "Ligue Auto-exec e informe a URL Raw do script para continuar após a troca."
    end
    local queue = queue_on_teleport or queueonteleport
    if type(queue) ~= "function" then
        return false, "Esta versão do executor não disponibilizou queue_on_teleport."
    end
    local code = string.format([[
local E = (getgenv and getgenv()) or _G
E.ExuHubQueuedLoadUntil = os.time() + 12
E.ExuHubAutoExec = true
E.ExuHubScriptUrl = %q
E.ExuHubResumeHunt = %s
E.ExuHubServerCursor = %q
E.ExuHubVisitedCsv = %q
loadstring(game:HttpGet(%q))()
]], S.scriptUrl, continueHunt and "true" or "false", S.serverCursor or "", encodeVisited(), S.scriptUrl)
    local ok, err = pcall(queue, code)
    if not ok then return false, tostring(err) end
    return true
end

local function hopToNextServer(continueHunt)
    if game.JobId and game.JobId ~= "" then S.visitedServers[game.JobId] = true end
    local server, err = getNextPublicServer()
    if not server then
        setStatus("Não consegui listar outro servidor: " .. tostring(err))
        return false
    end
    S.visitedServers[server.id] = true

    if continueHunt then
        local queued, queueErr = queueNextLoad(true)
        if not queued then
            S.visitedServers[server.id] = nil
            setStatus("Para continuar caçando após cada troca, cole a URL Raw e ligue Auto-exec. " .. tostring(queueErr))
            return false
        end
    elseif S.autoExec then
        queueNextLoad(false)
    end

    setStatus("Trocando para servidor com " .. tostring(server.playing) .. "/" .. tostring(server.maxPlayers) .. " jogadores...")
    task.wait(0.6)
    local ok, teleportErr = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
    end)
    if not ok then
        S.visitedServers[server.id] = nil
        setStatus("Falha ao solicitar troca de servidor: " .. tostring(teleportErr))
        return false
    end
    return true
end

local huntButton
local autoExecButton
local scriptUrlBox

local function setHuntEnabled(enabled)
    S.serverHunt = enabled
    Env.ExuHubResumeHunt = enabled
    if huntButton then
        huntButton.Text = "Caçar Mega Raro: " .. (enabled and "ON" or "OFF")
        huntButton.BackgroundColor3 = enabled and Color3.fromRGB(102, 65, 163) or Color3.fromRGB(46, 43, 61)
    end
    if not enabled then
        setStatus("Busca de servidores parada.")
        return
    end
    if not S.autoExec or not validRawUrl(S.scriptUrl) then
        S.serverHunt = false
        Env.ExuHubResumeHunt = false
        if huntButton then huntButton.Text = "Caçar Mega Raro: OFF"; huntButton.BackgroundColor3 = Color3.fromRGB(46,43,61) end
        setStatus("Para caçar em sequência, cole a URL Raw do ExuHub e ligue Auto-exec primeiro.")
        return
    end
    task.spawn(function()
        while S.serverHunt and not S.dead do
            local found = findMegaRareTarget()
            if found then
                S.serverHunt = false
                Env.ExuHubResumeHunt = false
                if huntButton then huntButton.Text = "Caçar Mega Raro: OFF"; huntButton.BackgroundColor3 = Color3.fromRGB(46,43,61) end
                local name = found.model and found.model.Name or found.prompt.ObjectText or "Exu"
                setStatus("Mega Raro detectado neste servidor: " .. tostring(name) .. ". Marque sua base e ligue Auto roubar.")
                return
            end
            setStatus("Nenhum Mega Raro identificável aqui. Buscando outro servidor...")
            local moved = hopToNextServer(true)
            if moved then return end
            S.serverHunt = false
            Env.ExuHubResumeHunt = false
            if huntButton then
                huntButton.Text = "Caçar Mega Raro: OFF"
                huntButton.BackgroundColor3 = Color3.fromRGB(46, 43, 61)
            end
            return
        end
    end)
end

local function installAutoExecLoader()
    if not validRawUrl(S.scriptUrl) then return false, "Cole uma URL Raw HTTPS do ExuHub primeiro." end
    if type(writefile) ~= "function" then return false, "Este executor não disponibilizou writefile para criar o loader." end
    local loader = "local E=(getgenv and getgenv()) or _G; if E.ExuHubQueuedLoadUntil and os.time() < E.ExuHubQueuedLoadUntil then return end; loadstring(game:HttpGet(" .. string.format("%q", S.scriptUrl) .. "))()"
    local ok, err = pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" then
            local exists = false
            pcall(function() exists = isfolder("autoexec") end)
            if not exists then pcall(makefolder, "autoexec") end
        end
        writefile("autoexec/ExuHub.lua", loader)
    end)
    if not ok then return false, tostring(err) end
    return true
end

local function removeAutoExecLoader()
    if type(delfile) == "function" then
        pcall(delfile, "autoexec/ExuHub.lua")
    end
end

local speedButton = makeButton("Velocidade: OFF", 42, function(b)
    updateToggle(b, "Velocidade", "speed")
    if not S.speed then
        local _, h = characterParts()
        if h and S.savedSpeeds[h] then h.WalkSpeed = S.savedSpeeds[h] end
    end
end)

local flyButton = makeButton("Voo: OFF", 78, function(b)
    updateToggle(b, "Voo", "fly")
    if not S.fly and S.velocity then S.velocity:Destroy(); S.velocity = nil end
end)

local autoButton = makeButton("Auto roubar: OFF", 114, function(b)
    if not S.base then
        setStatus("Primeiro clique em Marcar base estando dentro dela.")
        return
    end
    updateToggle(b, "Auto roubar", "auto")
    if S.auto then
        setStatus("Auto Steal: tentando priorizar a maior raridade reconhecível...")
        task.spawn(function()
            while S.auto and not S.dead do
                local target = bestExuPrompt()
                if not target then
                    setStatus("Não achei prompt de Exu reconhecível. Tentando de novo...")
                    task.wait(1.5)
                else
                    local name = target.model and target.model.Name or target.prompt.ObjectText
                    setStatus("Indo até: " .. tostring(name) .. " (raridade estimada " .. target.rarity .. ")")
                    local activationRange = math.clamp(tonumber(target.prompt.MaxActivationDistance) or 6, 3, 10)
                    local reached = teleportTo(target.position, 1.5, activationRange + 3)
                    if not reached and S.auto then
                        setStatus("Teleporte bloqueado; usando voo até o Exu...")
                        reached = travelTo(target.position, math.clamp(activationRange, 3, 6), 18)
                    end
                    if not S.auto then break end
                    if reached and target.prompt.Parent and target.prompt.Enabled then
                        setStatus("Tentando roubar " .. tostring(name) .. "...")
                        activatePrompt(target.prompt)
                        S.usedPrompts[target.prompt] = os.clock()
                        task.wait(0.65)
                        setStatus("Voltando à base...")
                        local back = teleportTo(S.base, 3, 12)
                        if not back and S.auto then
                            setStatus("Teleporte de retorno bloqueado; usando voo para a base...")
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

local baseButton = makeButton("Marcar base atual", 150, function(b)
    local _, _, root = characterParts()
    if not root then setStatus("Personagem ainda não carregou."); return end
    S.base = root.Position
    b.Text = "Base marcada ✓"
    b.BackgroundColor3 = Color3.fromRGB(43, 105, 77)
    setStatus("Base marcada. Ative Auto roubar para começar.")
end)

huntButton = makeButton("Caçar Mega Raro: OFF", 186, function()
    setHuntEnabled(not S.serverHunt)
end)

local hopButton = makeButton("Trocar de servidor", 222, function()
    hopToNextServer(false)
end)

scriptUrlBox = Instance.new("TextBox")
scriptUrlBox.Name = "ScriptRawURL"
scriptUrlBox.Size = UDim2.new(1, -20, 0, 30)
scriptUrlBox.Position = UDim2.fromOffset(10, 258)
scriptUrlBox.BackgroundColor3 = Color3.fromRGB(35, 35, 47)
scriptUrlBox.BorderSizePixel = 0
scriptUrlBox.ClearTextOnFocus = false
scriptUrlBox.PlaceholderText = "Cole aqui a URL Raw do ExuHub.lua"
scriptUrlBox.Text = S.scriptUrl
scriptUrlBox.TextColor3 = Color3.fromRGB(245, 245, 250)
scriptUrlBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 165)
scriptUrlBox.Font = Enum.Font.Gotham
scriptUrlBox.TextSize = 10
scriptUrlBox.TextXAlignment = Enum.TextXAlignment.Left
scriptUrlBox.Parent = frame
Instance.new("UICorner", scriptUrlBox).CornerRadius = UDim.new(0, 7)
local scriptUrlPadding = Instance.new("UIPadding")
scriptUrlPadding.PaddingLeft = UDim.new(0, 8)
scriptUrlPadding.PaddingRight = UDim.new(0, 8)
scriptUrlPadding.Parent = scriptUrlBox
scriptUrlBox.FocusLost:Connect(function()
    S.scriptUrl = string.gsub(scriptUrlBox.Text, "^%s*(.-)%s*$", "%1")
    Env.ExuHubScriptUrl = S.scriptUrl
    if validRawUrl(S.scriptUrl) then
        setStatus("URL salva nesta sessão. Agora você pode ativar Auto-exec.")
    else
        setStatus("Cole o endereço direto HTTPS/Raw do arquivo Lua hospedado.")
    end
end)

autoExecButton = makeButton("Auto-exec: " .. (S.autoExec and "ON" or "OFF"), 294, function(b)
    if S.autoExec then
        if S.serverHunt then setHuntEnabled(false) end
        S.autoExec = false
        Env.ExuHubAutoExec = false
        removeAutoExecLoader()
        b.Text = "Auto-exec: OFF"
        b.BackgroundColor3 = Color3.fromRGB(46, 43, 61)
        setStatus("Auto-exec desligado. O loader autoexec/ExuHub.lua foi removido, se acessível.")
    else
        S.scriptUrl = string.gsub(scriptUrlBox.Text, "^%s*(.-)%s*$", "%1")
        Env.ExuHubScriptUrl = S.scriptUrl
        local ok, err = installAutoExecLoader()
        if not ok then
            setStatus("Não ativei Auto-exec: " .. tostring(err))
            return
        end
        S.autoExec = true
        Env.ExuHubAutoExec = true
        b.Text = "Auto-exec: ON"
        b.BackgroundColor3 = Color3.fromRGB(102, 65, 163)
        setStatus("Loader gravado em autoexec/ExuHub.lua e será enfileirado nas trocas do Hub. Confirme a pasta Auto Execute do Solara.")
    end
end)
if S.autoExec then autoExecButton.BackgroundColor3 = Color3.fromRGB(102, 65, 163) end

local antiRagdollButton = makeButton("Anti-Ragdoll: OFF", 330, function(b)
    updateToggle(b, "Anti-Ragdoll", "antiRagdoll")
    if S.antiRagdoll then
        local _, humanoid = characterParts()
        if humanoid then applyAntiRagdoll(humanoid) end
        setStatus("Anti-Ragdoll ligado. Pode não impedir quedas impostas pelo servidor.")
    else
        restoreAntiRagdoll()
        setStatus("Anti-Ragdoll desligado; estados originais restaurados.")
    end
end)

local closeButton = makeButton("Fechar / parar tudo", 426, cleanup)
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
        if S.antiRagdoll then
            applyAntiRagdoll(humanoid)
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

setStatus("Exu Hub pronto. Anti-Ragdoll pode não bloquear efeitos impostos pelo servidor. Caça Mega Raro lê raridades visíveis nos prompts.")

if resumeHunt then
    task.defer(function()
        if not S.dead then
            S.serverHunt = false
            setHuntEnabled(true)
        end
    end)
end
