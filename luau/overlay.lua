--[[
  Usage:
    1. Start the Electron app (npm start).
    2. Generate the Config with the control panel and paste it into init.lua.
    3. Run init.lua or manually generate the Config.
    4. Click the overlay to interact. F7 toggles keyboard capture, F8 hides/shows.
    5. Drag the overlay with the right mouse button.
]]

-- // Services
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

--// Config
local Config = HttpService:JSONDecode(readfile("config.json"))

local WS_URL = "ws://127.0.0.1:" .. (Config.Port or 8842)

local OverlayPos = Config.OverlayPos or {}
local OVERLAY_POS = Vector2.new(OverlayPos.X or 0, OverlayPos.Y or 0)

local FOCUS_KEY = (Config.FocusKey and Enum.KeyCode[Config.FocusKey]) or Enum.KeyCode.F7
local CLOSE_KEY = (Config.CloseKey and Enum.KeyCode[Config.CloseKey]) or Enum.KeyCode.F8
local START_FOCUSED = Config.StartFocused or false

local function log(...)
    print("[overlay]", ...)
end

assert(Drawing, "Drawing library is required")
assert(crypt and crypt.base64decode, "crypt.base64decode is required")

-- // WebSocket
local Conn = nil

local function websocket_send(Obj)
    if not Conn then
        return false
    end

    local ok, err = pcall(function()
        Conn:Send(HttpService:JSONEncode(Obj))
    end)

    if not ok then
        log("send failed:", err)
    end

    return ok
end

local function websocket_connect()
    return WebSocket.connect(WS_URL)
end

local function websocket_bind(Socket, OnMessage, OnClose)
    assert(Socket.OnMessage and Socket.OnMessage.Connect, "WebSocket object has no OnMessage signal")
    assert(Socket.OnClose and Socket.OnClose.Connect, "WebSocket object has no OnClose signal")
    Socket.OnMessage:Connect(OnMessage)
    Socket.OnClose:Connect(OnClose)
end

-- // State
local PAGE_W, PAGE_H = Config.Width or 640, Config.Height or 360

-- On-screen size of the overlay — stretched to fill the monitor (or the configured max).
local DISPLAY_W, DISPLAY_H = 640, 360

local function updateDisplay()
    local maxW, maxH = 640, 360
    local camera = game:GetService("Workspace").CurrentCamera

    if camera then
        local vs = camera.ViewportSize
        if vs and vs.X > 0 and vs.Y > 0 then
            maxW, maxH = vs.X, vs.Y
        end
    end

    if Config.MaxWidth and Config.MaxWidth > 0 then maxW = Config.MaxWidth end
    if Config.MaxHeight and Config.MaxHeight > 0 then maxH = Config.MaxHeight end

    DISPLAY_W, DISPLAY_H = maxW, maxH
end

updateDisplay()

local OverlayImage = nil
local Focused = START_FOCUSED
local OverlayVisible = true

local Dragging = false
local DragStartMouse = nil
local DragStartOverlayPos = nil

-- // Message Handling
local function handleMessage(Raw)
    local Message = HttpService:JSONDecode(Raw)

    if Message.type == "configured" then
        PAGE_W, PAGE_H = Message.w, Message.h
        updateDisplay()
        OverlayImage.Size = Vector2.new(DISPLAY_W, DISPLAY_H)
        log("configured", PAGE_W, "x", PAGE_H)

    elseif Message.type == "frame" then
        if not OverlayVisible then
            return
        end

        PAGE_W, PAGE_H = Message.w, Message.h
        updateDisplay()
        OverlayImage.Size = Vector2.new(DISPLAY_W, DISPLAY_H)
        OverlayImage.Data = crypt.base64decode(Message.b64)
    end
end

-- // Input Mapping
local BASE_KEYS = {
    Return = "Return", Space = "Space", Backspace = "Backspace", Delete = "Delete",
    Tab = "Tab", Escape = "Escape", Up = "Up", Down = "Down", Left = "Left", Right = "Right",
    Home = "Home", End = "End", PageUp = "PageUp", PageDown = "PageDown",
    CapsLock = "CapsLock", Insert = "Insert",
    Minus = "-", Equals = "=", LeftBracket = "[", RightBracket = "]",
    BackSlash = "\\", Semicolon = ";", Quote = "'", Comma = ",", Period = ".",
    Slash = "/", Backquote = "`",
    KeypadZero = "0", KeypadOne = "1", KeypadTwo = "2", KeypadThree = "3", KeypadFour = "4",
    KeypadFive = "5", KeypadSix = "6", KeypadSeven = "7", KeypadEight = "8", KeypadNine = "9",
    KeypadPeriod = ".", KeypadDivide = "/", KeypadMultiply = "*", KeypadMinus = "-",
    KeypadPlus = "+", KeypadEnter = "Return",
    Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
    Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
}

for i = 1, 12 do
    BASE_KEYS["F" .. i] = "F" .. i
end

local function baseKey(Name)
    if BASE_KEYS[Name] then
        return BASE_KEYS[Name]
    end

    if #Name == 1 then
        return Name -- single letter A-Z
    end

    return nil
end

local function mouseButton(InputType)
    if InputType == Enum.UserInputType.MouseButton2 then
        return "right"
    end

    if InputType == Enum.UserInputType.MouseButton3 then
        return "middle"
    end

    return "left"
end

local function toPage(x, y)
    x = (x - OVERLAY_POS.X) / DISPLAY_W * PAGE_W
    y = (y - OVERLAY_POS.Y) / DISPLAY_H * PAGE_H
    return x, y
end

local function inside(x, y)
    return x >= OVERLAY_POS.X
        and y >= OVERLAY_POS.Y
        and x <= OVERLAY_POS.X + DISPLAY_W
        and y <= OVERLAY_POS.Y + DISPLAY_H
end

local function mods()
    local Shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
    local Ctrl  = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
    local Alt   = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
    return Shift, Ctrl, Alt
end

-- // Mouse clicks + keyboard
UserInputService.InputBegan:Connect(function(Input, GameProcessed)
    local InputType = Input.UserInputType

    if InputType == Enum.UserInputType.MouseButton2 then
        -- right button: drag the overlay
        local MouseLocation = UserInputService:GetMouseLocation()

        if OverlayVisible and inside(MouseLocation.X, MouseLocation.Y) then
            Dragging = true
            DragStartMouse = MouseLocation
            DragStartOverlayPos = OVERLAY_POS
        end

    elseif InputType == Enum.UserInputType.MouseButton1
        or InputType == Enum.UserInputType.MouseButton3 then

        local MouseLocation = UserInputService:GetMouseLocation()

        if OverlayVisible and inside(MouseLocation.X, MouseLocation.Y) then
            local x, y = toPage(MouseLocation.X, MouseLocation.Y)
            websocket_send({ type = "input", kind = "mousedown", x = x, y = y, button = mouseButton(InputType) })
            Focused = true
        end

    elseif InputType == Enum.UserInputType.Keyboard then

        if Input.KeyCode == CLOSE_KEY then
            OverlayVisible = not OverlayVisible

            if OverlayImage then
                OverlayImage.Visible = OverlayVisible
            end

            log("overlay visible:", OverlayVisible)

        elseif Input.KeyCode == FOCUS_KEY then
            Focused = not Focused
            log("keyboard capture:", Focused)

        elseif Focused and OverlayVisible then
            local Key = baseKey(Input.KeyCode.Name)

            if Key then
                local Shift, Ctrl, Alt = mods()
                websocket_send({ type = "input", kind = "keydown", key = Key, shift = Shift, ctrl = Ctrl, alt = Alt })
            end
        end

    end
end)

UserInputService.InputEnded:Connect(function(Input, GameProcessed)
    local InputType = Input.UserInputType

    if InputType == Enum.UserInputType.MouseButton2 then
        Dragging = false

    elseif InputType == Enum.UserInputType.MouseButton1
        or InputType == Enum.UserInputType.MouseButton3 then

        local MouseLocation = UserInputService:GetMouseLocation()

        if OverlayVisible and inside(MouseLocation.X, MouseLocation.Y) then
            local x, y = toPage(MouseLocation.X, MouseLocation.Y)
            websocket_send({ type = "input", kind = "mouseup", x = x, y = y, button = mouseButton(InputType) })
        end

    elseif InputType == Enum.UserInputType.Keyboard and Focused and OverlayVisible then
        local Key = baseKey(Input.KeyCode.Name)

        if Key then
            local Shift, Ctrl, Alt = mods()
            websocket_send({ type = "input", kind = "keyup", key = Key, shift = Shift, ctrl = Ctrl, alt = Alt })
        end
    end
end)

-- // Mouse wheel
UserInputService.InputChanged:Connect(function(Input, GameProcessed)
    local InputType = Input.UserInputType

    if InputType == Enum.UserInputType.MouseWheel then
        local MouseLocation = UserInputService:GetMouseLocation()

        if OverlayVisible and inside(MouseLocation.X, MouseLocation.Y) then
            local x, y = toPage(MouseLocation.X, MouseLocation.Y)

            -- Wheel scroll lives in Input.Position.Z (positive = wheel forward/up).
            -- Chromium treats positive deltaY as "scroll down", so negate it.
            websocket_send({
                type = "input",
                kind = "mousewheel",
                x = x,
                y = y,
                deltaY = -Input.Position.Z * 100,
                deltaX = 0,
            })
        end
    end
end)

-- // Mouse move (throttled poll, only when over the overlay)
local LastX, LastY = -1, -1
local LastSent = 0

RunService.RenderStepped:Connect(function()
    local Now = os.clock()

    if Dragging then
        local MouseLocation = UserInputService:GetMouseLocation()

        OVERLAY_POS = Vector2.new(
            DragStartOverlayPos.X + (MouseLocation.X - DragStartMouse.X),
            DragStartOverlayPos.Y + (MouseLocation.Y - DragStartMouse.Y)
        )

        if OverlayImage then
            OverlayImage.Position = OVERLAY_POS
        end

        return
    end

    if Now - LastSent < 0.05 then
        return
    end

    local MouseLocation = UserInputService:GetMouseLocation()

    if OverlayVisible and inside(MouseLocation.X, MouseLocation.Y) then

        if math.abs(MouseLocation.X - LastX) > 1 or math.abs(MouseLocation.Y - LastY) > 1 then
            LastX, LastY = MouseLocation.X, MouseLocation.Y
            LastSent = Now

            local x, y = toPage(MouseLocation.X, MouseLocation.Y)
            websocket_send({ type = "input", kind = "mousemove", x = x, y = y })
        end

    end
end)

-- // Init
local function init()
    OverlayImage = Drawing.new("Image")
    OverlayImage.Visible = true
    OverlayImage.Position = OVERLAY_POS
    OverlayImage.Size = Vector2.new(DISPLAY_W, DISPLAY_H)

    local function connect()
        Conn = websocket_connect()

        if not Conn then
            log("could not connect to", WS_URL, "— retrying in 3s…")
            task.wait(3)
            connect()
            return
        end

        log("connected to", WS_URL)

        websocket_bind(Conn, function(Raw)
            local ok, err = pcall(handleMessage, Raw)

            if not ok then
                log("frame error:", err)
            end
        end, function()
            log("disconnected — reconnecting in 2s…")
            Conn = nil
            task.wait(2)
            connect()
        end)

        -- send the whole config to the Electron app
        websocket_send({
            type = "configure",
            config = Config,
        })
    end

    connect()
end

init()
