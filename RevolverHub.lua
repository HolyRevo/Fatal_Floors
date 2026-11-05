--// REVOLVER HUB V1.4

--// SERVICES
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local VirtualInputManager = game:GetService("VirtualInputManager")

local function getViewportSize()
    local camera = Workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function isTouchLayout()
    local viewport = getViewportSize()
    return UserInputService.TouchEnabled or viewport.X < 700
end

local IS_MOBILE_UI = isTouchLayout()

local KUKIRIN_PLACE_ID = 122840796290491
local IS_KUKIRIN = game.PlaceId == KUKIRIN_PLACE_ID

local LP = Players.LocalPlayer
if not LP then
    return
end

--// ENVIRONMENT
local ENV = _G
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then
        ENV = result
    end
end

if type(ENV.RevolverHubV1) == "table" and type(ENV.RevolverHubV1.Destroy) == "function" then
    pcall(ENV.RevolverHubV1.Destroy)
end

--// BUILD
local BUILD_CHANNEL = "release"
local BUILD_LABEL = "KEY REQUIRED"
local BUILD_MODE_UPDATERS = {}

--// STATE
local RUNNING = true
local CONNECTIONS = {}
local LOGS = {}
local ERROR_TIMES = {}
local HIGHLIGHTS = setmetatable({}, { __mode = "k" })
local OBJECT_COOLDOWNS = setmetatable({}, { __mode = "k" })
local SELL_COOLDOWNS = setmetatable({}, { __mode = "k" })
local MAX_HIGHLIGHTS = 180

local STATS = {
    StartedAt = os.clock(),
    OresCollected = 0,
    ItemsSold = 0,
    FoodsUsed = 0,
    ReviversCollected = 0,
    PickupFails = 0,
    SellFails = 0,
}

local CONFIG = {
    AutoFarm = false,
    AutoSell = false,
    AutoEat = false,
    AutoReviver = false,

    OreESP = false,
    EntityESP = false,
    LocationESP = false,
    PlayerESP = false,

    WalkSpeed = false,
    HipHeight = false,
    JumpPower = false,
    AntiAFK = false,
    NoclipCam = false,
    ESPDirty = true,

    WalkSpeedValue = 24,
    HipHeightValue = 3,
    JumpPowerValue = 65,
    RainbowUI = false,
    UIScaleValue = 1,

    FarmDelay = 0.35,
    SellDelay = 0.50,
    EatDelay = 2.0,

    KukirinAutoWheelie = false,
    KukirinWheelieTapInterval = 0.20,
    KukirinThrottlePulse = 0.14,
    KukirinPlayerESP = false,
    KukirinChams = false,
    KukirinAntiLag = false,
}

local Fluent, FluentWindow, FluentTabs, StatsParagraph, DebugParagraph, OverviewParagraph

--// THEME
local UI_SETTINGS = {
    Scale = 1,
    Rainbow = false,
    Accent = Color3.fromRGB(125, 105, 255),
    Accent2 = Color3.fromRGB(58, 210, 226),
    ThemeName = "Revolver",
}

--// HELPERS
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(CONNECTIONS, connection)
    return connection
end

local function log(message)
    local stamp = os.date("%H:%M:%S")
    table.insert(LOGS, "[" .. stamp .. "] " .. tostring(message))
    if #LOGS > 100 then
        table.remove(LOGS, 1)
    end
    print("[Revolver Hub v1.4] " .. tostring(message))
end

local function safeCall(label, callback)
    local ok, result = pcall(callback)
    if not ok then
        local now = os.clock()
        if not ERROR_TIMES[label] or now - ERROR_TIMES[label] > 5 then
            ERROR_TIMES[label] = now
            log(label .. " error: " .. tostring(result))
        end
        return false, result
    end
    return true, result
end

local function getGuiParent()
    if type(gethui) == "function" then
        local ok, result = pcall(gethui)
        if ok and result then
            return result
        end
    end
    return CoreGui
end

local function mountGui(gui)
    local parent = getGuiParent()
    local ok = pcall(function()
        gui.Parent = parent
    end)
    if not ok or not gui.Parent then
        pcall(function()
            gui.Parent = LP:WaitForChild("PlayerGui")
        end)
    end
end

local function tween(object, duration, properties, style, direction)
    local info = TweenInfo.new(
        duration or 0.2,
        style or Enum.EasingStyle.Quint,
        direction or Enum.EasingDirection.Out
    )
    local animation = TweenService:Create(object, info, properties)
    animation:Play()
    return animation
end

--// AUTH
local SUPABASE_FUNCTION_URL = "https://fikrsilwzmlegjtkqglc.supabase.co/functions/v1/fatalfloors-auth"
local SUPABASE_PUBLISHABLE_KEY = "sb_publishable_6vEJtA84VBevLYzbpDwzZw_H8emmQ60"
local DEVICE_ID_FILE = "RevolverHubDevice.txt"
local LEGACY_DEVICE_ID_FILE = "FatalFloorsHubDevice.txt"
local KEY_PROVIDER = "app" -- LootLabs-issued app keys
local API_CONFIG = nil

local function getDeviceId()
    local deviceId = ENV.RevolverHubV1_DeviceId or ENV.FatalFloorsV1_DeviceId
    if type(deviceId) == "string" and #deviceId >= 8 then
        return deviceId
    end
    if type(isfile) == "function" and type(readfile) == "function" then
        local ok, value = pcall(function()
            if isfile(DEVICE_ID_FILE) then return readfile(DEVICE_ID_FILE) end
            if LEGACY_DEVICE_ID_FILE and isfile(LEGACY_DEVICE_ID_FILE) then return readfile(LEGACY_DEVICE_ID_FILE) end
        end)
        if ok and type(value) == "string" and #value >= 8 then
            ENV.RevolverHubV1_DeviceId = value
            return value
        end
    end
    deviceId = HttpService:GenerateGUID(false) .. HttpService:GenerateGUID(false)
    ENV.RevolverHubV1_DeviceId = deviceId
    if type(writefile) == "function" then
        pcall(writefile, DEVICE_ID_FILE, deviceId)
    end
    return deviceId
end

local DEVICE_ID = getDeviceId()

local ACTIVE_KEY_FILE = "RevolverHubAccessKey.txt"
local LEGACY_ACTIVE_KEY_FILE = "FatalFloorsHubAccessKey.txt"
local ACTIVE_ACCESS_KEY = nil
local ACTIVE_KEY_IS_OWNER = false

local function loadSavedAccessKey()
    local cached = ENV.RevolverHubV1_ActiveKey or ENV.FatalFloorsV1_ActiveKey
    if type(cached) == "string" and #cached > 0 then
        ACTIVE_ACCESS_KEY = cached
        return cached
    end
    if type(readfile) == "function" then
        local ok, value = pcall(function()
            if type(isfile) == "function" then
                if isfile(ACTIVE_KEY_FILE) then return readfile(ACTIVE_KEY_FILE) end
                if LEGACY_ACTIVE_KEY_FILE and isfile(LEGACY_ACTIVE_KEY_FILE) then return readfile(LEGACY_ACTIVE_KEY_FILE) end
                return nil
            end
            local okNew, valueNew = pcall(readfile, ACTIVE_KEY_FILE)
            if okNew and type(valueNew) == "string" and #valueNew > 0 then return valueNew end
            return readfile(LEGACY_ACTIVE_KEY_FILE)
        end)
        if ok and type(value) == "string" and #value > 0 then
            ACTIVE_ACCESS_KEY = value
            ENV.RevolverHubV1_ActiveKey = value
            return value
        end
    end
    return nil
end

local function saveActiveAccessKey(value)
    if type(value) ~= "string" or value == "" then
        return false, "Key is empty."
    end
    ACTIVE_ACCESS_KEY = value
    ENV.RevolverHubV1_ActiveKey = value
    if type(writefile) == "function" then
        local ok, err = pcall(writefile, ACTIVE_KEY_FILE, value)
        if not ok then
            return false, "Saved for this executor session only: " .. tostring(err)
        end
        return true, "Saved to " .. ACTIVE_KEY_FILE
    end
    return false, "Executor has no writefile; key is saved for this session only."
end

local function apiRequest(method, query, payload)
    local url = SUPABASE_FUNCTION_URL .. (query or "")
    local options = {
        Url = url,
        Method = method,
        Headers = {
            ["apikey"] = SUPABASE_PUBLISHABLE_KEY,
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
        },
    }
    if payload then
        options.Body = HttpService:JSONEncode(payload)
    end

    local requestFunction = nil
    if type(syn) == "table" and type(syn.request) == "function" then
        requestFunction = syn.request
    elseif type(http) == "table" and type(http.request) == "function" then
        requestFunction = http.request
    elseif type(http_request) == "function" then
        requestFunction = http_request
    elseif type(request) == "function" then
        requestFunction = request
    end

    local ok, response
    if requestFunction then
        ok, response = pcall(requestFunction, options)
    else
        ok, response = pcall(function()
            return HttpService:RequestAsync(options)
        end)
    end
    if not ok or type(response) ~= "table" then
        return nil, 0, "HTTP request failed: " .. tostring(response)
    end

    local statusCode = tonumber(response.StatusCode or response.status_code or response.Status or 0) or 0
    local responseBody = response.Body or response.body or ""
    local decodedOk, decoded = pcall(function()
        return HttpService:JSONDecode(responseBody)
    end)
    if not decodedOk then
        return nil, statusCode, "Backend returned invalid JSON."
    end
    return decoded, statusCode, nil
end

local function copyToClipboard(value)
    if type(value) ~= "string" or value == "" then return false end
    if type(setclipboard) == "function" then
        return pcall(setclipboard, value)
    elseif type(toclipboard) == "function" then
        return pcall(toclipboard, value)
    end
    return false
end

local function loadProviderConfig()
    local data, status, err = apiRequest("GET", "?action=config")
    if data and status >= 200 and status < 300 and data.ok then
        API_CONFIG = data
        return true
    end
    log("Provider config unavailable: " .. tostring(err or (data and data.message) or status))
    return false
end

local function validateKey(candidate)
    candidate = tostring(candidate or ""):match("^%s*(.-)%s*$")
    if not candidate or candidate == "" then
        return false, "Enter an access key.", false
    end
    local data, status, err = apiRequest("POST", "", {
        action = "validate",
        provider = KEY_PROVIDER,
        key = candidate,
        deviceId = DEVICE_ID,
    })
    if data and data.valid == true and status >= 200 and status < 300 then
        local isOwner = data.owner == true
        return true, data.message or "Access granted", isOwner
    end
    return false, (data and data.message) or err or ("Validation failed (HTTP " .. tostring(status) .. ")"), false
end

local KEY_GUI = Instance.new("ScreenGui")
KEY_GUI.Name = "RevolverHubV1_KeyGate"
KEY_GUI.ResetOnSpawn = false
KEY_GUI.IgnoreGuiInset = true
mountGui(KEY_GUI)

local keyBackdrop = Instance.new("Frame")
keyBackdrop.Name = "Backdrop"
keyBackdrop.Size = UDim2.fromScale(1, 1)
keyBackdrop.BackgroundColor3 = Color3.fromRGB(12, 13, 15)
keyBackdrop.BackgroundTransparency = 0.10
keyBackdrop.BorderSizePixel = 0
keyBackdrop.Parent = KEY_GUI

local keyCard = Instance.new("Frame")
keyCard.Name = "KeyCard"
keyCard.AnchorPoint = Vector2.new(0.5, 0.5)
keyCard.Position = UDim2.fromScale(0.5, 0.5)
keyCard.Size = UDim2.fromOffset(430, 365)
keyCard.BackgroundColor3 = Color3.fromRGB(35, 37, 41)
keyCard.BorderSizePixel = 0
keyCard.Parent = keyBackdrop
Instance.new("UICorner", keyCard).CornerRadius = UDim.new(0, 16)

local keyCardScale = Instance.new("UIScale")
keyCardScale.Parent = keyCard

local function updateKeyCardScale()
    local viewport = getViewportSize()
    local fit = math.min(1, (viewport.X - 24) / 430, (viewport.Y - 24) / 365)
    keyCardScale.Scale = math.clamp(fit, 0.52, 1)
end

updateKeyCardScale()
local keyCamera = Workspace.CurrentCamera
if keyCamera then
    connect(keyCamera:GetPropertyChangedSignal("ViewportSize"), updateKeyCardScale)
end
connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
    task.defer(function()
        local camera = Workspace.CurrentCamera
        if camera then
            connect(camera:GetPropertyChangedSignal("ViewportSize"), updateKeyCardScale)
        end
        updateKeyCardScale()
    end)
end)

local keyStroke = Instance.new("UIStroke")
keyStroke.Color = Color3.fromRGB(132, 136, 143)
keyStroke.Transparency = 0.12
keyStroke.Thickness = 1.3
keyStroke.Parent = keyCard

local keyHeader = Instance.new("Frame")
keyHeader.Size = UDim2.new(1, 0, 0, 66)
keyHeader.BackgroundColor3 = Color3.fromRGB(75, 79, 85)
keyHeader.BorderSizePixel = 0
keyHeader.Parent = keyCard
Instance.new("UICorner", keyHeader).CornerRadius = UDim.new(0, 16)

local headerGradient = Instance.new("UIGradient")
headerGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(105, 110, 118)),
    ColorSequenceKeypoint.new(0.55, Color3.fromRGB(62, 66, 73)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(105, 110, 118)),
})
headerGradient.Parent = keyHeader

local keyGradientAnimation = TweenService:Create(
    headerGradient,
    TweenInfo.new(12, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
    { Rotation = 360 }
)
keyGradientAnimation:Play()

local keyTitle = Instance.new("TextLabel")
keyTitle.BackgroundTransparency = 1
keyTitle.Position = UDim2.fromOffset(20, 12)
keyTitle.Size = UDim2.new(1, -40, 0, 25)
keyTitle.Font = Enum.Font.GothamBold
keyTitle.Text = "REVOLVER HUB"
keyTitle.TextColor3 = Color3.new(1, 1, 1)
keyTitle.TextSize = 18
keyTitle.TextXAlignment = Enum.TextXAlignment.Left
keyTitle.Parent = keyHeader

local keySubtitle = Instance.new("TextLabel")
keySubtitle.BackgroundTransparency = 1
keySubtitle.Position = UDim2.fromOffset(21, 37)
keySubtitle.Size = UDim2.new(1, -42, 0, 17)
keySubtitle.Font = Enum.Font.Gotham
keySubtitle.Text = "V1.4 · SINGLE FILE · KEY-SELECTED BUILD"
keySubtitle.TextColor3 = Color3.fromRGB(222, 224, 228)
keySubtitle.TextSize = 10
keySubtitle.TextXAlignment = Enum.TextXAlignment.Left
keySubtitle.Parent = keyHeader

local keyPrompt = Instance.new("TextLabel")
keyPrompt.BackgroundTransparency = 1
keyPrompt.Position = UDim2.fromOffset(22, 82)
keyPrompt.Size = UDim2.new(1, -44, 0, 20)
keyPrompt.Font = Enum.Font.GothamMedium
keyPrompt.Text = "Owner key → Owner Beta · Normal key → Public Release"
keyPrompt.TextColor3 = Color3.fromRGB(215, 218, 223)
keyPrompt.TextSize = 12
keyPrompt.TextXAlignment = Enum.TextXAlignment.Left
keyPrompt.Parent = keyCard

local function applyBuildForKey(isOwner)
    BUILD_CHANNEL = isOwner and "owner-beta" or "release"
    BUILD_LABEL = isOwner and "OWNER BETA" or "PUBLIC RELEASE"
    ENV.RevolverHubV1_Build = BUILD_CHANNEL

    keyTitle.Text = "REVOLVER HUB · " .. BUILD_LABEL
    keySubtitle.Text = "V1.4 · " .. BUILD_LABEL .. " · FLUENT EDITION"
    keyPrompt.Text = isOwner
        and "Owner key detected · Owner Beta enabled"
        or "Release key detected · Public Release enabled"

    for _, updater in ipairs(BUILD_MODE_UPDATERS) do
        pcall(updater, BUILD_LABEL, BUILD_CHANNEL)
    end
    if type(ENV.RevolverHubV1) == "table" then
        ENV.RevolverHubV1.Build = BUILD_CHANNEL
        ENV.RevolverHubV1.Version = "1.4-" .. BUILD_CHANNEL
    end
end

local keyBox = Instance.new("TextBox")
keyBox.Position = UDim2.fromOffset(22, 111)
keyBox.Size = UDim2.new(1, -44, 0, 43)
keyBox.BackgroundColor3 = Color3.fromRGB(52, 55, 61)
keyBox.BorderSizePixel = 0
keyBox.ClearTextOnFocus = false
keyBox.Font = Enum.Font.Gotham
keyBox.PlaceholderText = "Access key..."
keyBox.PlaceholderColor3 = Color3.fromRGB(157, 161, 168)
keyBox.Text = loadSavedAccessKey() or ""
keyBox.TextColor3 = Color3.new(1, 1, 1)
keyBox.TextSize = 13
keyBox.Parent = keyCard
Instance.new("UICorner", keyBox).CornerRadius = UDim.new(0, 9)

local keyButton = Instance.new("TextButton")
keyButton.Position = UDim2.fromOffset(22, 166)
keyButton.Size = UDim2.new(1, -44, 0, 40)
keyButton.BackgroundColor3 = Color3.fromRGB(91, 96, 104)
keyButton.BorderSizePixel = 0
keyButton.AutoButtonColor = false
keyButton.Font = Enum.Font.GothamBold
keyButton.Text = "UNLOCK HUB"
keyButton.TextColor3 = Color3.new(1, 1, 1)
keyButton.TextSize = 11
keyButton.Parent = keyCard
Instance.new("UICorner", keyButton).CornerRadius = UDim.new(0, 9)

local keyMessage = Instance.new("TextLabel")
keyMessage.BackgroundTransparency = 1
keyMessage.Position = UDim2.fromOffset(22, 215)
keyMessage.Size = UDim2.new(1, -44, 0, 20)
keyMessage.Font = Enum.Font.Gotham
keyMessage.Text = "LootLabs verified license · keys are device-bound"
keyMessage.TextColor3 = Color3.fromRGB(143, 151, 177)
keyMessage.TextSize = 9
keyMessage.TextXAlignment = Enum.TextXAlignment.Center
keyMessage.Parent = keyCard

local providerButtons = {}
local lootLabsButton = Instance.new("TextButton")
lootLabsButton.Position = UDim2.fromOffset(22, 246)
lootLabsButton.Size = UDim2.new(1, -44, 0, 38)
lootLabsButton.BackgroundColor3 = Color3.fromRGB(91, 96, 104)
lootLabsButton.BorderSizePixel = 0
lootLabsButton.AutoButtonColor = false
lootLabsButton.Font = Enum.Font.GothamBold
lootLabsButton.Text = "GET LOOTLABS KEY LINK"
lootLabsButton.TextColor3 = Color3.new(1, 1, 1)
lootLabsButton.TextSize = 10
lootLabsButton.Parent = keyCard
Instance.new("UICorner", lootLabsButton).CornerRadius = UDim.new(0, 8)
providerButtons.lootlabs = lootLabsButton

local providerHint = Instance.new("TextLabel")
providerHint.BackgroundTransparency = 1
providerHint.Position = UDim2.fromOffset(22, 293)
providerHint.Size = UDim2.new(1, -44, 0, 42)
providerHint.Font = Enum.Font.Gotham
providerHint.Text = "Request your personal LootLabs link, complete every required task, then paste the generated FF key above."
providerHint.TextColor3 = Color3.fromRGB(143, 151, 177)
providerHint.TextSize = 8
providerHint.TextWrapped = true
providerHint.Parent = keyCard

local function refreshProviderConfig()
    if loadProviderConfig() then
        providerHint.Text = API_CONFIG.lootlabsEnabled
            and "LootLabs is ready. Complete every task to receive your key."
            or "LootLabs is not configured on the server yet."
    else
        providerHint.Text = "Backend not reachable. Check executor HTTP requests and the Supabase setup."
    end
end

task.spawn(refreshProviderConfig)

connect(providerButtons.lootlabs.Activated, function()
    keyMessage.Text = "Creating your personal LootLabs link..."
    keyMessage.TextColor3 = Color3.fromRGB(223, 227, 247)
    task.spawn(function()
        local data, status, err = apiRequest("POST", "", { action = "create-lootlabs" })
        if data and data.ok and data.url then
            if copyToClipboard(data.url) then
                keyMessage.Text = "LootLabs link copied. Complete it in your browser."
                keyMessage.TextColor3 = Color3.fromRGB(97, 242, 163)
            else
                keyMessage.Text = "Link created, but clipboard is unavailable: " .. tostring(data.url)
                keyMessage.TextColor3 = Color3.fromRGB(255, 204, 105)
            end
        else
            keyMessage.Text = (data and data.message) or err or ("LootLabs error " .. tostring(status))
            keyMessage.TextColor3 = Color3.fromRGB(255, 100, 114)
        end
    end)
end)

local KEY_UNLOCKED = false
local KEY_VALIDATING = false
local KEY_CHANGE_MODE = false

local function submitKey()
    if (KEY_UNLOCKED and not KEY_CHANGE_MODE) or KEY_VALIDATING then return end
    KEY_VALIDATING = true
    keyButton.Text = KEY_CHANGE_MODE and "CHECKING NEW KEY..." or "CHECKING KEY..."
    keyMessage.Text = "Checking with the secure license server..."
    keyMessage.TextColor3 = Color3.fromRGB(223, 227, 247)

    task.spawn(function()
        local candidate = tostring(keyBox.Text or ""):match("^%s*(.-)%s*$")
        local valid, reason, isOwner = validateKey(candidate)
        KEY_VALIDATING = false
        if valid then
            local wasChanging = KEY_CHANGE_MODE
            ACTIVE_KEY_IS_OWNER = isOwner == true
            applyBuildForKey(ACTIVE_KEY_IS_OWNER)
            local saved, saveMessage = saveActiveAccessKey(candidate)
            KEY_UNLOCKED = true
            KEY_CHANGE_MODE = false
            keyButton.Text = wasChanging and "KEY SWITCHED" or "ACCESS GRANTED"
            keyMessage.Text = reason .. (saved and " · key saved" or " · " .. tostring(saveMessage))
            keyMessage.TextColor3 = Color3.fromRGB(97, 242, 163)
            if KEY_GUI and KEY_GUI.Parent then
                KEY_GUI.Enabled = false
            end
            if wasChanging then
                notify("Access key switched and saved", "success")
                log("Access key changed; owner=" .. tostring(ACTIVE_KEY_IS_OWNER))
            end
        else
            keyButton.Text = KEY_CHANGE_MODE and "VERIFY & SWITCH KEY" or "UNLOCK HUB"
            keyMessage.Text = reason .. (KEY_CHANGE_MODE and " · current key remains active" or "")
            keyMessage.TextColor3 = Color3.fromRGB(255, 100, 114)
            local original = keyCard.Position
            for _ = 1, 2 do
                if not keyCard.Parent then break end
                tween(keyCard, 0.045, { Position = original + UDim2.fromOffset(6, 0) }, Enum.EasingStyle.Linear)
                task.wait(0.05)
                tween(keyCard, 0.045, { Position = original - UDim2.fromOffset(6, 0) }, Enum.EasingStyle.Linear)
                task.wait(0.05)
            end
            if keyCard.Parent then tween(keyCard, 0.06, { Position = original }, Enum.EasingStyle.Linear) end
        end
    end)
end

local function beginKeySwitch()
    if not KEY_UNLOCKED then return end
    KEY_CHANGE_MODE = true
    KEY_GUI.DisplayOrder = 10000
    KEY_GUI.Enabled = true
    keyTitle.Text = "SWITCH ACCESS KEY"
    keySubtitle.Text = "CURRENT BUILD · " .. BUILD_LABEL
    keyPrompt.Text = "Enter another valid key. Your build changes automatically after validation."
    keyBox.Text = ""
    keyButton.Text = "VERIFY & SWITCH KEY"
    keyMessage.Text = "Your current key stays active unless the new key validates."
    keyMessage.TextColor3 = Color3.fromRGB(143, 151, 177)
    keyBox:CaptureFocus()
end
connect(keyButton.Activated, submitKey)
connect(keyBox.FocusLost, function(enterPressed)
    if enterPressed then
        submitKey()
    end
end)
connect(keyButton.MouseEnter, function()
    tween(keyButton, 0.15, { BackgroundColor3 = Color3.fromRGB(121, 126, 134) })
end)
connect(keyButton.MouseLeave, function()
    tween(keyButton, 0.15, { BackgroundColor3 = Color3.fromRGB(91, 96, 104) })
end)

local previouslySavedKey = loadSavedAccessKey()
if previouslySavedKey then
    keyBox.Text = previouslySavedKey
    keyMessage.Text = "Saved key found. Validating automatically..."
    task.spawn(submitKey)
end

repeat
    task.wait(0.1)
until KEY_UNLOCKED or not RUNNING

if not KEY_UNLOCKED then
    return
end

--// CHARACTER
local function getCharacter()
    return LP.Character
end

local function getHumanoid()
    local character = getCharacter()
    return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getRoot()
    local character = getCharacter()
    return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function getBackpack()
    return LP:FindFirstChildOfClass("Backpack")
end

local function getAllTools()
    local found = {}
    local seen = {}
    local backpack = getBackpack()
    local character = getCharacter()

    local function collect(container)
        if not container then return end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") and not seen[item] then
                seen[item] = true
                table.insert(found, item)
            end
        end
    end

    collect(backpack)
    collect(character)
    return found
end

local function inventoryCounts()
    local counts = {}
    for _, tool in ipairs(getAllTools()) do
        counts[tool.Name] = (counts[tool.Name] or 0) + 1
    end
    return counts
end

local function countTool(name)
    local count = 0
    for _, tool in ipairs(getAllTools()) do
        if tool.Name == name then
            count = count + 1
        end
    end
    return count
end

local function countOreTools()
    local count = 0
    for _, tool in ipairs(getAllTools()) do
        if string.find(string.lower(tool.Name), "iron", 1, true)
            or string.find(string.lower(tool.Name), "jade", 1, true)
            or string.find(string.lower(tool.Name), "amethyst", 1, true)
            or string.find(string.lower(tool.Name), "gold", 1, true)
            or string.find(string.lower(tool.Name), "amber", 1, true) then
            count = count + 1
        end
    end
    return count
end

local function equipTool(tool)
    local humanoid = getHumanoid()
    if not humanoid or not tool or not tool.Parent then
        return false
    end

    if tool.Parent == getCharacter() then
        return true
    end

    local ok = pcall(function()
        humanoid:EquipTool(tool)
    end)
    return ok and tool.Parent == getCharacter()
end

local function getObjectPosition(object)
    if not object then
        return nil
    end

    if object:IsA("BasePart") then
        return object.Position
    end

    if object:IsA("Model") then
        local ok, pivot = pcall(function()
            return object:GetPivot()
        end)
        if ok and pivot then
            return pivot.Position
        end
    end

    local part = object:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local EGG_PLATFORM

local function clearEggPlatform()
    if EGG_PLATFORM then
        pcall(function() EGG_PLATFORM:Destroy() end)
        EGG_PLATFORM = nil
    end
end

local function isGiantEgg(name)
    local lowered = string.lower(tostring(name or "")):gsub("[%s_%-]", "")
    return string.find(lowered, "giantegg", 1, true) ~= nil
end

local function teleportNear(position)
    local root = getRoot()
    if not root or typeof(position) ~= "Vector3" then
        clearEggPlatform()
        return false
    end

    clearEggPlatform()
    local ok = pcall(function()
        root.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0))
    end)
    return ok
end

local function teleportBelowEgg(position)
    local root = getRoot()
    if not root or typeof(position) ~= "Vector3" then
        return false
    end

    local destination = position - Vector3.new(0, 2.5, 0)
    local ok = pcall(function()
        if not EGG_PLATFORM or not EGG_PLATFORM.Parent then
            EGG_PLATFORM = Instance.new("Part")
            EGG_PLATFORM.Name = "RevolverHub_EggPlatform"
            EGG_PLATFORM.Size = Vector3.new(8, 1, 8)
            EGG_PLATFORM.Anchored = true
            EGG_PLATFORM.CanCollide = true
            EGG_PLATFORM.CanTouch = false
            EGG_PLATFORM.CanQuery = false
            EGG_PLATFORM.Transparency = 0.3
            EGG_PLATFORM.Material = Enum.Material.SmoothPlastic
            EGG_PLATFORM.Color = Color3.fromRGB(135, 135, 145)
            EGG_PLATFORM.Parent = Workspace
        end
        EGG_PLATFORM.CFrame = CFrame.new(destination - Vector3.new(0, 3.5, 0))
        root.CFrame = CFrame.new(destination)
    end)
    if not ok then clearEggPlatform() end
    return ok
end

local function teleportForPickup(position, name)
    if isGiantEgg(name) then
        return teleportBelowEgg(position)
    end
    return teleportNear(position)
end

--// ITEMS
local ORE_NAMES = {
    "iron",
    "jade",
    "amethyst",
    "gold",
    "amber",
}

local FOOD_NAMES = {
    "food", "apple", "berry", "berries", "mushroom", "meat", "fish",
    "meal", "bread", "steak", "carrot", "ham", "egg", "kiwi",
    "ration", "soup", "fruit", "cooked", "giantegg", "gianteggs",
}

local GRIND = {
    MapOriginalPivot = nil,
    MapLiftedModel = nil,
    MapLifted = false,
    MapSafeHeight = 20,
}

function GRIND.foodHealAmount(name)
    local lowered = string.lower(tostring(name or "")):gsub("[%s_%-]", "")
    if string.find(lowered, "egg", 1, true) then return nil end
    if string.find(lowered, "cookedcarrot", 1, true) then return 30 end
    if string.find(lowered, "carrot", 1, true) then return 15 end
    if string.find(lowered, "cookedham", 1, true) then return 80 end
    if string.find(lowered, "ham", 1, true) then return 40 end
    return nil
end

function GRIND.preferredFoodHeal()
    local humanoid = getHumanoid()
    if not humanoid or humanoid.Health <= 0 then return nil end

    local missing = math.max(0, humanoid.MaxHealth - humanoid.Health)
    if missing < 15 then return nil end

    for _, heal in ipairs({ 15, 30, 40, 80 }) do
        if heal >= missing then
            if heal <= missing * 2 then return heal end
            return nil
        end
    end

    return 80
end

function GRIND.shouldPickupFood(name)
    local preferred = GRIND.preferredFoodHeal()
    return preferred ~= nil and GRIND.foodHealAmount(name) == preferred
end

function GRIND.isTrapObject(object)
    if not object then return false end
    local ownName = string.lower(tostring(object.Name or "")):gsub("[%s_%-]", "")
    local current = object
    while current and current ~= Workspace do
        local name = string.lower(tostring(current.Name or "")):gsub("[%s_%-]", "")
        if string.find(name, "trap", 1, true) then return true end
        if current:GetAttribute("IsTrap") == true
            or current:GetAttribute("Trap") == true
            or current:GetAttribute("DangerousTrap") == true then
            return true
        end
        current = current.Parent
    end
    if string.find(ownName, "ham", 1, true) or string.find(ownName, "gold", 1, true) or string.find(ownName, "carrot", 1, true) then
        for _, descendant in ipairs(object:GetDescendants()) do
            local name = string.lower(tostring(descendant.Name or "")):gsub("[%s_%-]", "")
            if string.find(name, "trap", 1, true) then return true end
        end
    end
    return false
end

local ENTITY_WORDS = { "monster", "enemy", "entity", "creature", "boss" }
local LOCATION_WORDS = { "spawn", "exit", "shop", "station", "elevator", "safezone", "safe_zone" }

local function containsAny(name, words)
    local lowered = string.lower(tostring(name or ""))
    for _, word in ipairs(words) do
        if string.find(lowered, word, 1, true) then
            return true
        end
    end
    return false
end

local function isOre(name)
    local lowered = string.lower(tostring(name or "")):gsub("[%s_%-]", "")
    if string.find(lowered, "trap", 1, true) then return false end
    return containsAny(name, ORE_NAMES)
end

local function isFood(name)
    local lowered = string.lower(tostring(name or "")):gsub("[%s_%-]", "")
    if string.find(lowered, "trap", 1, true) then return false end
    if isGiantEgg(name) then return true end
    return containsAny(name, FOOD_NAMES)
end


local function hasNewOre(before)
    local after = inventoryCounts()
    for name, amount in pairs(after) do
        if isOre(name) and amount > (before[name] or 0) then
            return true
        end
    end
    return false
end

local function findFood()
    local preferred = GRIND.preferredFoodHeal()
    if not preferred then return nil end

    for _, tool in ipairs(getAllTools()) do
        if not GRIND.isTrapObject(tool) and isFood(tool.Name)
            and GRIND.foodHealAmount(tool.Name) == preferred then
            return tool
        end
    end
    return nil
end

local function findWorldFood()
    local preferred = GRIND.preferredFoodHeal()
    if not preferred then return nil end

    local function scanFolder(folder)
        if not folder then return nil end
        for _, object in ipairs(folder:GetChildren()) do
            if (object:IsA("BasePart") or object:IsA("Model") or object:IsA("Tool"))
                and not GRIND.isTrapObject(object)
                and isFood(object.Name)
                and GRIND.foodHealAmount(object.Name) == preferred
                and (OBJECT_COOLDOWNS[object] or 0) <= os.clock() then
                return object
            end
        end
        return nil
    end

    local generated = Workspace:FindFirstChild("ProcGenGenerated")
    local procItems = generated and generated:FindFirstChild("ProcGenItems")
    local found = scanFolder(procItems)
    if found then return found end

    local rootCarrot = Workspace:FindFirstChild("Carrot")
    if rootCarrot and not GRIND.isTrapObject(rootCarrot)
        and GRIND.foodHealAmount(rootCarrot.Name) == preferred
        and (OBJECT_COOLDOWNS[rootCarrot] or 0) <= os.clock() then
        return rootCarrot
    end
    return nil
end

--// PROMPTS
local function findPrompt(object)
    if not object then
        return nil
    end

    if object:IsA("ProximityPrompt") then
        return object
    end

    for _, descendant in ipairs(object:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") and descendant.Enabled then
            return descendant
        end
    end
    return nil
end

local function activatePrompt(prompt)
    if not prompt or not prompt.Parent or not prompt.Enabled then
        return false
    end

    local ok = pcall(function()
        prompt:InputHoldBegin()
        local hold = math.max(0.1, tonumber(prompt.HoldDuration) or 0.1)
        task.wait(hold)
        prompt:InputHoldEnd()
    end)
    return ok
end

--// SELL
local function getSellSpot()
    local tiles = Workspace:FindFirstChild("PlacedTiles")
    local station = tiles and tiles:FindFirstChild("SellStation")
    if not station then return nil, nil end
    local spot = station:FindFirstChild("SellingSpot") or station
    return spot, findPrompt(spot) or findPrompt(station)
end

local function nextOreTool()
    for _, tool in ipairs(getAllTools()) do
        if not GRIND.isTrapObject(tool) and not isFood(tool.Name)
            and isOre(tool.Name) and (SELL_COOLDOWNS[tool] or 0) <= os.clock() then
            return tool
        end
    end
    return nil
end

local function sellTool(tool)
    if not tool or not tool.Parent then
        return false, "Ore tool missing"
    end
    if isFood(tool.Name) then
        return false, "Food is never sold"
    end

    local spot, prompt = getSellSpot()
    local position = getObjectPosition(spot)
    if not spot or not prompt or not position then
        return false, "Sell station, position or prompt missing"
    end

    local beforeTotal = countOreTools()
    if not teleportNear(position) then
        return false, "Could not move to sell station"
    end

    task.wait(0.18)
    if not equipTool(tool) then
        return false, "Could not equip ore"
    end

    task.wait(0.1)
    if not activatePrompt(prompt) then
        return false, "Sell prompt activation failed"
    end

    local deadline = os.clock() + 2.5
    repeat
        task.wait(0.1)
        local currentTotal = countOreTools()
        if currentTotal < beforeTotal then
            local sold = beforeTotal - currentTotal
            STATS.ItemsSold = STATS.ItemsSold + sold
            return true
        end
    until os.clock() >= deadline or not RUNNING

    return false, "Inventory did not decrease after sale"
end

--// EAT
local function getFoodRemote()
    local remote = ReplicatedStorage:FindFirstChild("FoodEatRequest", true)
    if remote and remote:IsA("RemoteEvent") then
        return remote
    end
    return nil
end

local function eatFood(allowWorldPickup)
    local preferredHeal = GRIND.preferredFoodHeal()
    if not preferredHeal then
        return false, "Food not needed yet (15 HP minimum) or no suitable food tier"
    end

    local food = findFood()
    local worldFood = nil
    local beforeHealth = nil
    local humanoid = getHumanoid()
    if humanoid then
        beforeHealth = humanoid.Health
    end

    if not food then
        if allowWorldPickup == false then
            return false, "Preferred food was not added to inventory"
        end
        worldFood = findWorldFood()
        if not worldFood then
            return false, "No suitable food found in inventory or world"
        end

        local position = getObjectPosition(worldFood)
        local prompt = findPrompt(worldFood)
        if not position or not prompt then
            OBJECT_COOLDOWNS[worldFood] = os.clock() + 5
            return false, "World food prompt or position missing"
        end
        if not teleportForPickup(position, worldFood.Name) then
            OBJECT_COOLDOWNS[worldFood] = os.clock() + 5
            return false, "Could not move to world food"
        end

        task.wait(0.18)
        if not RUNNING or not CONFIG.AutoEat then
            return false, "Auto Eat disabled"
        end
        if not activatePrompt(prompt) then
            OBJECT_COOLDOWNS[worldFood] = os.clock() + 5
            return false, "World food prompt activation failed"
        end

        OBJECT_COOLDOWNS[worldFood] = os.clock() + 8
        task.wait(0.25)

        local tiles = Workspace:FindFirstChild("PlacedTiles")
        local map = tiles and tiles:FindFirstChild("Map")
        if map then
            local mapOk, mapPivot = pcall(function() return map:GetPivot() end)
            if mapOk and mapPivot then
                teleportNear(mapPivot.Position)
                task.wait(0.25)
            end
        end

        food = findFood()
    end

    if not food then
        return false, "Preferred food was not added to inventory; nothing was eaten"
    end
    if not equipTool(food) then
        return false, "Could not equip preferred food"
    end
    task.wait(0.12)

    local remote = getFoodRemote()
    local beforeCount = food and countTool(food.Name) or 0
    local ok, err

    if remote then
        ok, err = pcall(function()
            remote:FireServer()
        end)
    elseif food then
        ok, err = pcall(function()
            food:Activate()
        end)
    else
        return false, "FoodEatRequest remote is missing"
    end

    if not ok then
        return false, "Food request failed: " .. tostring(err)
    end

    task.wait(0.35)
    local toolConsumed = food and countTool(food.Name) < beforeCount
    local worldPickupConsumed = worldFood and not worldFood.Parent
    local currentHumanoid = getHumanoid()
    local healthChanged = beforeHealth and currentHumanoid and currentHumanoid.Health > beforeHealth

    if toolConsumed or worldPickupConsumed or healthChanged then
        STATS.FoodsUsed = STATS.FoodsUsed + 1
        return true, "Food consumption verified"
    end

    return true, "Food request sent; consumption could not be verified"
end

--// REVIVER
local function getMapPosition()
    local tiles = Workspace:FindFirstChild("PlacedTiles")
    local map = tiles and tiles:FindFirstChild("Map")
    if not map then return nil end
    local ok, pivot = pcall(function() return map:GetPivot() end)
    return ok and pivot and pivot.Position or nil
end

function GRIND.getMapModel()
    local tiles = Workspace:FindFirstChild("PlacedTiles")
    return tiles and tiles:FindFirstChild("Map") or nil
end

function GRIND.liftMapForGrinding()
    local map = GRIND.getMapModel()
    if not map then return false, "Map model missing" end
    if GRIND.MapLifted and GRIND.MapLiftedModel == map then return true end
    if GRIND.MapLiftedModel ~= map then
        local previousMap = GRIND.MapLiftedModel
        if previousMap and previousMap.Parent and GRIND.MapOriginalPivot then
            pcall(function() previousMap:PivotTo(GRIND.MapOriginalPivot) end)
        end
        GRIND.MapLifted = false
        GRIND.MapOriginalPivot = nil
        GRIND.MapLiftedModel = nil
    end
    local ok, pivot = pcall(function() return map:GetPivot() end)
    if not ok or not pivot then return false, "Map pivot unavailable" end
    GRIND.MapOriginalPivot = pivot
    local moved = pcall(function()
        map:PivotTo(pivot + Vector3.new(0, GRIND.MapSafeHeight, 0))
    end)
    if not moved then
        GRIND.MapOriginalPivot = nil
        return false, "Could not lift map"
    end
    GRIND.MapLiftedModel = map
    GRIND.MapLifted = true
    return true
end

function GRIND.restoreMapAfterGrinding()
    if not GRIND.MapLifted or not GRIND.MapOriginalPivot then return end
    local map = GRIND.MapLiftedModel
    if map and map.Parent then
        pcall(function() map:PivotTo(GRIND.MapOriginalPivot) end)
    end
    GRIND.MapLifted = false
    GRIND.MapOriginalPivot = nil
    GRIND.MapLiftedModel = nil
end

function GRIND.returnToLiftedMap()
    local mapPosition = getMapPosition()
    if not mapPosition then return false end
    return teleportNear(mapPosition + Vector3.new(0, 2.5, 0))
end

local function getScrapDropRemote()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local remote = remotes and remotes:FindFirstChild("ScrapDrop")
    return remote and remote:IsA("RemoteEvent") and remote or nil
end

--// FARM
function GRIND.supportedPickup(object)
    return object and (object:IsA("BasePart") or object:IsA("Model") or object:IsA("Tool"))
end

function GRIND.findFarmTargets(includeAll)
    local targets, seen = {}, {}
    local function add(object, kind)
        local validPickup = GRIND.supportedPickup(object) or (kind == "Reviver" and object and object:IsA("Folder"))
        if not object or seen[object] or not object.Parent or not validPickup then return end
        if GRIND.isTrapObject(object) then return end
        if isFood(object.Name) then
            if not GRIND.shouldPickupFood(object.Name) then return end
            kind = "Food"
        end
        if not includeAll and kind ~= "Reviver" then return end
        seen[object] = true
        table.insert(targets, { Object = object, Kind = kind })
    end

    local generated = Workspace:FindFirstChild("ProcGenGenerated")
    local items = generated and generated:FindFirstChild("ProcGenItems")
    if includeAll and items then
        for _, object in ipairs(items:GetChildren()) do
            add(object, object.Name == "Reviver" and "Reviver" or (object.Name == "Shard" and "Shard" or (isFood(object.Name) and "Food" or "Item")))
        end
    end

    if generated then
        local reviver = generated:FindFirstChild("Reviver", true)
        if reviver then add(reviver, "Reviver") end
        if includeAll then
            local shard = generated:FindFirstChild("Shard", true)
            if shard then add(shard, "Shard") end
        end
    end

    return targets
end

function GRIND.getSellStationTarget()
    local tiles = Workspace:FindFirstChild("PlacedTiles")
    local station = tiles and tiles:FindFirstChild("SellStation")
    if not station then return nil, nil end
    local spot = station:FindFirstChild("SellingSpot") or station
    return spot, findPrompt(spot) or findPrompt(station)
end

function GRIND.sellWorldPickup(object)
    if not object or not object.Parent or GRIND.isTrapObject(object) then
        return false, "Missing object or trap excluded"
    end
    if isFood(object.Name) then
        return false, "Food is never sold"
    end
    local prompt = findPrompt(object)
    local position = getObjectPosition(object)
    if not prompt or not position then return false, "Pickup prompt or position missing" end
    if not teleportNear(position) then return false, "Could not reach pickup" end
    task.wait(0.18)
    if not activatePrompt(prompt) then return false, "Pickup prompt failed" end
    task.wait(0.18)

    if isFood(object.Name) then return false, "Food is never sold" end
    local sellTarget, sellPrompt = GRIND.getSellStationTarget()
    local sellPosition = getObjectPosition(sellTarget)
    if not sellTarget or not sellPrompt or not sellPosition then
        return false, "Sell Station prompt or position missing"
    end
    if not teleportNear(sellPosition + Vector3.new(0, 0, -2)) then
        return false, "Could not reach Sell Station"
    end
    task.wait(0.18)
    if not activatePrompt(sellPrompt) then return false, "Sell prompt failed" end
    STATS.ItemsSold = STATS.ItemsSold + 1
    return true, "Picked up and sold " .. tostring(object.Name)
end

function GRIND.processFarmTarget(target)
    local object, kind = target.Object, target.Kind
    if not object or not object.Parent or GRIND.isTrapObject(object) then
        return false, "Target disappeared or trap excluded"
    end
    if isFood(object.Name) and not GRIND.shouldPickupFood(object.Name) then
        return false, "Food ignored; no matching heal is needed"
    end
    local prompt = findPrompt(object)
    local position = getObjectPosition(object)
    if not prompt or not position then return false, "Target prompt or position missing" end
    if not teleportForPickup(position, object.Name) then return false, "Could not reach target" end
    task.wait(0.18)
    if not RUNNING or not (CONFIG.AutoFarm or (kind == "Reviver" and CONFIG.AutoReviver)) then
        return false, "Automation disabled"
    end
    local oreBefore = isOre(object.Name) and inventoryCounts() or nil
    if not activatePrompt(prompt) then return false, "Target prompt activation failed" end

    if oreBefore then
        local deadline = os.clock() + 2.5
        local confirmed = false
        repeat
            task.wait(0.1)
            confirmed = hasNewOre(oreBefore)
        until confirmed or os.clock() >= deadline or not RUNNING
        if not confirmed then return false, "Ore pickup was not confirmed" end
        STATS.OresCollected = STATS.OresCollected + 1
    elseif kind == "Reviver" then
        task.wait(0.25)
    else
        task.wait(0.18)
    end

    if kind == "Reviver" then
        if not GRIND.returnToLiftedMap() then return false, "Map return position missing" end
        task.wait(0.25)
        local dropRemote = getScrapDropRemote()
        if not dropRemote then return false, "ScrapDrop remote missing" end
        local ok, err = pcall(function() dropRemote:FireServer() end)
        if not ok then return false, "ScrapDrop failed: " .. tostring(err) end
        STATS.ReviversCollected = STATS.ReviversCollected + 1
        return true, "Reviver dropped"
    elseif kind == "Shard" then
        pcall(function() object:Destroy() end)
        GRIND.returnToLiftedMap()
        return true, "Shard collected"
    elseif kind == "Food" or isFood(object.Name) then
        return GRIND.eatWorldPickupAfterPrompt(object)
    end

    local sellTarget, sellPrompt = GRIND.getSellStationTarget()
    local sellPosition = getObjectPosition(sellTarget)
    if not sellTarget or not sellPrompt or not sellPosition then return false, "Sell Station unavailable" end
    if not teleportNear(sellPosition + Vector3.new(0, 0, -2)) then return false, "Could not reach Sell Station" end
    task.wait(0.18)
    if not activatePrompt(sellPrompt) then return false, "Sell prompt failed" end
    STATS.ItemsSold = STATS.ItemsSold + 1
    return true, "Collected and sold " .. tostring(object.Name)
end

GRIND.eatWorldPickupAfterPrompt = function(object)
    if not object or not GRIND.shouldPickupFood(object.Name) then
        return false, "Food need changed; pickup was not eaten"
    end
    GRIND.returnToLiftedMap()
    task.wait(0.25)
    local ok, detail = eatFood(false)
    if not ok then return false, detail end
    return true, "Collected and ate " .. tostring(object.Name)
end

function GRIND.nextFallbackTarget()
    local candidates = {}
    local carrot = Workspace:FindFirstChild("Carrot")
    if carrot then table.insert(candidates, carrot) end
    local upgrades = Workspace:FindFirstChild("SpawnedUpgradeItems")
    if upgrades then
        for _, item in ipairs(upgrades:GetChildren()) do
            if GRIND.supportedPickup(item) then table.insert(candidates, item) end
        end
    end
    for _, object in ipairs(candidates) do
        if object.Parent and not GRIND.isTrapObject(object)
            and (OBJECT_COOLDOWNS[object] or 0) <= os.clock() then
            if isFood(object.Name) then
                if GRIND.shouldPickupFood(object.Name) then return object end
            else
                return object
            end
        end
    end
    return nil
end

--// MOVEMENT
local BASELINE_HUMANOID = nil
local BASELINE_MOVEMENT = nil

local function captureMovementBaseline(humanoid)
    if BASELINE_HUMANOID == humanoid and BASELINE_MOVEMENT then
        return
    end

    BASELINE_HUMANOID = humanoid
    BASELINE_MOVEMENT = {
        WalkSpeed = humanoid.WalkSpeed,
        HipHeight = humanoid.HipHeight,
        UseJumpPower = humanoid.UseJumpPower,
        JumpPower = humanoid.JumpPower,
        JumpHeight = humanoid.JumpHeight,
    }
end

local function restoreMovement()
    local humanoid = getHumanoid()
    if not humanoid or not BASELINE_MOVEMENT or BASELINE_HUMANOID ~= humanoid then
        return
    end

    pcall(function()
        humanoid.WalkSpeed = BASELINE_MOVEMENT.WalkSpeed
        humanoid.HipHeight = BASELINE_MOVEMENT.HipHeight
        humanoid.UseJumpPower = BASELINE_MOVEMENT.UseJumpPower
        humanoid.JumpPower = BASELINE_MOVEMENT.JumpPower
        humanoid.JumpHeight = BASELINE_MOVEMENT.JumpHeight
    end)
end

local function updateMovement()
    local humanoid = getHumanoid()
    if not humanoid then
        return
    end

    captureMovementBaseline(humanoid)
    local baseline = BASELINE_MOVEMENT

    pcall(function()
        humanoid.WalkSpeed = CONFIG.WalkSpeed and CONFIG.WalkSpeedValue or baseline.WalkSpeed
        humanoid.HipHeight = CONFIG.HipHeight and CONFIG.HipHeightValue or baseline.HipHeight

        if CONFIG.JumpPower then
            humanoid.UseJumpPower = true
            humanoid.JumpPower = CONFIG.JumpPowerValue
        else
            humanoid.UseJumpPower = baseline.UseJumpPower
            humanoid.JumpPower = baseline.JumpPower
            humanoid.JumpHeight = baseline.JumpHeight
        end
    end)
end

--// NOCLIP CAMERA
local NoclipCamPopper
local NoclipCamOriginal

local function setNoclipCam(enabled)
    local hook = ENV.hookfunction or hookfunction
    if type(hook) ~= "function" then
        return false, "NoclipCam requires executor hookfunction support"
    end

    if enabled then
        if NoclipCamPopper and NoclipCamOriginal then
            return true, "NoclipCam already enabled"
        end

        local playerScripts = LP:FindFirstChild("PlayerScripts") or LP:WaitForChild("PlayerScripts", 5)
        local playerModule = playerScripts and (playerScripts:FindFirstChild("PlayerModule") or playerScripts:WaitForChild("PlayerModule", 5))
        local cameraModule = playerModule and (playerModule:FindFirstChild("CameraModule") or playerModule:WaitForChild("CameraModule", 5))
        local zoomController = cameraModule and (cameraModule:FindFirstChild("ZoomController") or cameraModule:WaitForChild("ZoomController", 5))
        local popperModule = zoomController and (zoomController:FindFirstChild("Popper") or zoomController:WaitForChild("Popper", 5))
        if not popperModule or not popperModule:IsA("ModuleScript") then
            return false, "Roblox camera Popper module was not found"
        end

        local requireOK, popper = pcall(require, popperModule)
        if not requireOK or type(popper) ~= "function" then
            return false, "Could not load Roblox camera Popper module"
        end

        local hookOK, original = pcall(function()
            return hook(popper, function(focus, targetDist, focusExtrapolation)
                return targetDist
            end)
        end)
        if not hookOK or type(original) ~= "function" then
            return false, "Could not hook camera Popper; executor hookfunction may be incompatible"
        end

        NoclipCamPopper = popper
        NoclipCamOriginal = original
        return true, "NoclipCam enabled"
    end

    if NoclipCamPopper and NoclipCamOriginal then
        local restoreOK, restoreError = pcall(function()
            hook(NoclipCamPopper, NoclipCamOriginal)
        end)
        if not restoreOK then
            return false, "Could not restore camera collision: " .. tostring(restoreError)
        end
        NoclipCamPopper = nil
        NoclipCamOriginal = nil
    end
    return true, "NoclipCam disabled"
end

--// ESP
local ESP_FOLDER = Instance.new("Folder")
ESP_FOLDER.Name = "RevolverHubV1_ESP"
ESP_FOLDER.Parent = Workspace

local ESP_COLORS = {
    Ore = Color3.fromRGB(75, 218, 255),
    Entity = Color3.fromRGB(255, 86, 105),
    Location = Color3.fromRGB(183, 126, 255),
    Player = Color3.fromRGB(100, 255, 158),
}

local function playerForCharacter(model)
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character == model then
            return player
        end
    end
    return nil
end

local function classifyESP(object)
    if not object or not (object:IsA("Model") or object:IsA("BasePart")) then
        return nil
    end

    if CONFIG.PlayerESP and object:IsA("Model") and playerForCharacter(object) then
        return "Player"
    end

    if CONFIG.OreESP and isOre(object.Name) then
        return "Ore"
    end

    if CONFIG.EntityESP and containsAny(object.Name, ENTITY_WORDS) then
        return "Entity"
    end

    if CONFIG.LocationESP and containsAny(object.Name, LOCATION_WORDS) then
        return "Location"
    end

    return nil
end

local function removeHighlight(object)
    local entry = HIGHLIGHTS[object]
    if entry then
        pcall(function()
            if entry.Highlight then entry.Highlight:Destroy() end
        end)
        HIGHLIGHTS[object] = nil
    end
end

local function addHighlight(object, category)
    if not object or not object.Parent then
        return
    end

    local existing = HIGHLIGHTS[object]
    if existing and existing.Category == category and existing.Highlight and existing.Highlight.Parent then
        return
    elseif existing then
        removeHighlight(object)
    end

    local count = 0
    for _ in pairs(HIGHLIGHTS) do
        count = count + 1
    end
    if count >= MAX_HIGHLIGHTS then
        return
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "FFV6_Highlight"
    highlight.Adornee = object
    highlight.FillColor = ESP_COLORS[category]
    highlight.OutlineColor = ESP_COLORS[category]
    highlight.FillTransparency = 0.78
    highlight.OutlineTransparency = 0.08
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = ESP_FOLDER

    HIGHLIGHTS[object] = {
        Highlight = highlight,
        Category = category,
    }
end

local function scanESP()
    if not CONFIG.ESPDirty then return end
    CONFIG.ESPDirty = false
    local seen = {}

    for _, object in ipairs(Workspace:GetDescendants()) do
        if not RUNNING then
            return
        end

        local category = classifyESP(object)
        if category then
            seen[object] = true
            addHighlight(object, category)
        end
    end

    for object in pairs(HIGHLIGHTS) do
        if not object.Parent or not seen[object] then
            removeHighlight(object)
        end
    end
end

local function clearESP()
    for object in pairs(HIGHLIGHTS) do
        removeHighlight(object)
    end
end

--// KUKIRIN LIFE
local KUKIRIN_PLAYER_HIGHLIGHTS = setmetatable({}, { __mode = "k" })
local KUKIRIN_LAG_SAVED = setmetatable({}, { __mode = "k" })
local KUKIRIN_GLOBAL_SHADOWS = nil
local KUKIRIN_TERRAIN_DECORATION = nil
local KUKIRIN_KEYS_HELD = {}

local function setKukirinKey(keyCode, down)
    if KUKIRIN_KEYS_HELD[keyCode] == down then return end
    local ok = pcall(function()
        VirtualInputManager:SendKeyEvent(down, keyCode, false, game)
    end)
    if ok then
        KUKIRIN_KEYS_HELD[keyCode] = down and true or nil
    end
end

local function releaseKukirinKeys()
    for keyCode in pairs(KUKIRIN_KEYS_HELD) do
        pcall(function() VirtualInputManager:SendKeyEvent(false, keyCode, false, game) end)
        KUKIRIN_KEYS_HELD[keyCode] = nil
    end
end

local function saveAndSet(object, property, value)
    if not object then return end
    local saved = KUKIRIN_LAG_SAVED[object]
    if not saved then
        saved = {}
        KUKIRIN_LAG_SAVED[object] = saved
    end
    if saved[property] == nil then
        local ok, original = pcall(function() return object[property] end)
        if not ok then return end
        saved[property] = original
    end
    pcall(function() object[property] = value end)
end

local function optimizeKukirinObject(object)
    if not CONFIG.KukirinAntiLag or not object then return end
    if object:IsA("BasePart") then
        saveAndSet(object, "CastShadow", false)
        saveAndSet(object, "Reflectance", 0)
        saveAndSet(object, "Material", Enum.Material.Plastic)
    elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
        or object:IsA("Smoke") or object:IsA("Fire") or object:IsA("Sparkles")
        or object:IsA("PostEffect") then
        saveAndSet(object, "Enabled", false)
    elseif object:IsA("Decal") or object:IsA("Texture") then
        saveAndSet(object, "Transparency", 1)
    end
end

local function applyKukirinAntiLag(enabled)
    CONFIG.KukirinAntiLag = enabled == true
    if CONFIG.KukirinAntiLag then
        if KUKIRIN_GLOBAL_SHADOWS == nil then KUKIRIN_GLOBAL_SHADOWS = Lighting.GlobalShadows end
        pcall(function() Lighting.GlobalShadows = false end)
        local terrain = Workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            pcall(function()
                if KUKIRIN_TERRAIN_DECORATION == nil then KUKIRIN_TERRAIN_DECORATION = terrain.Decoration end
                terrain.Decoration = false
            end)
        end
        task.spawn(function()
            local all = Workspace:GetDescendants()
            for index, object in ipairs(all) do
                if not RUNNING or not CONFIG.KukirinAntiLag then break end
                optimizeKukirinObject(object)
                if index % 180 == 0 then task.wait() end
            end
            for _, object in ipairs(Lighting:GetDescendants()) do
                if not RUNNING or not CONFIG.KukirinAntiLag then break end
                optimizeKukirinObject(object)
            end
            log("Kukirin anti-lag applied (local visuals only)")
        end)
    else
        for object, properties in pairs(KUKIRIN_LAG_SAVED) do
            for property, original in pairs(properties) do
                pcall(function() object[property] = original end)
            end
            KUKIRIN_LAG_SAVED[object] = nil
        end
        if KUKIRIN_GLOBAL_SHADOWS ~= nil then
            pcall(function() Lighting.GlobalShadows = KUKIRIN_GLOBAL_SHADOWS end)
            KUKIRIN_GLOBAL_SHADOWS = nil
        end
        local terrain = Workspace:FindFirstChildOfClass("Terrain")
        if terrain and KUKIRIN_TERRAIN_DECORATION ~= nil then
            pcall(function() terrain.Decoration = KUKIRIN_TERRAIN_DECORATION end)
            KUKIRIN_TERRAIN_DECORATION = nil
        end
        log("Kukirin anti-lag restored original visuals")
    end
end

local function removeKukirinPlayerVisual(player)
    local highlight = KUKIRIN_PLAYER_HIGHLIGHTS[player]
    if highlight then
        pcall(function() highlight:Destroy() end)
        KUKIRIN_PLAYER_HIGHLIGHTS[player] = nil
    end
end

local function updateKukirinPlayerVisual(player)
    if not player or player == LP then return end
    local enabled = CONFIG.KukirinPlayerESP or CONFIG.KukirinChams
    local character = player.Character
    if not enabled or not character or not character.Parent then
        removeKukirinPlayerVisual(player)
        return
    end
    local highlight = KUKIRIN_PLAYER_HIGHLIGHTS[player]
    if not highlight or not highlight.Parent then
        highlight = Instance.new("Highlight")
        highlight.Name = "RevolverKukirin_Player"
        highlight.Adornee = character
        highlight.Parent = ESP_FOLDER
        KUKIRIN_PLAYER_HIGHLIGHTS[player] = highlight
    end
    highlight.Adornee = character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Color3.fromRGB(125, 105, 255)
    highlight.OutlineColor = Color3.fromRGB(70, 220, 255)
    highlight.FillTransparency = CONFIG.KukirinChams and 0.42 or 1
    highlight.OutlineTransparency = CONFIG.KukirinPlayerESP and 0.05 or 1
end

local function refreshKukirinPlayerVisuals()
    for _, player in ipairs(Players:GetPlayers()) do
        updateKukirinPlayerVisual(player)
    end
end

local function hookKukirinPlayer(player)
    connect(player.CharacterAdded, function()
        task.defer(function() updateKukirinPlayerVisual(player) end)
    end)
    updateKukirinPlayerVisual(player)
end

local function scanKukirinRide()
    local humanoid = getHumanoid()
    local seat = humanoid and humanoid.SeatPart
    log("--- KUKIRIN RIDE SCAN ---")
    if not seat then
        log("No SeatPart found. Sit on the scooter first.")
        return
    end
    log("Seat: " .. seat:GetFullName() .. " [" .. seat.ClassName .. "]")
    local model = seat:FindFirstAncestorOfClass("Model")
    if not model then
        log("Seat has no parent Model")
        return
    end
    log("Scooter model: " .. model:GetFullName())
    local count = 0
    local valueHints = { "speed", "accel", "power", "brake", "weight", "torque", "suspension", "wheel", "trick", "spin", "flip" }
    for _, object in ipairs(model:GetDescendants()) do
        local classMatch = object:IsA("BasePart") or object:IsA("Constraint") or object:IsA("BodyMover")
            or object:IsA("RemoteEvent") or object:IsA("RemoteFunction") or object:IsA("ValueBase")
            or object:IsA("ModuleScript") or object:IsA("LocalScript")
        local name = string.lower(object.Name)
        local valueMatch = false
        for _, hint in ipairs(valueHints) do
            if string.find(name, hint, 1, true) then valueMatch = true break end
        end
        if classMatch or valueMatch then
            local suffix = ""
            if object:IsA("ValueBase") then
                pcall(function() suffix = " | Value=" .. tostring(object.Value) end)
            end
            log(object.ClassName .. " | " .. object:GetFullName() .. suffix)
            count = count + 1
            if count >= 80 then
                log("Scan capped at 80 relevant descendants")
                break
            end
        end
        for attributeName, attributeValue in pairs(object:GetAttributes()) do
            local attributeLower = string.lower(attributeName)
            for _, hint in ipairs(valueHints) do
                if string.find(attributeLower, hint, 1, true) then
                    log("ATTRIBUTE: " .. object:GetFullName() .. " | " .. attributeName .. "=" .. tostring(attributeValue))
                    break
                end
            end
        end
    end
end

local function scanKukirinModAndTrickUI()
    log("--- KUKIRIN MOD / TRICK SCAN ---")
    local playerGui = LP:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        log("PlayerGui not ready")
        return
    end

    local keywords = { "scooter", "upgrade", "mod", "hardware", "unlock", "trick", "spin", "flip", "wheelie", "garage", "shop" }
    local function matches(value)
        local lower = string.lower(tostring(value or ""))
        for _, keyword in ipairs(keywords) do
            if string.find(lower, keyword, 1, true) then return true end
        end
        return false
    end

    local guiCount = 0
    for _, object in ipairs(playerGui:GetDescendants()) do
        local textValue = ""
        if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
            pcall(function() textValue = object.Text end)
        end
        if matches(object.Name) or matches(textValue) then
            local visible = ""
            if object:IsA("GuiObject") then
                pcall(function() visible = " | Visible=" .. tostring(object.Visible) end)
            end
            log("UI: " .. object.ClassName .. " | " .. object:GetFullName() .. visible .. (textValue ~= "" and " | Text=" .. string.sub(textValue, 1, 70) or ""))
            guiCount = guiCount + 1
            if guiCount >= 50 then
                log("UI scan capped at 50 matches")
                break
            end
        end
    end
    if guiCount == 0 then log("No matching UI objects found; open the garage/mod or trick menu and scan again") end

    local remoteCount = 0
    for _, object in ipairs(ReplicatedStorage:GetDescendants()) do
        if (object:IsA("RemoteEvent") or object:IsA("RemoteFunction")) and matches(object.Name) then
            log("REMOTE: " .. object.ClassName .. " | " .. object:GetFullName())
            remoteCount = remoteCount + 1
            if remoteCount >= 35 then
                log("Remote scan capped at 35 matches")
                break
            end
        end
    end
    if remoteCount == 0 then log("No named scooter/trick remotes found in ReplicatedStorage") end
    log("Scan complete. Copy the Console output when sending it back.")
end

local function kukirinWheelieWorker()
    local nextTap = 0
    local throttleUntil = 0
    while RUNNING do
        local active = IS_KUKIRIN and CONFIG.KukirinAutoWheelie and not UserInputService:GetFocusedTextBox()
        local humanoid = active and getHumanoid() or nil
        local seat = humanoid and humanoid.SeatPart
        if seat and (seat:IsA("VehicleSeat") or seat:IsA("Seat")) then
            setKukirinKey(Enum.KeyCode.LeftControl, true)
            if os.clock() >= throttleUntil then
                setKukirinKey(Enum.KeyCode.W, true)
                task.wait(math.clamp(CONFIG.KukirinThrottlePulse, 0.05, 0.4))
                setKukirinKey(Enum.KeyCode.W, false)
                throttleUntil = os.clock() + 0.12
            end
            if os.clock() >= nextTap then
                setKukirinKey(Enum.KeyCode.Up, true)
                task.wait(0.035)
                setKukirinKey(Enum.KeyCode.Up, false)
                nextTap = os.clock() + math.clamp(CONFIG.KukirinWheelieTapInterval, 0.10, 0.75)
            end
        else
            releaseKukirinKeys()
            nextTap = 0
            throttleUntil = 0
        end
        task.wait(0.025)
    end
    releaseKukirinKeys()
end

--// GUI
local COLORS = {
    Background = Color3.fromRGB(12, 14, 22),
    Panel = Color3.fromRGB(19, 22, 33),
    Panel2 = Color3.fromRGB(27, 31, 46),
    PanelHover = Color3.fromRGB(35, 40, 58),
    Accent = Color3.fromRGB(113, 91, 255),
    Accent2 = Color3.fromRGB(50, 190, 224),
    Text = Color3.fromRGB(240, 242, 255),
    Muted = Color3.fromRGB(145, 153, 179),
    Green = Color3.fromRGB(92, 235, 157),
    Red = Color3.fromRGB(255, 91, 110),
}

local function make(className, properties, parent)
    local object = Instance.new(className)
    for property, value in pairs(properties or {}) do
        object[property] = value
    end
    object.Parent = parent
    return object
end

local function addCorner(object, radius)
    return make("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, object)
end

local function addStroke(object, color, transparency, thickness)
    return make("UIStroke", {
        Color = color or COLORS.Accent,
        Transparency = transparency == nil and 0.65 or transparency,
        Thickness = thickness or 1,
    }, object)
end

local function addPadding(object, left, right, top, bottom)
    return make("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or 0),
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
    }, object)
end

--// MAIN UI
local GUI = Instance.new("ScreenGui")
GUI.Name = "RevolverHubV1_LegacyHidden"
GUI.ResetOnSpawn = false
GUI.IgnoreGuiInset = true
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
mountGui(GUI)

local Main = make("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(900, 610),
    BackgroundColor3 = COLORS.Background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, GUI)
addCorner(Main, 18)
addStroke(Main, COLORS.Accent, 0.22, 1.4)
local MainScale = make("UIScale", { Scale = UI_SETTINGS.Scale }, Main)
local MOBILE_RESTORE

local MainShadow = make("ImageLabel", {
    Name = "SoftShadow",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(1, 46, 1, 46),
    BackgroundTransparency = 1,
    Image = "rbxassetid://6014261993",
    ImageColor3 = Color3.fromRGB(0, 0, 0),
    ImageTransparency = 0.34,
    ScaleType = Enum.ScaleType.Slice,
    SliceCenter = Rect.new(49, 49, 450, 450),
    ZIndex = 0,
}, Main)
Main.ZIndex = 2

local Top = make("Frame", {
    Name = "TopBar",
    Size = UDim2.new(1, 0, 0, 70),
    BackgroundColor3 = COLORS.Panel,
    BorderSizePixel = 0,
}, Main)
addCorner(Top, 15)

local topGradient = make("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(75, 56, 180)),
        ColorSequenceKeypoint.new(0.52, Color3.fromRGB(35, 116, 169)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(75, 56, 180)),
    }),
    Rotation = 0,
}, Top)
local topGradientAnimation = TweenService:Create(
    topGradient,
    TweenInfo.new(14, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
    { Rotation = 360 }
)
topGradientAnimation:Play()

local topOverlay = make("Frame", {
    Position = UDim2.new(0, 0, 0, 42),
    Size = UDim2.new(1, 0, 0, 22),
    BackgroundColor3 = COLORS.Panel,
    BackgroundTransparency = 0.05,
    BorderSizePixel = 0,
}, Top)

local logo = make("TextLabel", {
    Position = UDim2.fromOffset(24, 10),
    Size = UDim2.fromOffset(300, 26),
    BackgroundTransparency = 1,
    Text = "REVOLVER HUB",
    TextColor3 = COLORS.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    TextXAlignment = Enum.TextXAlignment.Left,
}, Top)

local subtitle = make("TextLabel", {
    Position = UDim2.fromOffset(25, 39),
    Size = UDim2.fromOffset(330, 17),
    BackgroundTransparency = 1,
    Text = "REVOLVER HUB  •  V1.4  •  SECURE LICENSE",
    TextColor3 = Color3.fromRGB(211, 219, 247),
    Font = Enum.Font.GothamMedium,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
}, Top)

local statusLabel = make("TextLabel", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -20, 0.5, 0),
    Size = UDim2.fromOffset(160, 25),
    BackgroundTransparency = 1,
    Text = "● READY",
    TextColor3 = COLORS.Green,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Right,
}, Top)

local Sidebar = make("Frame", {
    Name = "Sidebar",
    Position = UDim2.fromOffset(14, 82),
    Size = UDim2.new(0, 184, 1, -96),
    BackgroundColor3 = COLORS.Panel,
    BorderSizePixel = 0,
}, Main)
addCorner(Sidebar, 11)

local sidebarHeader = make("TextLabel", {
    Position = UDim2.fromOffset(14, 12),
    Size = UDim2.new(1, -28, 0, 17),
    BackgroundTransparency = 1,
    Text = "NAVIGATION",
    TextColor3 = COLORS.Muted,
    Font = Enum.Font.GothamBold,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
}, Sidebar)

local tabHolder = make("ScrollingFrame", {
    Position = UDim2.fromOffset(9, 44),
    Size = UDim2.new(1, -18, 0, 300),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 2,
    ScrollBarImageColor3 = COLORS.Accent,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, Sidebar)
local tabLayout = make("UIListLayout", {
    Padding = UDim.new(0, 7),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, tabHolder)
connect(tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
    if tabHolder.ScrollingDirection == Enum.ScrollingDirection.X then
        tabHolder.CanvasSize = UDim2.new(0, tabLayout.AbsoluteContentSize.X + 12, 0, 0)
    else
        tabHolder.CanvasSize = UDim2.new(0, 0, 0, tabLayout.AbsoluteContentSize.Y + 12)
    end
end)

local sidebarFooter = make("TextLabel", {
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 13, 1, -12),
    Size = UDim2.new(1, -26, 0, 38),
    BackgroundTransparency = 1,
    Text = "LICENSED MODE\nSERVER VERIFIED",
    TextColor3 = Color3.fromRGB(165, 157, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Bottom,
}, Sidebar)

local Content = make("Frame", {
    Name = "Content",
    Position = UDim2.fromOffset(210, 82),
    Size = UDim2.new(1, -224, 1, -96),
    BackgroundColor3 = COLORS.Panel,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, Main)
addCorner(Content, 11)

local Pages = {}
local TabButtons = {}
local ActiveTab = nil

local function createPage(name)
    local page = make("ScrollingFrame", {
        Name = name .. "Page",
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = COLORS.Accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false,
    }, Content)
    addPadding(page, 13, 13, 13, 15)
    local layout = make("UIListLayout", {
        Padding = UDim.new(0, 9),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, page)
    connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        page.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 30)
    end)
    Pages[name] = page
    return page
end

local function showPage(name)
    if not Pages[name] then return end
    ActiveTab = name

    for pageName, page in pairs(Pages) do
        if pageName == name then
            page.Visible = true
            page.Position = UDim2.fromOffset(9, 0)
            tween(page, 0.22, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
        else
            page.Visible = false
        end
    end

    for tabName, button in pairs(TabButtons) do
        local selected = tabName == name
        tween(button, 0.16, {
            BackgroundColor3 = selected and COLORS.PanelHover or COLORS.Panel,
            TextColor3 = selected and COLORS.Text or COLORS.Muted,
        })
        local indicator = button:FindFirstChild("Indicator")
        if indicator then
            tween(indicator, 0.16, {
                BackgroundTransparency = selected and 0 or 1,
                Size = selected and UDim2.new(0, 3, 0.62, 0) or UDim2.new(0, 3, 0.2, 0),
            })
        end
    end
end

local function createTab(name, symbol, order)
    local button = make("TextButton", {
        Name = name,
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = COLORS.Panel,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = symbol .. "    " .. name,
        TextColor3 = COLORS.Muted,
        Font = Enum.Font.GothamSemibold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = order,
    }, tabHolder)
    addCorner(button, 10)
    addPadding(button, 14, 6, 0, 0)

    local indicator = make("Frame", {
        Name = "Indicator",
        Position = UDim2.new(0, 0, 0.19, 0),
        Size = UDim2.new(0, 3, 0.2, 0),
        BackgroundColor3 = COLORS.Accent2,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, button)
    addCorner(indicator, 3)

    connect(button.Activated, function()
        showPage(name)
    end)
    connect(button.MouseEnter, function()
        if ActiveTab ~= name then
            tween(button, 0.12, { BackgroundColor3 = COLORS.Panel2 })
        end
    end)
    connect(button.MouseLeave, function()
        if ActiveTab ~= name then
            tween(button, 0.12, { BackgroundColor3 = COLORS.Panel })
        end
    end)

    TabButtons[name] = button
    return createPage(name)
end

local HomePage = createTab("Overview", "⌂", 1)
local FarmPage = createTab("Farm", "◈", 2)
local VisualPage = createTab("Visuals", "◎", 3)
local MovementPage = createTab("Movement", "➤", 4)
local StatsPage = createTab("Stats", "▤", 5)
local SettingsPage = createTab("Settings", "⚙", 6)
local DebugPage = createTab("Console", "⌘", 7)

local function section(parent, title, subtitleText)
    local holder = make("Frame", {
        Size = UDim2.new(1, -2, 0, subtitleText and 39 or 25),
        BackgroundTransparency = 1,
    }, parent)
    local label = make("TextLabel", {
        Position = UDim2.fromOffset(1, 0),
        Size = UDim2.new(1, -2, 0, 19),
        BackgroundTransparency = 1,
        Text = string.upper(title),
        TextColor3 = COLORS.Accent2,
        Font = Enum.Font.GothamBold,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, holder)
    if subtitleText then
        make("TextLabel", {
            Position = UDim2.fromOffset(1, 19),
            Size = UDim2.new(1, -2, 0, 16),
            BackgroundTransparency = 1,
            Text = subtitleText,
            TextColor3 = COLORS.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, holder)
    end
    return holder
end

local function createToggle(parent, title, configKey, description)
    local height = description and 54 or 43
    local row = make("Frame", {
        Size = UDim2.new(1, -2, 0, height),
        BackgroundColor3 = COLORS.Panel2,
        BorderSizePixel = 0,
    }, parent)
    addCorner(row, 9)

    make("TextLabel", {
        Position = UDim2.fromOffset(12, description and 7 or 0),
        Size = UDim2.new(1, -82, 0, 20),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = COLORS.Text,
        Font = Enum.Font.GothamSemibold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    if description then
        make("TextLabel", {
            Position = UDim2.fromOffset(12, 28),
            Size = UDim2.new(1, -84, 0, 15),
            BackgroundTransparency = 1,
            Text = description,
            TextColor3 = COLORS.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)
    end

    local switch = make("TextButton", {
        Position = UDim2.new(1, -58, 0.5, -12),
        Size = UDim2.fromOffset(45, 24),
        BackgroundColor3 = COLORS.Background,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, row)
    addCorner(switch, 20)

    local knob = make("Frame", {
        Position = UDim2.fromOffset(3, 3),
        Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = COLORS.Muted,
        BorderSizePixel = 0,
    }, switch)
    addCorner(knob, 20)

    local function refresh()
        local enabled = CONFIG[configKey] == true
        tween(switch, 0.16, {
            BackgroundColor3 = enabled and COLORS.Accent or COLORS.Background,
        })
        tween(knob, 0.16, {
            Position = enabled and UDim2.new(1, -21, 0, 3) or UDim2.fromOffset(3, 3),
            BackgroundColor3 = enabled and COLORS.Text or COLORS.Muted,
        })
    end

    connect(switch.Activated, function()
        CONFIG[configKey] = not CONFIG[configKey]
        refresh()
        log(title .. (CONFIG[configKey] and " enabled" or " disabled"))
        if configKey == "WalkSpeed" or configKey == "HipHeight" or configKey == "JumpPower" then
            updateMovement()
        elseif configKey == "NoclipCam" then
            local applied, detail = setNoclipCam(CONFIG.NoclipCam)
            if not applied then
                CONFIG.NoclipCam = false
                refresh()
            end
            log(detail)
        elseif configKey == "OreESP" or configKey == "EntityESP" or configKey == "LocationESP" or configKey == "PlayerESP" then
            CONFIG.ESPDirty = true
            if not (CONFIG.OreESP or CONFIG.EntityESP or CONFIG.LocationESP or CONFIG.PlayerESP) then
                clearESP()
            end
        end
    end)

    connect(row.MouseEnter, function()
        tween(row, 0.12, { BackgroundColor3 = COLORS.PanelHover })
    end)
    connect(row.MouseLeave, function()
        tween(row, 0.12, { BackgroundColor3 = COLORS.Panel2 })
    end)

    refresh()
    return row
end

local function createSlider(parent, title, configKey, minimum, maximum, step)
    step = step or 1
    local row = make("Frame", {
        Size = UDim2.new(1, -2, 0, 63),
        BackgroundColor3 = COLORS.Panel2,
        BorderSizePixel = 0,
    }, parent)
    addCorner(row, 9)

    local valueLabel = make("TextLabel", {
        Position = UDim2.fromOffset(12, 6),
        Size = UDim2.new(1, -24, 0, 18),
        BackgroundTransparency = 1,
        TextColor3 = COLORS.Text,
        Font = Enum.Font.GothamSemibold,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local bar = make("TextButton", {
        Position = UDim2.fromOffset(13, 37),
        Size = UDim2.new(1, -26, 0, 8),
        BackgroundColor3 = COLORS.Background,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Active = true,
    }, row)
    addCorner(bar, 6)

    local fill = make("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = COLORS.Accent,
        BorderSizePixel = 0,
        Active = false,
    }, bar)
    addCorner(fill, 6)

    local knob = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(15, 15),
        BackgroundColor3 = COLORS.Text,
        BorderSizePixel = 0,
        Active = false,
        ZIndex = 3,
    }, bar)
    addCorner(knob, 20)
    addStroke(knob, COLORS.Accent, 0.25, 1)

    local dragging = false
    local activeTouch = nil

    local function formatValue(value)
        local text = string.format("%.3f", value)
        text = string.gsub(text, "0+$", "")
        text = string.gsub(text, "%.$", "")
        return text
    end

    local function setValue(rawValue, animated)
        local steps = math.floor(((rawValue - minimum) / step) + 0.5)
        local value = minimum + (steps * step)
        value = math.clamp(value, minimum, maximum)
        value = math.floor(value * 1000 + 0.5) / 1000
        CONFIG[configKey] = value

        local percent = (value - minimum) / (maximum - minimum)
        percent = math.clamp(percent, 0, 1)
        valueLabel.Text = title .. "  |  " .. formatValue(value)

        local sizeTarget = UDim2.fromScale(percent, 1)
        local positionTarget = UDim2.fromScale(percent, 0.5)
        if animated then
            tween(fill, 0.07, { Size = sizeTarget }, Enum.EasingStyle.Quad)
            tween(knob, 0.07, { Position = positionTarget }, Enum.EasingStyle.Quad)
        else
            fill.Size = sizeTarget
            knob.Position = positionTarget
        end
    end

    local function updateFromX(x)
        local width = bar.AbsoluteSize.X
        if width <= 0 then return end
        local percent = math.clamp((x - bar.AbsolutePosition.X) / width, 0, 1)
        setValue(minimum + percent * (maximum - minimum), true)
    end

    connect(bar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            updateFromX(input.Position.X)
        elseif input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            activeTouch = input
            updateFromX(input.Position.X)
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            updateFromX(input.Position.X)
        elseif input.UserInputType == Enum.UserInputType.Touch and input == activeTouch then
            updateFromX(input.Position.X)
        end
    end)

    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input == activeTouch then
            dragging = false
            activeTouch = nil
        end
    end)

    setValue(CONFIG[configKey], false)
    return row
end

local function createButton(parent, title, callback, color)
    local button = make("TextButton", {
        Size = UDim2.new(1, -2, 0, 38),
        BackgroundColor3 = color or COLORS.Accent,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = title,
        TextColor3 = COLORS.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
    }, parent)
    addCorner(button, 8)
    connect(button.MouseEnter, function()
        tween(button, 0.13, { BackgroundColor3 = Color3.fromRGB(132, 111, 255) })
    end)
    connect(button.MouseLeave, function()
        tween(button, 0.13, { BackgroundColor3 = color or COLORS.Accent })
    end)
    connect(button.Activated, callback)
    return button
end

--// NOTIFICATIONS
local ToastHolder = make("Frame", {
    Name = "ToastHolder",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -18, 0, 78),
    Size = UDim2.fromOffset(280, 220),
    BackgroundTransparency = 1,
}, GUI)
local ToastLayout = make("UIListLayout", {
    Padding = UDim.new(0, 8),
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
    SortOrder = Enum.SortOrder.LayoutOrder,
}, ToastHolder)

local function notify(message, kind)
    log(message)
    if Fluent then
        pcall(function()
            Fluent:Notify({
                Title = kind == "error" and "Revolver Hub · Error" or (kind == "success" and "Revolver Hub · Success" or "Revolver Hub"),
                Content = tostring(message),
                Duration = 4,
            })
        end)
    end
    local accent = kind == "error" and COLORS.Red or (kind == "success" and COLORS.Green or COLORS.Accent2)
    local toast = make("Frame", {
        Size = UDim2.fromOffset(0, 52),
        BackgroundColor3 = COLORS.Panel2,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, ToastHolder)
    addCorner(toast, 9)
    addStroke(toast, accent, 0.35, 1)

    make("Frame", {
        Size = UDim2.new(0, 3, 1, -14),
        Position = UDim2.fromOffset(0, 7),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
    }, toast)

    make("TextLabel", {
        Position = UDim2.fromOffset(13, 0),
        Size = UDim2.new(1, -22, 1, 0),
        BackgroundTransparency = 1,
        Text = tostring(message),
        TextColor3 = COLORS.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, toast)

    tween(toast, 0.22, { Size = UDim2.fromOffset(270, 52) })
    task.delay(3, function()
        if toast and toast.Parent then
            tween(toast, 0.18, { Size = UDim2.fromOffset(0, 52), BackgroundTransparency = 1 })
            task.wait(0.2)
            if toast then toast:Destroy() end
        end
    end)
end

--// OVERVIEW
section(HomePage, "Welcome back", "Your Revolver Hub control center · Version 1.0 interface")
local welcomeCard = make("Frame", {
    Size = UDim2.new(1, -2, 0, 118),
    BackgroundColor3 = COLORS.Panel2,
    BorderSizePixel = 0,
}, HomePage)
addCorner(welcomeCard, 13)
local welcomeGradient = make("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(37, 43, 72)),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(35, 53, 78)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(55, 39, 88)),
    }),
    Rotation = 18,
}, welcomeCard)
make("TextLabel", {
    Position = UDim2.fromOffset(17, 15),
    Size = UDim2.new(1, -34, 0, 28),
    BackgroundTransparency = 1,
    Text = "REVOLVER HUB  /  V1.4",
    TextColor3 = COLORS.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left,
}, welcomeCard)
make("TextLabel", {
    Position = UDim2.fromOffset(18, 49),
    Size = UDim2.new(1, -36, 0, 42),
    BackgroundTransparency = 1,
    Text = "Revolver Hub control center.\nToggle modules, tune your setup and watch your session live.",
    TextColor3 = Color3.fromRGB(190, 199, 224),
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
}, welcomeCard)
section(HomePage, "Quick launch", "Jump straight into the modules")
createButton(HomePage, "OPEN AUTOMATION  →", function() showPage("Farm") end)
createButton(HomePage, "OPEN VISUALS  →", function() showPage("Visuals") end, COLORS.PanelHover)
createButton(HomePage, "OPEN MOVEMENT  →", function() showPage("Movement") end, COLORS.PanelHover)
section(HomePage, "Session snapshot", "Live counters are available in the Stats page")
local homeStatus = make("TextLabel", {
    Size = UDim2.new(1, -2, 0, 54),
    BackgroundColor3 = COLORS.Panel2,
    BorderSizePixel = 0,
    Text = "●  HUB INITIALIZED  ·  " .. BUILD_LABEL,
    TextColor3 = COLORS.Green,
    Font = Enum.Font.GothamBold,
    TextSize = 11,
}, HomePage)
addCorner(homeStatus, 10)
table.insert(BUILD_MODE_UPDATERS, function(buildLabel)
    if homeStatus and homeStatus.Parent then
        homeStatus.Text = "●  HUB INITIALIZED  ·  " .. buildLabel
    end
end)

--// FARM UI
section(FarmPage, "Automation", "Run one task at a time to prevent farm/sell conflicts")
createToggle(FarmPage, "Auto Grind", "AutoFarm", "Collect ores and safe loot; only pick food when its heal fits missing HP; never sell food or eat eggs; always drop Revivers; skip traps")
createToggle(FarmPage, "Auto Sell Items", "AutoSell", "Sell carried ores whenever available")
createToggle(FarmPage, "Auto Eat", "AutoEat", "Eat at 15+ missing HP: carrot 15, cooked carrot 30, ham 40, cooked ham 80; eggs never eaten")
createToggle(FarmPage, "Auto Reviver", "AutoReviver", "Collect Revivers and always drop them; never sell, solo or multiplayer")
section(FarmPage, "Timing", "All values are real seconds; decimal steps are supported")
createSlider(FarmPage, "Farm delay (sec)", "FarmDelay", 0.10, 2.00, 0.05)
createSlider(FarmPage, "Sell delay (sec)", "SellDelay", 0.10, 2.00, 0.05)
createSlider(FarmPage, "Eat interval (sec)", "EatDelay", 1.00, 15.00, 0.25)

--// VISUALS UI
section(VisualPage, "ESP modules", "Highlights are reused instead of recreated every scan")
createToggle(VisualPage, "Ore ESP", "OreESP", "Iron, Jade, Amethyst, Gold and Amber")
createToggle(VisualPage, "Entity ESP", "EntityESP", "Names containing monster, enemy, entity, creature or boss")
createToggle(VisualPage, "Location ESP", "LocationESP", "Spawn, exit, shop, station, elevator and safe zones")
createToggle(VisualPage, "Player ESP", "PlayerESP", "Highlight player character models")

--// MOVEMENT UI
section(MovementPage, "Movement", "Values restore to the character's original settings when disabled")
createToggle(MovementPage, "WalkSpeed", "WalkSpeed", "Apply a custom WalkSpeed")
createSlider(MovementPage, "WalkSpeed value", "WalkSpeedValue", 16, 100, 1)
createToggle(MovementPage, "HipHeight", "HipHeight", "Apply a custom HipHeight")
createSlider(MovementPage, "HipHeight value", "HipHeightValue", 0, 20, 0.25)
createToggle(MovementPage, "JumpPower", "JumpPower", "Temporarily enables UseJumpPower and restores its old value")
createSlider(MovementPage, "JumpPower value", "JumpPowerValue", 25, 150, 1)
createToggle(MovementPage, "Anti-AFK", "AntiAFK", "Attempts an idle input using VirtualUser where supported")
createToggle(MovementPage, "NoclipCam (NCCam)", "NoclipCam", "Keep the camera attached to your character while it passes through walls")

--// STATS UI
section(StatsPage, "Live session", "Values refresh twice per second")
local StatsCard = make("Frame", {
    Size = UDim2.new(1, -2, 0, 300),
    BackgroundColor3 = COLORS.Panel2,
    BorderSizePixel = 0,
}, StatsPage)
addCorner(StatsCard, 10)
local StatsLabel = make("TextLabel", {
    Position = UDim2.fromOffset(15, 12),
    Size = UDim2.new(1, -30, 1, -24),
    BackgroundTransparency = 1,
    Text = "Loading statistics...",
    TextColor3 = COLORS.Text,
    Font = Enum.Font.Code,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
}, StatsCard)

--// SETTINGS UI
section(SettingsPage, "Access and license", "Build is selected by your key · saved key auto-validates when you run the script")
createButton(SettingsPage, "CHANGE / SWITCH ACCESS KEY", beginKeySwitch, COLORS.PanelHover)
section(SettingsPage, "Personalize your interface", "Live theme controls · changes apply instantly")
local themePreview = make("Frame", {
    Size = UDim2.new(1, -2, 0, 76),
    BackgroundColor3 = COLORS.Panel2,
    BorderSizePixel = 0,
}, SettingsPage)
addCorner(themePreview, 11)
local previewAccent = make("Frame", {
    Position = UDim2.fromOffset(13, 13),
    Size = UDim2.fromOffset(48, 48),
    BackgroundColor3 = UI_SETTINGS.Accent,
    BorderSizePixel = 0,
}, themePreview)
addCorner(previewAccent, 12)
make("TextLabel", {
    Position = UDim2.fromOffset(73, 12),
    Size = UDim2.new(1, -86, 0, 20),
    BackgroundTransparency = 1,
    Text = "CURRENT COLOR PROFILE",
    TextColor3 = COLORS.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
}, themePreview)
local themeNameLabel = make("TextLabel", {
    Position = UDim2.fromOffset(73, 34),
    Size = UDim2.new(1, -86, 0, 18),
    BackgroundTransparency = 1,
    Text = UI_SETTINGS.ThemeName .. "  ·  Revolver palette",
    TextColor3 = COLORS.Muted,
    Font = Enum.Font.Gotham,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
}, themePreview)

local function applyAccent(newAccent, newAccent2, label)
    local oldAccent, oldAccent2 = COLORS.Accent, COLORS.Accent2
    COLORS.Accent, COLORS.Accent2 = newAccent, newAccent2
    UI_SETTINGS.Accent, UI_SETTINGS.Accent2, UI_SETTINGS.ThemeName = newAccent, newAccent2, label
    for _, object in ipairs(GUI:GetDescendants()) do
        pcall(function()
            if object:IsA("UIStroke") and object.Color == oldAccent then object.Color = newAccent end
            if object:IsA("TextButton") or object:IsA("Frame") then
                if object.BackgroundColor3 == oldAccent then object.BackgroundColor3 = newAccent end
                if object.BackgroundColor3 == oldAccent2 then object.BackgroundColor3 = newAccent2 end
            end
            if object:IsA("TextLabel") and object.TextColor3 == oldAccent then object.TextColor3 = newAccent end
            if object:IsA("ScrollingFrame") and object.ScrollBarImageColor3 == oldAccent then object.ScrollBarImageColor3 = newAccent end
        end)
    end
    previewAccent.BackgroundColor3 = newAccent
    themeNameLabel.Text = label .. "  ·  custom palette"
    keyStroke.Color = newAccent
    notify("Theme changed to " .. label, "success")
end

section(SettingsPage, "Color presets", "Choose the accent that matches your setup")
local palettes = {
    {"Revolver", Color3.fromRGB(125, 105, 255), Color3.fromRGB(58, 210, 226)},
    {"Cyber", Color3.fromRGB(0, 220, 190), Color3.fromRGB(91, 255, 208)},
    {"Rose", Color3.fromRGB(255, 91, 151), Color3.fromRGB(255, 164, 196)},
    {"Ember", Color3.fromRGB(255, 139, 65), Color3.fromRGB(255, 204, 105)},
    {"Ice", Color3.fromRGB(85, 174, 255), Color3.fromRGB(139, 224, 255)},
    {"Violet", Color3.fromRGB(180, 100, 255), Color3.fromRGB(224, 155, 255)},
}
for _, palette in ipairs(palettes) do
    local name, colorA, colorB = palette[1], palette[2], palette[3]
    createButton(SettingsPage, "●   " .. name, function()
        UI_SETTINGS.Rainbow = false
        applyAccent(colorA, colorB, name)
    end, COLORS.PanelHover)
end

createToggle(SettingsPage, "Rainbow accent", "RainbowUI", "Slow animated hue cycling across accent elements")
createSlider(SettingsPage, "Interface scale", "UIScaleValue", 0.80, 1.20, 0.05)
createButton(SettingsPage, "Hide / show hub", function()
    Main.Visible = not Main.Visible
    if MOBILE_RESTORE then
        MOBILE_RESTORE.Visible = IS_MOBILE_UI and not Main.Visible
    end
end, COLORS.PanelHover)
createButton(SettingsPage, "RESET INTERFACE SCALE", function()
    CONFIG.UIScaleValue = 1
    UI_SETTINGS.Scale = 1
    MainScale.Scale = 1
    notify("Interface scale reset", "success")
end, COLORS.PanelHover)

--// DEBUG UI
section(DebugPage, "Debug console", "Recent events and caught errors")
local DebugCard = make("Frame", {
    Size = UDim2.new(1, -2, 0, 260),
    BackgroundColor3 = COLORS.Panel2,
    BorderSizePixel = 0,
}, DebugPage)
addCorner(DebugCard, 10)
local DebugLabel = make("TextLabel", {
    Position = UDim2.fromOffset(12, 10),
    Size = UDim2.new(1, -24, 1, -20),
    BackgroundTransparency = 1,
    Text = "Waiting for logs...",
    TextColor3 = COLORS.Muted,
    Font = Enum.Font.Code,
    TextSize = 9,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
}, DebugCard)
createButton(DebugPage, "CLEAR LOGS", function()
    table.clear(LOGS)
    log("Log cleared")
end, COLORS.PanelHover)

--// WINDOW DRAG
local draggingWindow = false
local dragStart = nil
local startPosition = nil
connect(Top.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        draggingWindow = true
        dragStart = input.Position
        startPosition = Main.Position
    elseif input.UserInputType == Enum.UserInputType.Touch then
        local rightControlZone = IS_MOBILE_UI and (Top.AbsolutePosition.X + Top.AbsoluteSize.X - 116) or math.huge
        if not IS_MOBILE_UI or input.Position.X < rightControlZone then
            draggingWindow = true
            dragStart = input.Position
            startPosition = Main.Position
        end
    end
end)
connect(UserInputService.InputChanged, function(input)
    if not draggingWindow then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingWindow = false
    end
end)

--// FLUENT UI
local destroyHub
local function fluentToggle(tab, title, configKey, description)
    local control = tab:AddToggle("FF_" .. configKey, {
        Title = title,
        Description = description or "",
        Default = CONFIG[configKey] == true,
        Callback = function(value)
            CONFIG[configKey] = value == true
            log(title .. (CONFIG[configKey] and " enabled" or " disabled"))
            if configKey == "WalkSpeed" or configKey == "HipHeight" or configKey == "JumpPower" then
                updateMovement()
            elseif configKey == "NoclipCam" then
                local applied, detail = setNoclipCam(CONFIG.NoclipCam)
                if not applied then
                    CONFIG.NoclipCam = false
                    pcall(function() control:SetValue(false) end)
                end
                log(detail)
            elseif configKey == "OreESP" or configKey == "EntityESP" or configKey == "LocationESP" or configKey == "PlayerESP" then
                CONFIG.ESPDirty = true
                if not (CONFIG.OreESP or CONFIG.EntityESP or CONFIG.LocationESP or CONFIG.PlayerESP) then clearESP() end
            elseif configKey == "KukirinAntiLag" then
                applyKukirinAntiLag(CONFIG.KukirinAntiLag)
            elseif configKey == "KukirinPlayerESP" or configKey == "KukirinChams" then
                refreshKukirinPlayerVisuals()
            elseif configKey == "KukirinAutoWheelie" and not CONFIG.KukirinAutoWheelie then
                releaseKukirinKeys()
            end
        end,
    })
    return control
end

local function fluentSlider(tab, title, configKey, minimum, maximum, rounding, description)
    return tab:AddSlider("FF_" .. configKey, {
        Title = title,
        Description = description or "",
        Default = CONFIG[configKey],
        Min = minimum,
        Max = maximum,
        Rounding = rounding or 0,
        Callback = function(value) CONFIG[configKey] = value end,
    })
end

local function fluentButton(tab, title, description, callback)
    return tab:AddButton({ Title = title, Description = description or "", Callback = callback })
end

local function updateFluentParagraph(paragraph, value)
    if not paragraph then return end
    local ok = pcall(function()
        if type(paragraph.SetDesc) == "function" then
            paragraph:SetDesc(value)
        elseif type(paragraph.SetContent) == "function" then
            paragraph:SetContent(value)
        elseif paragraph.ContentLabel then
            paragraph.ContentLabel.Text = value
        end
    end)
    return ok
end

local fluentViewport = getViewportSize()
local fluentMobile = isTouchLayout()
local fluentWidth = fluentMobile and math.max(300, math.min(760, fluentViewport.X - 20)) or 760
local fluentHeight = fluentMobile and math.max(260, math.min(565, fluentViewport.Y - 48)) or 565
local fluentTabWidth = fluentMobile and math.max(88, math.min(132, math.floor(fluentWidth * 0.28))) or 150

local fluentOk, fluentError = pcall(function()
    Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
    FluentWindow = Fluent:CreateWindow({
        Title = "Revolver Hub",
        SubTitle = "V1.4  •  SECURE LICENSE",
        TabWidth = fluentTabWidth,
        Size = UDim2.fromOffset(fluentWidth, fluentHeight),
        Acrylic = true,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightControl,
    })

    FluentTabs = {
        Overview = FluentWindow:AddTab({ Title = "Overview", Icon = "layout-dashboard" }),
        Farm = FluentWindow:AddTab({ Title = "Farm", Icon = "pickaxe" }),
        Visuals = FluentWindow:AddTab({ Title = "Visuals", Icon = "scan-eye" }),
        Movement = FluentWindow:AddTab({ Title = "Movement", Icon = "person-standing" }),
        Stats = FluentWindow:AddTab({ Title = "Stats", Icon = "chart-no-axes-combined" }),
        Settings = FluentWindow:AddTab({ Title = "Settings", Icon = "settings" }),
        Console = FluentWindow:AddTab({ Title = "Console", Icon = "terminal" }),
    }
    if IS_KUKIRIN then
        FluentTabs.Kukirin = FluentWindow:AddTab({ Title = "Kukirin Life", Icon = "bike" })
    end

    FluentTabs.Overview:AddParagraph({
        Title = "REVOLVER HUB  /  V1.4",
        Content = "Premium automation dashboard  ·  Version 1.0\nServer-validated access  ·  Device-bound licenses\nRightControl minimizes the interface.",
    })
    OverviewParagraph = FluentTabs.Overview:AddParagraph({
        Title = "SESSION STATUS",
        Content = "Hub initialized. Configure modules from the tabs above.",
    })
    fluentButton(FluentTabs.Overview, "OPEN FARM MODULES", "Configure ore collection, selling and food automation.", function() FluentWindow:SelectTab(2) end)
    fluentButton(FluentTabs.Overview, "OPEN VISUALS", "Configure ESP overlays.", function() FluentWindow:SelectTab(3) end)
    fluentButton(FluentTabs.Overview, "STOP ALL MODULES / UNLOAD", "Disables loops, restores movement and unloads the UI.", function() if destroyHub then destroyHub() end end)

    FluentTabs.Farm:AddParagraph({ Title = "AUTOMATION", Content = "Serialized worker: farm, sell and eat actions are handled one at a time." })
    fluentToggle(FluentTabs.Farm, "Auto Grind", "AutoFarm", "Collect ores and safe loot; only pick food when its heal fits missing HP; never sell food or eat eggs; always drop Revivers; skip traps.")
    fluentToggle(FluentTabs.Farm, "Auto Sell Items", "AutoSell", "Sell carried ores whenever available.")
    fluentToggle(FluentTabs.Farm, "Auto Eat", "AutoEat", "Eat at 15+ missing HP: carrot 15, cooked carrot 30, ham 40, cooked ham 80; eggs never eaten.")
    fluentToggle(FluentTabs.Farm, "Auto Reviver", "AutoReviver", "Collect Revivers and always drop them; never sell, solo or multiplayer.")
    fluentSlider(FluentTabs.Farm, "Farm delay", "FarmDelay", 0.10, 2.00, 2, "Seconds between collection attempts.")
    fluentSlider(FluentTabs.Farm, "Sell delay", "SellDelay", 0.10, 2.00, 2, "Seconds between sell attempts.")
    fluentSlider(FluentTabs.Farm, "Eat interval", "EatDelay", 1.00, 15.00, 2, "Minimum time between food attempts.")

    FluentTabs.Visuals:AddParagraph({ Title = "ESP OVERLAYS", Content = "Highlights are reused and capped to avoid excessive instances." })
    fluentToggle(FluentTabs.Visuals, "Ore ESP", "OreESP", "Iron, Jade, Amethyst, Gold and Amber.")
    fluentToggle(FluentTabs.Visuals, "Entity ESP", "EntityESP", "Detect monster, enemy, entity, creature and boss models.")
    fluentToggle(FluentTabs.Visuals, "Location ESP", "LocationESP", "Spawn, exit, shop, station, elevator and safe zones.")
    fluentToggle(FluentTabs.Visuals, "Player ESP", "PlayerESP", "Highlight player character models.")

    FluentTabs.Movement:AddParagraph({ Title = "MOVEMENT CONTROLS", Content = "Original character values are restored when movement toggles are disabled." })
    fluentToggle(FluentTabs.Movement, "WalkSpeed override", "WalkSpeed", "Apply a custom WalkSpeed.")
    fluentSlider(FluentTabs.Movement, "WalkSpeed value", "WalkSpeedValue", 16, 100, 0, "Target WalkSpeed.")
    fluentToggle(FluentTabs.Movement, "HipHeight override", "HipHeight", "Apply a custom HipHeight.")
    fluentSlider(FluentTabs.Movement, "HipHeight value", "HipHeightValue", 0, 20, 2, "Target HipHeight.")
    fluentToggle(FluentTabs.Movement, "JumpPower override", "JumpPower", "Temporarily use JumpPower and restore the original setting.")
    fluentSlider(FluentTabs.Movement, "JumpPower value", "JumpPowerValue", 25, 150, 0, "Target JumpPower.")
    fluentToggle(FluentTabs.Movement, "Anti-AFK", "AntiAFK", "Attempts an idle input where VirtualUser is supported.")
    fluentToggle(FluentTabs.Movement, "NoclipCam (NCCam)", "NoclipCam", "Keep the camera attached to your character while it passes through walls.")

    if IS_KUKIRIN and FluentTabs.Kukirin then
        FluentTabs.Kukirin:AddParagraph({
            Title = "KUKIRIN LIFE / 122840796290491",
            Content = "Scooter assist and local performance controls. Trick farming and mod unlocking need the live scooter/shop structure to be confirmed first.",
        })
        fluentToggle(FluentTabs.Kukirin, "Auto Wheelie Assist", "KukirinAutoWheelie", "Uses Control + short Up taps with a light throttle pulse. You must be seated on your scooter.")
        fluentSlider(FluentTabs.Kukirin, "Wheelie tap interval", "KukirinWheelieTapInterval", 0.10, 0.75, 2, "Slower taps are easier to control on laggy clients.")
        fluentSlider(FluentTabs.Kukirin, "Throttle pulse", "KukirinThrottlePulse", 0.05, 0.40, 2, "Short W pulses instead of holding full throttle constantly.")
        fluentToggle(FluentTabs.Kukirin, "Player ESP", "KukirinPlayerESP", "Event-driven player outlines; one Highlight per player.")
        fluentToggle(FluentTabs.Kukirin, "Chams", "KukirinChams", "Filled through-wall player highlights. Works independently from outlines.")
        fluentToggle(FluentTabs.Kukirin, "Anti-Lag", "KukirinAntiLag", "Local-only: reduces shadows, particles, post effects, textures and reflections; restores originals when disabled.")
        fluentButton(FluentTabs.Kukirin, "SCAN ACTIVE SCOOTER", "Sit on your scooter first; prints its seat, model and physics objects to the Console tab.", scanKukirinRide)
        fluentButton(FluentTabs.Kukirin, "SCAN MOD / TRICK UI", "Open the scooter garage/mod menu or trick menu first, then scan. Prints matching UI names and ReplicatedStorage remotes to Console.", scanKukirinModAndTrickUI)
    end

    StatsParagraph = FluentTabs.Stats:AddParagraph({ Title = "LIVE SESSION METRICS", Content = "Collecting statistics..." })
    local LicenseParagraph = FluentTabs.Settings:AddParagraph({ Title = "LICENSE", Content = "Build: " .. BUILD_LABEL .. "\nOwner key selects Owner Beta; any other valid license selects Public Release. The selected key is saved locally and revalidated after teleports." })
    table.insert(BUILD_MODE_UPDATERS, function(buildLabel)
        updateFluentParagraph(LicenseParagraph, "Build: " .. buildLabel .. "\nOwner key selects Owner Beta; any other valid license selects Public Release. The selected key is saved locally and revalidated after teleports.")
    end)
    fluentButton(FluentTabs.Settings, "CHANGE / SWITCH ACCESS KEY", "Enter a different valid key. The current key is kept if validation fails.", beginKeySwitch)
    FluentTabs.Settings:AddParagraph({ Title = "INTERFACE", Content = "Fluent UI library · Dark theme · RightControl to minimize.\nUse Interface Manager to change supported themes and Save Manager to store UI configuration." })
    fluentButton(FluentTabs.Settings, "STOP / UNLOAD HUB", "Stops automation, disconnects events and restores movement.", function() if destroyHub then destroyHub() end end)
    DebugParagraph = FluentTabs.Console:AddParagraph({ Title = "RECENT LOGS", Content = "Waiting for log entries..." })
    fluentButton(FluentTabs.Console, "CLEAR LOGS", "Clear the local debug buffer.", function() table.clear(LOGS); log("Log cleared") end)

    local managerOK, managerError = pcall(function()
        local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
        local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()
        SaveManager:SetLibrary(Fluent)
        InterfaceManager:SetLibrary(Fluent)
        SaveManager:IgnoreThemeSettings()
        SaveManager:SetIgnoreIndexes({})
        InterfaceManager:SetFolder("RevolverHub")
        SaveManager:SetFolder("RevolverHub")
        InterfaceManager:BuildInterfaceSection(FluentTabs.Settings)
        SaveManager:BuildConfigSection(FluentTabs.Settings)
    end)
    if not managerOK then log("Optional Fluent managers unavailable: " .. tostring(managerError)) end

    FluentWindow:SelectTab(1)
    GUI.Enabled = false
    Fluent:Notify({ Title = "Revolver Hub", Content = "V1.4 Fluent loaded · secure license accepted", Duration = 6 })
end)

if not fluentOk then
    Fluent = nil
    GUI.Enabled = true
    warn("[Revolver Hub] Fluent failed to load; showing legacy fallback UI: " .. tostring(fluentError))
else
    log("Fluent interface initialized")
end

--// EVENTS
connect(Workspace.DescendantAdded, function(object)
    CONFIG.ESPDirty = true
    if IS_KUKIRIN and CONFIG.KukirinAntiLag then
        task.defer(optimizeKukirinObject, object)
    end
end)
connect(Lighting.DescendantAdded, function(object)
    if IS_KUKIRIN and CONFIG.KukirinAntiLag then
        task.defer(optimizeKukirinObject, object)
    end
end)
connect(Players.PlayerAdded, function(player)
    if IS_KUKIRIN then hookKukirinPlayer(player) end
end)
connect(Players.PlayerRemoving, function(player)
    removeKukirinPlayerVisual(player)
end)
if IS_KUKIRIN then
    for _, player in ipairs(Players:GetPlayers()) do
        hookKukirinPlayer(player)
    end
end
connect(Workspace.DescendantRemoving, function(object)
    CONFIG.ESPDirty = true
    removeHighlight(object)
end)

connect(LP.CharacterAdded, function()
    BASELINE_HUMANOID = nil
    BASELINE_MOVEMENT = nil
    task.wait(0.8)
    if RUNNING then
        updateMovement()
        log("Character respawn detected")
    end
end)

connect(LP.Idled, function()
    if not RUNNING or not CONFIG.AntiAFK then
        return
    end

    safeCall("Anti-AFK", function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end)

--// SHUTDOWN
destroyHub = function()
    if not RUNNING then
        return
    end

    RUNNING = false

    CONFIG.AutoFarm = false
    CONFIG.AutoSell = false
    CONFIG.AutoEat = false
    CONFIG.AutoReviver = false
    CONFIG.OreESP = false
    CONFIG.EntityESP = false
    CONFIG.LocationESP = false
    CONFIG.PlayerESP = false
    CONFIG.KukirinAutoWheelie = false
    CONFIG.KukirinPlayerESP = false
    CONFIG.KukirinChams = false
    if CONFIG.KukirinAntiLag then pcall(applyKukirinAntiLag, false) end
    releaseKukirinKeys()
    for player in pairs(KUKIRIN_PLAYER_HIGHLIGHTS) do removeKukirinPlayerVisual(player) end

    pcall(restoreMovement)
    pcall(function() setNoclipCam(false) end)
    CONFIG.NoclipCam = false
    pcall(clearEggPlatform)
    pcall(restoreMapAfterGrinding)

    for _, connection in ipairs(CONNECTIONS) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(CONNECTIONS)

    clearESP()
    pcall(function() ESP_FOLDER:Destroy() end)
    if Fluent then pcall(function() Fluent:Unload() end) end
    pcall(function() GUI:Destroy() end)
    pcall(function()
        KEY_GUI:Destroy()
    end)

    if ENV.RevolverHubV1 then
        ENV.RevolverHubV1 = nil
    end
    print("[Revolver Hub v1.4] Hub stopped and cleaned up")
end

--// TOPBAR
local minimizeButton = make("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -270, 0.5, 0),
    Size = UDim2.fromOffset(68, 25),
    BackgroundColor3 = COLORS.PanelHover,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "MINIMIZE",
    TextColor3 = COLORS.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 8,
}, Top)
addCorner(minimizeButton, 7)
connect(minimizeButton.Activated, function()
    Main.Visible = false
    if MOBILE_RESTORE then
        MOBILE_RESTORE.Visible = IS_MOBILE_UI
    end
end)

local killButton = make("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -190, 0.5, 0),
    Size = UDim2.fromOffset(68, 25),
    BackgroundColor3 = Color3.fromRGB(139, 49, 68),
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "STOP",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 9,
}, Top)
addCorner(killButton, 7)
connect(killButton.MouseEnter, function()
    tween(killButton, 0.12, { BackgroundColor3 = Color3.fromRGB(190, 57, 80) })
end)
connect(killButton.MouseLeave, function()
    tween(killButton, 0.12, { BackgroundColor3 = Color3.fromRGB(139, 49, 68) })
end)
connect(killButton.Activated, destroyHub)

MOBILE_RESTORE = make("TextButton", {
    Name = "MobileRestore",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 14, 1, -74),
    Size = UDim2.fromOffset(48, 48),
    BackgroundColor3 = COLORS.PanelHover,
    BorderSizePixel = 0,
    AutoButtonColor = true,
    Text = "RH",
    TextColor3 = COLORS.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    Visible = false,
    ZIndex = 100,
}, GUI)
addCorner(MOBILE_RESTORE, 14)
addStroke(MOBILE_RESTORE, COLORS.Accent, 0.15, 1.5)
connect(MOBILE_RESTORE.Activated, function()
    Main.Visible = true
    MOBILE_RESTORE.Visible = false
end)

local function applyLegacyResponsiveLayout()
    local viewport = getViewportSize()
    IS_MOBILE_UI = isTouchLayout()

    if IS_MOBILE_UI then
        local width = math.max(300, math.min(900, viewport.X - 18))
        local height = math.max(260, math.min(720, viewport.Y - 36))
        Main.Size = UDim2.fromOffset(width, height)
        Main.Position = UDim2.fromScale(0.5, 0.5)
        MainScale.Scale = math.min(CONFIG.UIScaleValue or 1, 1)

        Top.Size = UDim2.new(1, 0, 0, 60)
        logo.Position = UDim2.fromOffset(15, 15)
        logo.Size = UDim2.fromOffset(160, 28)
        logo.TextSize = 14
        subtitle.Visible = false
        statusLabel.Visible = false

        Sidebar.Position = UDim2.fromOffset(10, 66)
        Sidebar.Size = UDim2.new(1, -20, 0, 48)
        sidebarHeader.Visible = false
        sidebarFooter.Visible = false
        tabHolder.Position = UDim2.fromOffset(4, 4)
        tabHolder.Size = UDim2.new(1, -8, 1, -8)
        tabHolder.ScrollingDirection = Enum.ScrollingDirection.X
        tabHolder.ScrollBarThickness = 2
        tabLayout.FillDirection = Enum.FillDirection.Horizontal
        tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        tabLayout.Padding = UDim.new(0, 6)
        for name, button in pairs(TabButtons) do
            button.Size = UDim2.fromOffset(name == "Kukirin Life" and 112 or 94, 38)
            button.TextSize = 10
        end

        Content.Position = UDim2.fromOffset(10, 122)
        Content.Size = UDim2.new(1, -20, 1, -132)
        minimizeButton.Position = UDim2.new(1, -112, 0.5, 0)
        minimizeButton.Size = UDim2.fromOffset(48, 26)
        minimizeButton.TextSize = 8
        killButton.Position = UDim2.new(1, -58, 0.5, 0)
        killButton.Size = UDim2.fromOffset(48, 26)
        killButton.TextSize = 9
    else
        Main.Size = UDim2.fromOffset(900, 610)
        Main.Position = UDim2.fromScale(0.5, 0.5)
        MainScale.Scale = CONFIG.UIScaleValue or 1

        Top.Size = UDim2.new(1, 0, 0, 70)
        logo.Position = UDim2.fromOffset(24, 10)
        logo.Size = UDim2.fromOffset(300, 26)
        logo.TextSize = 18
        subtitle.Visible = true
        statusLabel.Visible = true

        Sidebar.Position = UDim2.fromOffset(14, 82)
        Sidebar.Size = UDim2.new(0, 184, 1, -96)
        sidebarHeader.Visible = true
        sidebarFooter.Visible = true
        tabHolder.Position = UDim2.fromOffset(9, 44)
        tabHolder.Size = UDim2.new(1, -18, 0, 300)
        tabHolder.ScrollingDirection = Enum.ScrollingDirection.Y
        tabHolder.ScrollBarThickness = 2
        tabLayout.FillDirection = Enum.FillDirection.Vertical
        tabLayout.Padding = UDim.new(0, 7)
        for _, button in pairs(TabButtons) do
            button.Size = UDim2.new(1, 0, 0, 42)
            button.TextSize = 11
        end

        Content.Position = UDim2.fromOffset(210, 82)
        Content.Size = UDim2.new(1, -224, 1, -96)
        minimizeButton.Position = UDim2.new(1, -270, 0.5, 0)
        minimizeButton.Size = UDim2.fromOffset(68, 25)
        killButton.Position = UDim2.new(1, -190, 0.5, 0)
        killButton.Size = UDim2.fromOffset(68, 25)
        MOBILE_RESTORE.Visible = false
    end

    if tabHolder.ScrollingDirection == Enum.ScrollingDirection.X then
        tabHolder.CanvasSize = UDim2.new(0, tabLayout.AbsoluteContentSize.X + 12, 0, 0)
    else
        tabHolder.CanvasSize = UDim2.new(0, 0, 0, tabLayout.AbsoluteContentSize.Y + 12)
    end
end

applyLegacyResponsiveLayout()
local responsiveCamera = Workspace.CurrentCamera
if responsiveCamera then
    connect(responsiveCamera:GetPropertyChangedSignal("ViewportSize"), applyLegacyResponsiveLayout)
end
connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
    task.defer(function()
        local camera = Workspace.CurrentCamera
        if camera then
            connect(camera:GetPropertyChangedSignal("ViewportSize"), applyLegacyResponsiveLayout)
        end
        applyLegacyResponsiveLayout()
    end)
end)

--// HOTKEY
if not Fluent then
    connect(UserInputService.InputBegan, function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.RightControl then
            Main.Visible = not Main.Visible
            if MOBILE_RESTORE then
                MOBILE_RESTORE.Visible = IS_MOBILE_UI and not Main.Visible
            end
        end
    end)
end

--// WORKER
local function automationWorker()
    local nextEatAt = 0
    while RUNNING do
        local didWork = false
        local farmActive = CONFIG.AutoFarm or CONFIG.AutoReviver

        if farmActive then
            local ok, reason = GRIND.liftMapForGrinding()
            if not ok then log("Map float unavailable: " .. tostring(reason)) end
        elseif GRIND.MapLifted then
            GRIND.restoreMapAfterGrinding()
            GRIND.returnToLiftedMap()
        end

        if farmActive then
            local targets = GRIND.findFarmTargets(CONFIG.AutoFarm)
            local target
            for _, candidate in ipairs(targets) do
                if candidate.Kind ~= "Reviver" or CONFIG.AutoFarm or CONFIG.AutoReviver then
                    if (OBJECT_COOLDOWNS[candidate.Object] or 0) <= os.clock() then
                        target = candidate
                        break
                    end
                end
            end

            if target then
                didWork = true
                local ok, detail = GRIND.processFarmTarget(target)
                if ok then
                    OBJECT_COOLDOWNS[target.Object] = os.clock() + (target.Kind == "Reviver" and 30 or 4)
                    log(detail)
                else
                    OBJECT_COOLDOWNS[target.Object] = os.clock() + (target.Kind == "Reviver" and 6 or 4)
                    STATS.PickupFails = STATS.PickupFails + 1
                    log("Autogrind skipped: " .. tostring(detail))
                end
                GRIND.returnToLiftedMap()
                task.wait(CONFIG.FarmDelay)
            elseif CONFIG.AutoFarm then
                local fallback = GRIND.nextFallbackTarget()
                if fallback then
                    didWork = true
                    local ok, detail
                    if isFood(fallback.Name) then
                        if not GRIND.shouldPickupFood(fallback.Name) then
                            ok, detail = false, "Food ignored; no matching heal is needed"
                        else
                            local prompt = findPrompt(fallback)
                            local position = getObjectPosition(fallback)
                            if prompt and position and teleportForPickup(position, fallback.Name) then
                                task.wait(0.18)
                                if activatePrompt(prompt) then
                                    ok, detail = GRIND.eatWorldPickupAfterPrompt(fallback)
                                else
                                    ok, detail = false, "Fallback food prompt failed"
                                end
                            else
                                ok, detail = false, "Fallback food prompt/position missing"
                            end
                        end
                    else
                        ok, detail = GRIND.sellWorldPickup(fallback)
                    end
                    if ok then
                        OBJECT_COOLDOWNS[fallback] = os.clock() + (fallback.Name == "Carrot" and 8 or 4)
                        log("Fallback pickup: " .. tostring(detail))
                    else
                        OBJECT_COOLDOWNS[fallback] = os.clock() + (isFood(fallback.Name) and 5 or 4)
                        STATS.PickupFails = STATS.PickupFails + 1
                        log("Fallback pickup skipped: " .. tostring(detail))
                    end
                    GRIND.returnToLiftedMap()
                    task.wait(CONFIG.SellDelay)
                else
                    task.wait(0.2)
                end
            end
        end

        if RUNNING and CONFIG.AutoSell then
            local tool = nextOreTool()
            if tool then
                didWork = true
                local ok, detail = sellTool(tool)
                if not ok then
                    SELL_COOLDOWNS[tool] = os.clock() + 4
                    STATS.SellFails = STATS.SellFails + 1
                    log("Sale skipped: " .. tostring(detail))
                else
                    SELL_COOLDOWNS[tool] = nil
                    log(detail or "Ore sold")
                end
                GRIND.returnToLiftedMap()
                task.wait(CONFIG.SellDelay)
            end
        end

        if RUNNING and CONFIG.AutoEat and os.clock() >= nextEatAt then
            local humanoid = getHumanoid()
            local injured = humanoid and humanoid.Health < (humanoid.MaxHealth - 0.5)
            if injured then
                didWork = true
                local ok, detail = eatFood()
                if ok then
                    log(detail)
                elseif detail ~= "No food found" and detail ~= "No food found in inventory or world" then
                    log(detail)
                end
            end
            nextEatAt = os.clock() + CONFIG.EatDelay
        end

        if not didWork then task.wait(0.2) end
    end
    if GRIND.MapLifted then GRIND.restoreMapAfterGrinding() end
end

--// REFRESH
task.spawn(function()
    while RUNNING do
        if CONFIG.OreESP or CONFIG.EntityESP or CONFIG.LocationESP or CONFIG.PlayerESP then
            safeCall("ESP scan", scanESP)
        else
            clearESP()
        end
        task.wait(1.75)
    end
end)

task.spawn(function()
    while RUNNING do
        if CONFIG.WalkSpeed or CONFIG.HipHeight or CONFIG.JumpPower then
            safeCall("Movement update", updateMovement)
        else
            restoreMovement()
        end
        task.wait(0.2)
    end
end)

task.spawn(function()
    while RUNNING do
        local elapsed = math.floor(os.clock() - STATS.StartedAt)
        local tools = getAllTools()
        local oreCount = countOreTools()
        local active = CONFIG.AutoFarm or CONFIG.AutoSell or CONFIG.AutoEat or CONFIG.AutoReviver
            or CONFIG.OreESP or CONFIG.EntityESP or CONFIG.LocationESP or CONFIG.PlayerESP
            or CONFIG.WalkSpeed or CONFIG.HipHeight or CONFIG.JumpPower or CONFIG.AntiAFK or CONFIG.NoclipCam

        statusLabel.Text = active and "● SYSTEM ACTIVE" or "● READY"
        statusLabel.TextColor3 = active and COLORS.Green or COLORS.Muted

        if CONFIG.UIScaleValue then
            UI_SETTINGS.Scale = CONFIG.UIScaleValue
            MainScale.Scale = IS_MOBILE_UI and math.min(CONFIG.UIScaleValue, 1) or CONFIG.UIScaleValue
        end
        if CONFIG.RainbowUI then
            local hue = (os.clock() * 0.055) % 1
            local rainbowA = Color3.fromHSV(hue, 0.72, 1)
            local rainbowB = Color3.fromHSV((hue + 0.12) % 1, 0.62, 1)
            local oldA = COLORS.Accent
            COLORS.Accent, COLORS.Accent2 = rainbowA, rainbowB
            for _, object in ipairs(GUI:GetDescendants()) do
                pcall(function()
                    if object:IsA("UIStroke") and object.Color == oldA then object.Color = rainbowA end
                    if (object:IsA("Frame") or object:IsA("TextButton")) and object.BackgroundColor3 == oldA then
                        object.BackgroundColor3 = rainbowA
                    end
                    if object:IsA("ScrollingFrame") then object.ScrollBarImageColor3 = rainbowA end
                end)
            end
            previewAccent.BackgroundColor3 = rainbowA
            keyStroke.Color = rainbowA
        end

        local statsText = string.format(
            "SESSION TIME       %02d:%02d:%02d\nINVENTORY TOOLS    %d\nORES IN INVENTORY  %d\nORES COLLECTED     %d\nREVIVERS COLLECTED %d\nITEMS SOLD         %d\nFOODS USED         %d\nPICKUP FAILURES    %d\nSELL FAILURES      %d\nESP OBJECT LIMIT   %d",
            math.floor(elapsed / 3600),
            math.floor((elapsed % 3600) / 60),
            elapsed % 60,
            #tools,
            oreCount,
            STATS.OresCollected,
            STATS.ReviversCollected,
            STATS.ItemsSold,
            STATS.FoodsUsed,
            STATS.PickupFails,
            STATS.SellFails,
            MAX_HIGHLIGHTS
        )
        StatsLabel.Text = statsText
        updateFluentParagraph(StatsParagraph, statsText)
        updateFluentParagraph(OverviewParagraph, "Status: " .. (active and "ACTIVE" or "READY") .. "\nUptime: " .. string.format("%02d:%02d:%02d", math.floor(elapsed / 3600), math.floor((elapsed % 3600) / 60), elapsed % 60) .. "\nOres collected: " .. STATS.OresCollected .. "  ·  Items sold: " .. STATS.ItemsSold)

        local recent = {}
        local startIndex = math.max(1, #LOGS - 22)
        for i = startIndex, #LOGS do
            table.insert(recent, LOGS[i])
        end
        local recentText = #recent > 0 and table.concat(recent, "\n") or "No log entries yet."
        DebugLabel.Text = recentText
        updateFluentParagraph(DebugParagraph, recentText)

        task.wait(0.5)
    end
end)

task.spawn(automationWorker)
if IS_KUKIRIN then
    task.spawn(kukirinWheelieWorker)
end

--// INIT
showPage("Overview")
log("Revolver Hub v1.4 " .. BUILD_LABEL .. " loaded")
notify(BUILD_LABEL .. " access granted · Hub ready", "success")

ENV.RevolverHubV1 = {
    Destroy = destroyHub,
    Version = "1.4-" .. BUILD_CHANNEL,
    Build = BUILD_CHANNEL,
    ChangeKey = beginKeySwitch,
}
