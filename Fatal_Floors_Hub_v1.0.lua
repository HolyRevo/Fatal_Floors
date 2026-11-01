-- Fatal Floors Hub v1.0 single-file key-based bootstrap
local __ffenv = _G
if type(getgenv) == "function" then
    local __ok, __value = pcall(getgenv)
    if __ok and type(__value) == "table" then __ffenv = __value end
end
if type(loadstring) ~= "function" then error("This executor needs loadstring support.") end
__ffenv.FatalFloorsAutoExecSource = [====[
--[[
    FATAL FLOORS HUB v1.0 | SINGLE-FILE KEY-BASED BUILD
    ------------------------------------------------------------
    Features:
      - Supabase-backed license validation and owner-key verification
      - LootLabs-only provider gate
      - Fluent UI dashboard with tabs, notifications and settings
      - AutoFarm: Iron, Jade, Amethyst, Gold and Amber
      - AutoSell with inventory-change verification
      - AutoEat with one request per attempt
      - Ore / entity / location / player ESP
      - WalkSpeed / HipHeight / JumpPower with baseline restoration
      - Anti-AFK attempt
      - Decimal sliders, debug log, statistics and full cleanup

    Compatibility note:
      This is a client-side executor script. Game object paths, prompt access,
      and the FoodEatRequest argument are based on the supplied v4 description
      and may need adjustment if Fatal Floors changes its implementation.
]]

--// SERVICES
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
if not LP then
    return
end

--// EXECUTOR ENVIRONMENT / RE-EXECUTION CLEANUP
local ENV = _G
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then
        ENV = result
    end
end

if type(ENV.FatalFloorsV8) == "table" and type(ENV.FatalFloorsV8.Destroy) == "function" then
    pcall(ENV.FatalFloorsV8.Destroy)
end

--// KEY-SELECTED BUILD + TELEPORT AUTO-REEXECUTE
-- Both access tiers run from this one file. Supabase's validation response
-- selects OWNER BETA when owner=true, otherwise PUBLIC RELEASE.
local BUILD_CHANNEL = "release"
local BUILD_LABEL = "KEY REQUIRED"
local BUILD_MODE_UPDATERS = {}
-- One shared loader is used because the key determines the build at runtime.
local AUTOEXEC_FILE = "FatalFloorsHub_AutoExec.lua"
local AUTOEXEC_BOOTSTRAP = type(ENV.FatalFloorsAutoExecSource) == "string"
    and ENV.FatalFloorsAutoExecSource or ""
ENV.FatalFloorsAutoExecSource = nil

-- Save this self-contained script for queue_on_teleport. On re-entry it reads
-- the saved key and Supabase selects the correct build again automatically.
if AUTOEXEC_BOOTSTRAP ~= "" and type(writefile) == "function" then
    local saved, saveError = pcall(writefile, AUTOEXEC_FILE, AUTOEXEC_BOOTSTRAP)
    if not saved then
        warn("[Fatal Floors] Could not save teleport loader: " .. tostring(saveError))
    end
end

--// GLOBAL STATE
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
    PickupFails = 0,
    SellFails = 0,
}

local CONFIG = {
    AutoFarm = false,
    AutoSell = false,
    AutoEat = false,

    OreESP = false,
    EntityESP = false,
    LocationESP = false,
    PlayerESP = false,

    WalkSpeed = false,
    HipHeight = false,
    JumpPower = false,
    AntiAFK = false,

    WalkSpeedValue = 24,
    HipHeightValue = 3,
    JumpPowerValue = 65,
    RainbowUI = false,
    UIScaleValue = 1,

    FarmDelay = 0.35,
    SellDelay = 0.5,
    EatDelay = 2.0,
}

local Fluent, FluentWindow, FluentTabs, StatsParagraph, DebugParagraph, OverviewParagraph

--// AURORA UI SETTINGS
local UI_SETTINGS = {
    Scale = 1,
    Rainbow = false,
    Accent = Color3.fromRGB(125, 105, 255),
    Accent2 = Color3.fromRGB(58, 210, 226),
    ThemeName = "Aurora",
}

--// GENERAL HELPERS
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
    print("[Fatal Floors v8] " .. tostring(message))
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

--// SERVER-SIDE KEY VALIDATION
-- Only the publishable key is embedded in the script. Provider/API secrets stay in Supabase.
local SUPABASE_FUNCTION_URL = "https://fikrsilwzmlegjtkqglc.supabase.co/functions/v1/fatalfloors-auth"
local SUPABASE_PUBLISHABLE_KEY = "sb_publishable_6vEJtA84VBevLYzbpDwzZw_H8emmQ60"
local DEVICE_ID_FILE = "FatalFloorsHubDevice.txt"
local KEY_PROVIDER = "app" -- LootLabs-issued app keys
local API_CONFIG = nil

local function getDeviceId()
    local deviceId = ENV.FatalFloorsV8_DeviceId
    if type(deviceId) == "string" and #deviceId >= 8 then
        return deviceId
    end
    if type(isfile) == "function" and type(readfile) == "function" then
        local ok, value = pcall(function()
            if isfile(DEVICE_ID_FILE) then return readfile(DEVICE_ID_FILE) end
        end)
        if ok and type(value) == "string" and #value >= 8 then
            ENV.FatalFloorsV8_DeviceId = value
            return value
        end
    end
    deviceId = HttpService:GenerateGUID(false) .. HttpService:GenerateGUID(false)
    ENV.FatalFloorsV8_DeviceId = deviceId
    if type(writefile) == "function" then
        pcall(writefile, DEVICE_ID_FILE, deviceId)
    end
    return deviceId
end

local DEVICE_ID = getDeviceId()

-- The active key is saved locally so re-executions after teleports can reuse it.
-- This is a plaintext executor file; do not share the file with anyone.
local ACTIVE_KEY_FILE = "FatalFloorsHubAccessKey.txt"
local ACTIVE_ACCESS_KEY = nil
local ACTIVE_KEY_IS_OWNER = false

local function loadSavedAccessKey()
    local cached = ENV.FatalFloorsV8_ActiveKey
    if type(cached) == "string" and #cached > 0 then
        ACTIVE_ACCESS_KEY = cached
        return cached
    end
    if type(readfile) == "function" then
        local ok, value = pcall(function()
            if type(isfile) == "function" and not isfile(ACTIVE_KEY_FILE) then
                return nil
            end
            return readfile(ACTIVE_KEY_FILE)
        end)
        if ok and type(value) == "string" and #value > 0 then
            ACTIVE_ACCESS_KEY = value
            ENV.FatalFloorsV8_ActiveKey = value
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
    ENV.FatalFloorsV8_ActiveKey = value
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
        -- The server, not a client-side hard-coded key, decides owner status.
        local isOwner = data.owner == true
        return true, data.message or "Access granted", isOwner
    end
    return false, (data and data.message) or err or ("Validation failed (HTTP " .. tostring(status) .. ")"), false
end

local KEY_GUI = Instance.new("ScreenGui")
KEY_GUI.Name = "FatalFloorsV8_KeyGate"
KEY_GUI.ResetOnSpawn = false
KEY_GUI.IgnoreGuiInset = true
mountGui(KEY_GUI)

local keyBackdrop = Instance.new("Frame")
keyBackdrop.Name = "Backdrop"
keyBackdrop.Size = UDim2.fromScale(1, 1)
keyBackdrop.BackgroundColor3 = Color3.fromRGB(5, 7, 13)
keyBackdrop.BackgroundTransparency = 0.18
keyBackdrop.BorderSizePixel = 0
keyBackdrop.Parent = KEY_GUI

local keyCard = Instance.new("Frame")
keyCard.Name = "KeyCard"
keyCard.AnchorPoint = Vector2.new(0.5, 0.5)
keyCard.Position = UDim2.fromScale(0.5, 0.5)
keyCard.Size = UDim2.fromOffset(450, 382)
keyCard.BackgroundColor3 = Color3.fromRGB(17, 20, 31)
keyCard.BorderSizePixel = 0
keyCard.Parent = keyBackdrop
Instance.new("UICorner", keyCard).CornerRadius = UDim.new(0, 16)

local keyStroke = Instance.new("UIStroke")
keyStroke.Color = Color3.fromRGB(112, 91, 255)
keyStroke.Transparency = 0.22
keyStroke.Thickness = 1.3
keyStroke.Parent = keyCard

local keyHeader = Instance.new("Frame")
keyHeader.Size = UDim2.new(1, 0, 0, 70)
keyHeader.BackgroundColor3 = Color3.fromRGB(91, 68, 220)
keyHeader.BorderSizePixel = 0
keyHeader.Parent = keyCard
Instance.new("UICorner", keyHeader).CornerRadius = UDim.new(0, 16)

local headerGradient = Instance.new("UIGradient")
headerGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(106, 76, 245)),
    ColorSequenceKeypoint.new(0.55, Color3.fromRGB(44, 147, 219)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(106, 76, 245)),
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
keyTitle.Size = UDim2.new(1, -82, 0, 25)
keyTitle.Font = Enum.Font.GothamBold
keyTitle.Text = "FATAL FLOORS HUB"
keyTitle.TextColor3 = Color3.new(1, 1, 1)
keyTitle.TextSize = 18
keyTitle.TextXAlignment = Enum.TextXAlignment.Left
keyTitle.Parent = keyHeader

local keySubtitle = Instance.new("TextLabel")
keySubtitle.BackgroundTransparency = 1
keySubtitle.Position = UDim2.fromOffset(21, 37)
keySubtitle.Size = UDim2.new(1, -82, 0, 17)
keySubtitle.Font = Enum.Font.Gotham
keySubtitle.Text = "V1.0 · SINGLE FILE · KEY-SELECTED BUILD"
keySubtitle.TextColor3 = Color3.fromRGB(228, 229, 255)
keySubtitle.TextSize = 10
keySubtitle.TextXAlignment = Enum.TextXAlignment.Left
keySubtitle.Parent = keyHeader

local keyClose = Instance.new("TextButton")
keyClose.Name = "CloseButton"
keyClose.AnchorPoint = Vector2.new(1, 0)
keyClose.Position = UDim2.new(1, -12, 0, 12)
keyClose.Size = UDim2.fromOffset(30, 30)
keyClose.BackgroundColor3 = Color3.fromRGB(18, 22, 38)
keyClose.BackgroundTransparency = 0.18
keyClose.BorderSizePixel = 0
keyClose.AutoButtonColor = false
keyClose.Font = Enum.Font.GothamBold
keyClose.Text = "×"
keyClose.TextColor3 = Color3.fromRGB(255, 255, 255)
keyClose.TextSize = 22
keyClose.Parent = keyHeader
Instance.new("UICorner", keyClose).CornerRadius = UDim.new(0, 9)

-- Drag the key window from its header. Works with mouse and touch input.
local dragging = false
local dragInput = nil
local dragStart = nil
local startPosition = nil
connect(keyHeader.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = keyCard.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
connect(keyHeader.InputChanged, function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
connect(UserInputService.InputChanged, function(input)
    if dragging and dragInput and input == dragInput then
        local delta = input.Position - dragStart
        keyCard.Position = UDim2.new(
            startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
        )
    end
end)

local keyPrompt = Instance.new("TextLabel")
keyPrompt.BackgroundTransparency = 1
keyPrompt.Position = UDim2.fromOffset(22, 82)
keyPrompt.Size = UDim2.new(1, -44, 0, 20)
keyPrompt.Font = Enum.Font.GothamMedium
keyPrompt.Text = "Owner key → Owner Beta · Normal key → Public Release"
keyPrompt.TextColor3 = Color3.fromRGB(224, 227, 241)
keyPrompt.TextSize = 12
keyPrompt.TextXAlignment = Enum.TextXAlignment.Left
keyPrompt.Parent = keyCard

local function applyBuildForKey(isOwner)
    BUILD_CHANNEL = isOwner and "owner-beta" or "release"
    BUILD_LABEL = isOwner and "OWNER BETA" or "PUBLIC RELEASE"
    ENV.FatalFloorsV8_Build = BUILD_CHANNEL

    keyTitle.Text = "FATAL FLOORS HUB · " .. BUILD_LABEL
    keySubtitle.Text = "V1.0 · " .. BUILD_LABEL .. " · FLUENT EDITION"
    keyPrompt.Text = isOwner
        and "Owner key detected · Owner Beta enabled"
        or "Release key detected · Public Release enabled"

    for _, updater in ipairs(BUILD_MODE_UPDATERS) do
        pcall(updater, BUILD_LABEL, BUILD_CHANNEL)
    end
    if type(ENV.FatalFloorsV8) == "table" then
        ENV.FatalFloorsV8.Build = BUILD_CHANNEL
        ENV.FatalFloorsV8.Version = "1.0-" .. BUILD_CHANNEL
    end
end

local keyBox = Instance.new("TextBox")
keyBox.Position = UDim2.fromOffset(22, 111)
keyBox.Size = UDim2.new(1, -44, 0, 43)
keyBox.BackgroundColor3 = Color3.fromRGB(28, 32, 47)
keyBox.BorderSizePixel = 0
keyBox.ClearTextOnFocus = false
keyBox.Font = Enum.Font.Gotham
keyBox.PlaceholderText = "Access key..."
keyBox.PlaceholderColor3 = Color3.fromRGB(124, 132, 157)
keyBox.Text = loadSavedAccessKey() or ""
keyBox.TextColor3 = Color3.new(1, 1, 1)
keyBox.TextSize = 13
keyBox.Parent = keyCard
Instance.new("UICorner", keyBox).CornerRadius = UDim.new(0, 9)

local keyButton = Instance.new("TextButton")
keyButton.Position = UDim2.fromOffset(22, 166)
keyButton.Size = UDim2.new(1, -44, 0, 40)
keyButton.BackgroundColor3 = Color3.fromRGB(105, 82, 245)
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
lootLabsButton.BackgroundColor3 = Color3.fromRGB(105, 82, 245)
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

connect(providerButtons.lootlabs.MouseButton1Click, function()
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

connect(keyClose.MouseButton1Click, function()
    -- Closing the gate exits instead of leaving a hidden, half-running script.
    RUNNING = false
    if KEY_GUI and KEY_GUI.Parent then
        KEY_GUI:Destroy()
    end
end)
connect(keyClose.MouseEnter, function()
    tween(keyClose, 0.12, { BackgroundColor3 = Color3.fromRGB(205, 62, 82) })
end)
connect(keyClose.MouseLeave, function()
    tween(keyClose, 0.12, { BackgroundColor3 = Color3.fromRGB(18, 22, 38) })
end)

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
connect(keyButton.MouseButton1Click, submitKey)
connect(keyBox.FocusLost, function(enterPressed)
    if enterPressed then
        submitKey()
    end
end)
connect(keyButton.MouseEnter, function()
    tween(keyButton, 0.15, { BackgroundColor3 = Color3.fromRGB(128, 105, 255) })
end)
connect(keyButton.MouseLeave, function()
    tween(keyButton, 0.15, { BackgroundColor3 = Color3.fromRGB(105, 82, 245) })
end)

-- Automatically validate the locally saved key after re-execution.
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

-- Executors with queue_on_teleport support will rerun this exact build after
-- a Roblox teleport (for example, moving from a lobby into a match/server).
local function queueAutoReexecute()
    local queueFunction = nil
    if type(queue_on_teleport) == "function" then
        queueFunction = queue_on_teleport
    elseif type(queueonteleport) == "function" then
        queueFunction = queueonteleport
    elseif type(syn) == "table" and type(syn.queue_on_teleport) == "function" then
        queueFunction = syn.queue_on_teleport
    elseif type(fluxus) == "table" and type(fluxus.queue_on_teleport) == "function" then
        queueFunction = fluxus.queue_on_teleport
    end
    if not queueFunction then
        return false, "This executor does not expose queue_on_teleport."
    end
    local escapedFile = string.format("%q", AUTOEXEC_FILE)
    local queuedSource = "local ok,src=pcall(readfile," .. escapedFile .. "); "
        .. "if ok and type(src)=='string' and type(loadstring)=='function' then "
        .. "local fn,err=loadstring(src); if fn then fn() else warn(err) end "
        .. "else warn('Fatal Floors auto-execute file unavailable') end"
    local ok, err = pcall(queueFunction, queuedSource)
    if not ok then
        return false, tostring(err)
    end
    return true, "Teleport auto-execute queued."
end

local autoQueued, autoQueueMessage = queueAutoReexecute()
if autoQueued then
    log(BUILD_LABEL .. " teleport re-execution armed")
else
    log("Teleport re-execution unavailable: " .. tostring(autoQueueMessage))
end

pcall(function()
    connect(LP.OnTeleport, function(teleportState)
        if teleportState == Enum.TeleportState.Started then
            queueAutoReexecute()
        end
    end)
end)

--// CHARACTER / INVENTORY HELPERS
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

local function teleportNear(position)
    local root = getRoot()
    if not root or typeof(position) ~= "Vector3" then
        return false
    end

    local ok = pcall(function()
        root.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0))
    end)
    return ok
end

--// ITEM CLASSIFICATION (AMBER INCLUDED)
local ORE_NAMES = {
    "iron",
    "jade",
    "amethyst",
    "gold",
    "amber",
}

local FOOD_NAMES = {
    "food",
    "apple",
    "berry",
    "berries",
    "mushroom",
    "meat",
    "fish",
    "meal",
    "bread",
    "steak",
    "carrot",
}

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
    return containsAny(name, ORE_NAMES)
end

local function isFood(name)
    return containsAny(name, FOOD_NAMES)
end

local function findFood()
    for _, tool in ipairs(getAllTools()) do
        if isFood(tool.Name) then
            return tool
        end
    end
    return nil
end

--// PROMPT HELPERS
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

    -- Use one activation method per attempt. This avoids duplicate prompt fires.
    if type(fireproximityprompt) == "function" then
        local ok = pcall(function()
            fireproximityprompt(prompt)
        end)
        if ok then
            return true
        end
    end

    local ok = pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(0.1, tonumber(prompt.HoldDuration) or 0.1))
        prompt:InputHoldEnd()
    end)
    return ok
end

--// AUTOFARM
local function getOreFolder()
    local generated = Workspace:FindFirstChild("ProcGenGenerated")
    return generated and generated:FindFirstChild("ProcGenItems") or nil
end

local function nextFarmTarget()
    local folder = getOreFolder()
    if not folder then
        return nil, "Ore folder missing"
    end

    for _, object in ipairs(folder:GetChildren()) do
        if RUNNING and CONFIG.AutoFarm and object.Parent and isOre(object.Name) then
            local cooldownUntil = OBJECT_COOLDOWNS[object] or 0
            if os.clock() >= cooldownUntil then
                return object
            end
        end
    end
    return nil
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

local function collectOre(object)
    if not object or not object.Parent then
        return false, "Ore no longer exists"
    end

    local prompt = findPrompt(object)
    local position = getObjectPosition(object)
    if not prompt or not position then
        return false, "Ore prompt or position missing"
    end

    local before = inventoryCounts()
    if not teleportNear(position) then
        return false, "Could not move to ore"
    end

    task.wait(0.18)
    if not RUNNING or not CONFIG.AutoFarm then
        return false, "Farm disabled"
    end

    if not activatePrompt(prompt) then
        return false, "Prompt activation failed"
    end

    local deadline = os.clock() + 2.5
    repeat
        task.wait(0.1)
        if hasNewOre(before) then
            STATS.OresCollected = STATS.OresCollected + 1
            return true
        end
    until os.clock() >= deadline or not RUNNING

    return false, "No matching inventory change detected"
end

--// AUTOSELL
local function getSellSpot()
    local tiles = Workspace:FindFirstChild("PlacedTiles")
    local station = tiles and tiles:FindFirstChild("SellStation")
    local spot = station and station:FindFirstChild("SellingSpot")
    if not spot then
        return nil, nil
    end
    return spot, findPrompt(spot)
end

local function nextOreTool()
    for _, tool in ipairs(getAllTools()) do
        if isOre(tool.Name) and (SELL_COOLDOWNS[tool] or 0) <= os.clock() then
            return tool
        end
    end
    return nil
end

local function sellTool(tool)
    if not tool or not tool.Parent then
        return false, "Ore tool missing"
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

--// AUTOEAT
local function getFoodRemote()
    local remote = ReplicatedStorage:FindFirstChild("FoodEatRequest", true)
    if remote and remote:IsA("RemoteEvent") then
        return remote
    end
    return nil
end

local function eatFood()
    local food = findFood()
    if not food then
        return false, "No food found"
    end

    if not equipTool(food) then
        return false, "Could not equip food"
    end

    task.wait(0.12)
    local remote = getFoodRemote()
    local beforeCount = countTool(food.Name)
    local ok, err

    if remote then
        -- The v4 script used the food name as the remote argument.
        -- Do not also Activate() the Tool: that can double-consume food.
        ok, err = pcall(function()
            remote:FireServer()
        end)
    else
        ok, err = pcall(function()
            food:Activate()
        end)
    end

    if not ok then
        return false, "Food request failed: " .. tostring(err)
    end

    -- Food may affect a hunger stat that this script cannot read. Confirm
    -- tool removal where possible; otherwise report the request as unverified.
    task.wait(0.35)
    if countTool(food.Name) < beforeCount then
        STATS.FoodsUsed = STATS.FoodsUsed + 1
        return true, "Food consumption verified"
    end

    return true, "Food request sent; consumption could not be verified"
end

--// MOVEMENT WITH BASELINE RESTORATION
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

--// ESP
local ESP_FOLDER = Instance.new("Folder")
ESP_FOLDER.Name = "FatalFloorsV8_ESP"
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

--// GUI HELPERS
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

--// MAIN GUI
local GUI = Instance.new("ScreenGui")
GUI.Name = "FatalFloorsV8_LegacyHidden"
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
    Text = "FATAL FLOORS",
    TextColor3 = COLORS.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    TextXAlignment = Enum.TextXAlignment.Left,
}, Top)

local subtitle = make("TextLabel", {
    Position = UDim2.fromOffset(25, 39),
    Size = UDim2.fromOffset(330, 17),
    BackgroundTransparency = 1,
    Text = "AURORA EDITION  •  V8  •  SECURE LICENSE",
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

local tabHolder = make("Frame", {
    Position = UDim2.fromOffset(9, 44),
    Size = UDim2.new(1, -18, 0, 300),
    BackgroundTransparency = 1,
}, Sidebar)
local tabLayout = make("UIListLayout", {
    Padding = UDim.new(0, 7),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, tabHolder)

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

    connect(button.MouseButton1Click, function()
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

    connect(switch.MouseButton1Click, function()
        CONFIG[configKey] = not CONFIG[configKey]
        refresh()
        log(title .. (CONFIG[configKey] and " enabled" or " disabled"))
        if configKey == "WalkSpeed" or configKey == "HipHeight" or configKey == "JumpPower" then
            updateMovement()
        elseif configKey == "OreESP" or configKey == "EntityESP" or configKey == "LocationESP" or configKey == "PlayerESP" then
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
    connect(button.MouseButton1Click, callback)
    return button
end

--// TOAST NOTIFICATIONS
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
                Title = kind == "error" and "Fatal Floors · Error" or (kind == "success" and "Fatal Floors · Success" or "Fatal Floors Hub"),
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

--// PAGE CONTENT: OVERVIEW
section(HomePage, "Welcome back", "Your Fatal Floors control center · Aurora interface")
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
    Text = "AURORA  /  FATAL FLOORS",
    TextColor3 = COLORS.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left,
}, welcomeCard)
make("TextLabel", {
    Position = UDim2.fromOffset(18, 49),
    Size = UDim2.new(1, -36, 0, 42),
    BackgroundTransparency = 1,
    Text = "A cleaner, smoother command center.\nToggle modules, tune your setup and watch your session live.",
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

--// PAGE CONTENT: FARM
section(FarmPage, "Automation", "Run one task at a time to prevent farm/sell conflicts")
createToggle(FarmPage, "Auto Farm", "AutoFarm", "Collect Iron, Jade, Amethyst, Gold and Amber")
createToggle(FarmPage, "Auto Sell", "AutoSell", "Sell ore tools and check that inventory decreases")
createToggle(FarmPage, "Auto Eat", "AutoEat", "Use detected food at the selected interval")
section(FarmPage, "Timing", "All values are real seconds; decimal steps are supported")
createSlider(FarmPage, "Farm delay (sec)", "FarmDelay", 0.10, 2.00, 0.05)
createSlider(FarmPage, "Sell delay (sec)", "SellDelay", 0.10, 2.00, 0.05)
createSlider(FarmPage, "Eat interval (sec)", "EatDelay", 1.00, 15.00, 0.25)

--// PAGE CONTENT: VISUALS
section(VisualPage, "ESP modules", "Highlights are reused instead of recreated every scan")
createToggle(VisualPage, "Ore ESP", "OreESP", "Iron, Jade, Amethyst, Gold and Amber")
createToggle(VisualPage, "Entity ESP", "EntityESP", "Names containing monster, enemy, entity, creature or boss")
createToggle(VisualPage, "Location ESP", "LocationESP", "Spawn, exit, shop, station, elevator and safe zones")
createToggle(VisualPage, "Player ESP", "PlayerESP", "Highlight player character models")

--// PAGE CONTENT: MOVEMENT
section(MovementPage, "Movement", "Values restore to the character's original settings when disabled")
createToggle(MovementPage, "WalkSpeed", "WalkSpeed", "Apply a custom WalkSpeed")
createSlider(MovementPage, "WalkSpeed value", "WalkSpeedValue", 16, 100, 1)
createToggle(MovementPage, "HipHeight", "HipHeight", "Apply a custom HipHeight")
createSlider(MovementPage, "HipHeight value", "HipHeightValue", 0, 20, 0.25)
createToggle(MovementPage, "JumpPower", "JumpPower", "Temporarily enables UseJumpPower and restores its old value")
createSlider(MovementPage, "JumpPower value", "JumpPowerValue", 25, 150, 1)
createToggle(MovementPage, "Anti-AFK", "AntiAFK", "Attempts an idle input using VirtualUser where supported")

--// PAGE CONTENT: STATS
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

--// PAGE CONTENT: SETTINGS
section(SettingsPage, "Access and license", "Build is selected by your key · saved key auto-validates after teleports")
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
    Text = UI_SETTINGS.ThemeName .. "  ·  Aurora palette",
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
    {"Aurora", Color3.fromRGB(125, 105, 255), Color3.fromRGB(58, 210, 226)},
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
createButton(SettingsPage, "Hide / show hub  [RightControl]", function()
    Main.Visible = not Main.Visible
end, COLORS.PanelHover)
createButton(SettingsPage, "RESET INTERFACE SCALE", function()
    CONFIG.UIScaleValue = 1
    UI_SETTINGS.Scale = 1
    MainScale.Scale = 1
    notify("Interface scale reset", "success")
end, COLORS.PanelHover)

--// PAGE CONTENT: DEBUG
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
        draggingWindow = true
        dragStart = input.Position
        startPosition = Main.Position
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

--// FLUENT UI (legacy custom layout remains as a hidden fallback only)
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
            elseif configKey == "OreESP" or configKey == "EntityESP" or configKey == "LocationESP" or configKey == "PlayerESP" then
                if not (CONFIG.OreESP or CONFIG.EntityESP or CONFIG.LocationESP or CONFIG.PlayerESP) then clearESP() end
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

local fluentOk, fluentError = pcall(function()
    Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
    FluentWindow = Fluent:CreateWindow({
        Title = "Fatal Floors Hub",
        SubTitle = "AURORA  •  V8  •  SECURE LICENSE",
        TabWidth = 150,
        Size = UDim2.fromOffset(760, 565),
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

    FluentTabs.Overview:AddParagraph({
        Title = "FATAL FLOORS  /  AURORA",
        Content = "Premium automation dashboard  ·  Version 8.0\nServer-validated access  ·  Device-bound licenses\nRightControl minimizes the interface.",
    })
    OverviewParagraph = FluentTabs.Overview:AddParagraph({
        Title = "SESSION STATUS",
        Content = "Hub initialized. Configure modules from the tabs above.",
    })
    fluentButton(FluentTabs.Overview, "OPEN FARM MODULES", "Configure ore collection, selling and food automation.", function() FluentWindow:SelectTab(2) end)
    fluentButton(FluentTabs.Overview, "OPEN VISUALS", "Configure ESP overlays.", function() FluentWindow:SelectTab(3) end)
    fluentButton(FluentTabs.Overview, "STOP ALL MODULES / UNLOAD", "Disables loops, restores movement and unloads the UI.", function() if destroyHub then destroyHub() end end)

    FluentTabs.Farm:AddParagraph({ Title = "AUTOMATION", Content = "Serialized worker: farm, sell and eat actions are handled one at a time." })
    fluentToggle(FluentTabs.Farm, "Auto Farm", "AutoFarm", "Collect Iron, Jade, Amethyst, Gold and Amber.")
    fluentToggle(FluentTabs.Farm, "Auto Sell", "AutoSell", "Sell ore tools and verify inventory changes.")
    fluentToggle(FluentTabs.Farm, "Auto Eat", "AutoEat", "Use detected food when the automation worker allows it.")
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
        InterfaceManager:SetFolder("FatalFloorsHub")
        SaveManager:SetFolder("FatalFloorsHub")
        InterfaceManager:BuildInterfaceSection(FluentTabs.Settings)
        SaveManager:BuildConfigSection(FluentTabs.Settings)
    end)
    if not managerOK then log("Optional Fluent managers unavailable: " .. tostring(managerError)) end

    FluentWindow:SelectTab(1)
    GUI.Enabled = false
    Fluent:Notify({ Title = "Fatal Floors Hub", Content = "V8 Fluent loaded · secure license accepted", Duration = 6 })
end)

if not fluentOk then
    Fluent = nil
    GUI.Enabled = true
    warn("[Fatal Floors] Fluent failed to load; showing legacy fallback UI: " .. tostring(fluentError))
else
    log("Fluent interface initialized")
end

--// MOVEMENT / AFK EVENTS
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
    CONFIG.OreESP = false
    CONFIG.EntityESP = false
    CONFIG.LocationESP = false
    CONFIG.PlayerESP = false

    pcall(restoreMovement)

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

    if ENV.FatalFloorsV8 then
        ENV.FatalFloorsV8 = nil
    end
    print("[Fatal Floors v8] Hub stopped and cleaned up")
end

--// KILL BUTTON IN TOPBAR
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
connect(minimizeButton.MouseButton1Click, function()
    Main.Visible = false
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
connect(killButton.MouseButton1Click, destroyHub)

--// HOTKEY
-- Fluent handles RightControl minimization. The legacy fallback keeps its own handler only when Fluent did not load.
if not Fluent then
    connect(UserInputService.InputBegan, function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.RightControl then Main.Visible = not Main.Visible end
    end)
end

--// AUTOMATION WORKER (SERIALIZED)
-- Farm, sell and eat run in one worker to prevent simultaneous teleports/equips.
local function automationWorker()
    local nextEatAt = 0

    while RUNNING do
        local didWork = false

        if CONFIG.AutoFarm then
            local target, reason = nextFarmTarget()
            if target then
                didWork = true
                local ok, detail = collectOre(target)
                if not ok then
                    OBJECT_COOLDOWNS[target] = os.clock() + 4
                    STATS.PickupFails = STATS.PickupFails + 1
                    log("Pickup skipped: " .. tostring(detail))
                else
                    OBJECT_COOLDOWNS[target] = nil
                end
                task.wait(CONFIG.FarmDelay)
            elseif reason then
                safeCall("Farm path", function()
                    error(reason)
                end)
                task.wait(1.5)
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
                end
                task.wait(CONFIG.SellDelay)
            end
        end

        if RUNNING and CONFIG.AutoEat and os.clock() >= nextEatAt then
            didWork = true
            local ok, detail = eatFood()
            if ok then
                log(detail)
            else
                if detail ~= "No food found" then
                    log(detail)
                end
            end
            nextEatAt = os.clock() + CONFIG.EatDelay
        end

        if not didWork then
            task.wait(0.2)
        end
    end
end

--// BACKGROUND REFRESH WORKERS
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
        local active = CONFIG.AutoFarm or CONFIG.AutoSell or CONFIG.AutoEat
            or CONFIG.OreESP or CONFIG.EntityESP or CONFIG.LocationESP or CONFIG.PlayerESP
            or CONFIG.WalkSpeed or CONFIG.HipHeight or CONFIG.JumpPower or CONFIG.AntiAFK

        statusLabel.Text = active and "● SYSTEM ACTIVE" or "● READY"
        statusLabel.TextColor3 = active and COLORS.Green or COLORS.Muted

        if CONFIG.UIScaleValue then
            UI_SETTINGS.Scale = CONFIG.UIScaleValue
            MainScale.Scale = CONFIG.UIScaleValue
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
            "SESSION TIME       %02d:%02d:%02d\nINVENTORY TOOLS    %d\nORES IN INVENTORY  %d\nORES COLLECTED     %d\nITEMS SOLD         %d\nFOODS USED         %d\nPICKUP FAILURES    %d\nSELL FAILURES      %d\nESP OBJECT LIMIT   %d",
            math.floor(elapsed / 3600),
            math.floor((elapsed % 3600) / 60),
            elapsed % 60,
            #tools,
            oreCount,
            STATS.OresCollected,
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

--// INITIALIZE
showPage("Overview")
log("Fatal Floors Hub v1.0 " .. BUILD_LABEL .. " loaded")
notify(BUILD_LABEL .. " access granted · Hub ready", "success")

ENV.FatalFloorsV8 = {
    Destroy = destroyHub,
    Version = "1.0-" .. BUILD_CHANNEL,
    Build = BUILD_CHANNEL,
    ChangeKey = beginKeySwitch,
}

]====]
local __ffchunk, __fferr = loadstring(__ffenv.FatalFloorsAutoExecSource)
if not __ffchunk then error(__fferr) end
__ffchunk()
