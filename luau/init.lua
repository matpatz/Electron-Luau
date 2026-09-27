-- // Services
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local CoreGui = game:GetService("CoreGui")

-- // Fields
local Fields = {
    Url = { Label = "URL", Value = "https://example.com", Type = "string" },
    Width = { Label = "Width", Value = "640", Type = "number" },
    Height = { Label = "Height", Value = "360", Type = "number" },
    Fps = { Label = "FPS", Value = "10", Type = "number" },
    Quality = { Label = "Quality (1-100)", Value = "55", Type = "number" },
    PosX = { Label = "Position X", Value = "0", Type = "number" },
    PosY = { Label = "Position Y", Value = "0", Type = "number" },
    MaxWidth = { Label = "Max width (0 = screen)", Value = "0", Type = "number" },
    MaxHeight = { Label = "Max height (0 = screen)", Value = "0", Type = "number" },
    FocusKey = { Label = "Focus key", Value = "F7", Type = "string" },
    CloseKey = { Label = "Close key", Value = "F8", Type = "string" },
}

-- Stable display order (dicts have no guaranteed order)
local FieldOrder = {
    "Url", "Width", "Height", "Fps", "Quality",
    "PosX", "PosY", "MaxWidth", "MaxHeight", "FocusKey", "CloseKey",
}

local StartFocused = false

-- // Helpers
local function getNumber(key, default)
    local field = Fields[key]
    return (field and tonumber(field.Value)) or default
end

local function getString(key)
    local field = Fields[key]
    return (field and field.Value) or ""
end

local function newInstance(className, properties)
    local inst = Instance.new(className)
    for prop, value in properties do
        inst[prop] = value
    end
    return inst
end

-- // Layout constants
local PANEL_W = 360
local ROW_H = 36
local PADDING = 14
local BUTTON_H = 36
local GAP = 6
local LABEL_W = 150
local INPUT_W = PANEL_W - LABEL_W - PADDING * 2 - 8

local PANEL_H = (#FieldOrder + 1) * (ROW_H + GAP)  -- fields + StartFocused toggle
    + BUTTON_H + GAP * 3

-- // Colors
local COLOR_BG = Color3.fromRGB(40, 40, 51)
local COLOR_ROW = Color3.fromRGB(59, 59, 66)
local COLOR_LABEL = Color3.fromRGB(255, 255, 255)
local COLOR_INPUT_BG = Color3.fromRGB(74, 74, 84)
local COLOR_INPUT_FG = Color3.fromRGB(255, 255, 255)
local COLOR_ACCENT = Color3.fromRGB(74, 74, 84)
local COLOR_WHITE = Color3.fromRGB(255, 255, 255)
local COLOR_TOGGLE_ON = Color3.fromRGB(48, 209, 88)

-- // Interface
local ScreenGui = newInstance("ScreenGui", {
    Name = "Config",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = CoreGui,
})

local Panel = newInstance("Frame", {
    Name = "Panel",
    Size = UDim2.fromOffset(PANEL_W, PANEL_H),
    Position = UDim2.fromOffset(40, 40),
    BackgroundColor3 = COLOR_BG,
    BorderSizePixel = 0,
    Draggable = true,
    Parent = ScreenGui,
})

newInstance("UICorner", { CornerRadius = UDim.new(0, 8), Parent = Panel })

-- // Scrollable content area
local Content = newInstance("Frame", {
    Name = "Content",
    Size = UDim2.new(1, 0, 1, 0),
    Position = UDim2.new(0, 0, 0, 0),
    BackgroundTransparency = 1,
    Parent = Panel,
})

-- // Field rows
local textBoxes = {}  -- key -> TextBox

local function makeRow(index, labelText, valueText, onChanged, customRight)
    local rowY = (index - 1) * (ROW_H + GAP) + GAP

    local Row = newInstance("Frame", {
        Size = UDim2.new(1, -PADDING * 2, 0, ROW_H),
        Position = UDim2.fromOffset(PADDING, rowY),
        BackgroundColor3 = COLOR_ROW,
        BorderSizePixel = 0,
        Parent = Content,
    })
    newInstance("UICorner", { CornerRadius = UDim.new(0, 5), Parent = Row })

    newInstance("TextLabel", {
        Size = UDim2.new(0, LABEL_W, 1, 0),
        Position = UDim2.fromOffset(8, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = COLOR_LABEL,
        TextSize = 13,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = Row,
    })

    if customRight then
        customRight(Row)
    else
        local box = newInstance("TextBox", {
            Size = UDim2.new(0, INPUT_W, 0, ROW_H - 10),
            Position = UDim2.new(0, LABEL_W + 8, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = COLOR_INPUT_BG,
            BorderSizePixel = 0,
            Text = valueText,
            TextColor3 = COLOR_INPUT_FG,
            PlaceholderColor3 = COLOR_LABEL,
            TextSize = 13,
            Font = Enum.Font.Gotham,
            ClearTextOnFocus = false,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = Row,
        })
        newInstance("UICorner", { CornerRadius = UDim.new(0, 4), Parent = box })
        newInstance("UIPadding", {
            PaddingLeft = UDim.new(0, 6),
            PaddingRight = UDim.new(0, 6),
            Parent = box,
        })

        if onChanged then
            box:GetPropertyChangedSignal("Text"):Connect(function()
                onChanged(box.Text)
            end)
        end

        return box
    end
end

for index, key in ipairs(FieldOrder) do
    local field = Fields[key]

    local box = makeRow(index, field.Label, field.Value, function(newText)
        if field.Type == "number" then
            -- strip any character that can't be part of a number
            local cleaned = newText:gsub("[^%d%.%-]", "")
            if cleaned ~= newText then
                -- reassign so the box self-corrects on next frame
                task.defer(function()
                    local tb = textBoxes[key]
                    if tb then tb.Text = cleaned end
                end)
            end
            field.Value = cleaned
        else
            field.Value = newText
        end
    end)

    textBoxes[key] = box
end

-- // StartFocused toggle row
local toggleIndex = #FieldOrder + 1
local toggleRowY = (toggleIndex - 1) * (ROW_H + GAP) + GAP

local ToggleRow = newInstance("Frame", {
    Size = UDim2.new(1, -PADDING * 2, 0, ROW_H),
    Position = UDim2.fromOffset(PADDING, toggleRowY),
    BackgroundColor3 = COLOR_ROW,
    BorderSizePixel = 0,
    Parent = Content,
})
newInstance("UICorner", { CornerRadius = UDim.new(0, 5), Parent = ToggleRow })

newInstance("TextLabel", {
    Size = UDim2.new(0, LABEL_W, 1, 0),
    Position = UDim2.fromOffset(8, 0),
    BackgroundTransparency = 1,
    Text = "Start focused",
    TextColor3 = COLOR_LABEL,
    TextSize = 13,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = ToggleRow,
})

-- Pill toggle
local ToggleBtn = newInstance("TextButton", {
    Size = UDim2.new(0, 44, 0, 24),
    Position = UDim2.new(0, LABEL_W + 8, 0.5, 0),
    AnchorPoint = Vector2.new(0, 0.5),
    BackgroundColor3 = COLOR_INPUT_BG,
    BorderSizePixel = 0,
    Text = "",
    Parent = ToggleRow,
})
newInstance("UICorner", { CornerRadius = UDim.new(0, 12), Parent = ToggleBtn })

local ToggleKnob = newInstance("Frame", {
    Size = UDim2.new(0, 18, 0, 18),
    Position = UDim2.fromOffset(3, 3),
    BackgroundColor3 = COLOR_WHITE,
    BorderSizePixel = 0,
    Parent = ToggleBtn,
})
newInstance("UICorner", { CornerRadius = UDim.new(0, 9), Parent = ToggleKnob })

local function refreshToggle()
    ToggleBtn.BackgroundColor3 = StartFocused and COLOR_TOGGLE_ON or COLOR_INPUT_BG
    ToggleKnob.Position = StartFocused
        and UDim2.fromOffset(44 - 18 - 3, 3)
        or UDim2.fromOffset(3, 3)
end

ToggleBtn.Activated:Connect(function()
    StartFocused = not StartFocused
    refreshToggle()
end)

refreshToggle()

-- // Submit button
local submitY = toggleRowY + ROW_H + GAP * 2

local SubmitBtn = newInstance("TextButton", {
    Size = UDim2.new(1, -PADDING * 2, 0, BUTTON_H),
    Position = UDim2.fromOffset(PADDING, submitY),
    BackgroundColor3 = COLOR_ACCENT,
    BorderSizePixel = 0,
    Text = "Submit",
    TextColor3 = COLOR_WHITE,
    TextSize = 14,
    Font = Enum.Font.GothamBold,
    Parent = Content,
})
newInstance("UICorner", { CornerRadius = UDim.new(0, 6), Parent = SubmitBtn })

-- // Submit handler
local function submit()
    local config = {
        Url = getString("Url"),
        Port = 8842,
        Width = getNumber("Width", 640),
        Height = getNumber("Height", 360),
        Fps = getNumber("Fps", 10),
        Quality = getNumber("Quality", 55),
        OverlayPos = { X = getNumber("PosX", 0), Y = getNumber("PosY", 0) },
        MaxWidth = getNumber("MaxWidth", 0),
        MaxHeight = getNumber("MaxHeight", 0),
        FocusKey = getString("FocusKey"),
        CloseKey = getString("CloseKey"),
        StartFocused = StartFocused,
    }

    writefile("config.json", HttpService:JSONEncode(config))
    ScreenGui:Destroy()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/matpatz/Electron-Luau/refs/heads/main/luau/overlay.lua"))()
end

SubmitBtn.Activated:Connect(submit)