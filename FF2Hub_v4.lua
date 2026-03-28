-- ╔═══════════════════════════════════════════════════════════════╗
--   FF2 Hub  |  Football Fusion 2  |  v4.0
--   Real logic sourced from paid script  ·  Improved UI
-- ╚═══════════════════════════════════════════════════════════════╝

-- ──────────────────────────────────────────────
--  GUARD AGAINST DOUBLE EXECUTION
-- ──────────────────────────────────────────────
if getgenv and getgenv().FF2HubLoaded then
    warn("[FF2Hub] Already loaded, reloading...")
    if getgenv().FF2HubCleanup then getgenv().FF2HubCleanup() end
end
if getgenv then getgenv().FF2HubLoaded = true end

-- ──────────────────────────────────────────────
--  SERVICES
-- ──────────────────────────────────────────────
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local CoreGui           = game:GetService("CoreGui")
local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")
local StatsService      = game:GetService("Stats")
local ScriptContext     = game:GetService("ScriptContext")
local StarterGui        = game:GetService("StarterGui")

local LP    = Players.LocalPlayer
local Mouse = LP:GetMouse()
local Camera = workspace.CurrentCamera

-- ──────────────────────────────────────────────
--  GAME STATE
-- ──────────────────────────────────────────────
local IS_PRACTICE = game.PlaceId == 8206123457
local values = ReplicatedStorage:FindFirstChild("Values")

if not values or IS_PRACTICE then
    if ReplicatedStorage:FindFirstChild("Values") then
        ReplicatedStorage:FindFirstChild("Values"):Destroy()
    end
    values = Instance.new("Folder")
    local status = Instance.new("StringValue")
    status.Name = "Status"; status.Value = "InPlay"; status.Parent = values
    values.Parent = ReplicatedStorage; values.Name = "Values"
end

-- ──────────────────────────────────────────────
--  CONNECTIONS TRACKER (for cleanup)
-- ──────────────────────────────────────────────
local Connections = {}
local function track(c) Connections[#Connections+1] = c return c end

if getgenv then
    getgenv().FF2HubCleanup = function()
        for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
        Connections = {}
        if CoreGui:FindFirstChild("FF2Hub") then CoreGui.FF2Hub:Destroy() end
        getgenv().FF2HubLoaded = false
    end
end

-- ──────────────────────────────────────────────
--  GLOBAL STATE
-- ──────────────────────────────────────────────
local ping            = 0
local fps             = 0
local velocity        = {}       -- ball velocity tracking
local isCatching      = false
local moveToUsing     = {}
local fakeBalls       = {}
local pullVectoredBalls = {}

-- ──────────────────────────────────────────────
--  UTILITY FUNCTIONS  (from paid script)
-- ──────────────────────────────────────────────
local function getPing()
    return pcall(function() return StatsService.PerformanceStats.Ping:GetValue() end) and StatsService.PerformanceStats.Ping:GetValue() or 0
end

local function getServerPing()
    local ok, val = pcall(function() return StatsService.Network.ServerStatsItem['Data Ping']:GetValue() end)
    return ok and val or 0
end

local function findClosestBall()
    local lowestDist = math.huge
    local nearest = nil
    local char = LP.Character
    for _, ball in pairs(workspace:GetChildren()) do
        if ball.Name ~= "Football" then continue end
        if not ball:IsA("BasePart") then continue end
        if not char or not char:FindFirstChild("HumanoidRootPart") then continue end
        local d = (ball.Position - char.HumanoidRootPart.Position).Magnitude
        if d < lowestDist then nearest = ball lowestDist = d end
    end
    return nearest
end

local function findPossessor()
    for _, p in pairs(Players:GetPlayers()) do
        local char = p.Character
        if char and char:FindFirstChildWhichIsA("Tool") then return char end
    end
end

local function getNearestPartFromParts(part, parts)
    local lowestDist = math.huge
    local nearest = nil
    for _, p in pairs(parts) do
        local d = (part.Position - p.Position).Magnitude
        if d < lowestDist then nearest = p lowestDist = d end
    end
    return nearest
end

local function beamProjectile(g, v0, x0, t1)
    local c = 0.5*0.5*0.5
    local p3 = 0.5*g*t1*t1 + v0*t1 + x0
    local p2 = p3 - (g*t1*t1 + v0*t1)/3
    local p1 = (c*g*t1*t1 + 0.5*v0*t1 + x0 - c*(x0+p3))/(3*c) - p2
    local curve0 = (p1-x0).magnitude
    local curve1 = (p2-p3).magnitude
    local b = (x0-p3).unit
    local r1 = (p1-x0).unit; local u1 = r1:Cross(b).unit
    local r2 = (p2-p3).unit; local u2 = r2:Cross(b).unit
    b = u1:Cross(r1).unit
    local cf1 = CFrame.new(x0.x,x0.y,x0.z, r1.x,u1.x,b.x, r1.y,u1.y,b.y, r1.z,u1.z,b.z)
    local cf2 = CFrame.new(p3.x,p3.y,p3.z, r2.x,u2.x,b.x, r2.y,u2.y,b.y, r2.z,u2.z,b.z)
    return curve0, -curve1, cf1, cf2
end

-- ──────────────────────────────────────────────
--  PING / FPS TRACKING
-- ──────────────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(0.1)
        ping = (getPing() + getServerPing()) / 1000
    end
end)

task.spawn(function()
    track(RunService.RenderStepped:Connect(function()
        fps = fps + 1
        task.delay(1, function() fps = fps - 1 end)
    end))
end)

-- ──────────────────────────────────────────────
--  UI THEME
-- ──────────────────────────────────────────────
local T = {
    BG         = Color3.fromRGB(12, 12, 18),
    Panel      = Color3.fromRGB(20, 20, 30),
    PanelDark  = Color3.fromRGB(15, 15, 22),
    Border     = Color3.fromRGB(45, 45, 68),
    Accent     = Color3.fromRGB(88, 155, 255),
    AccentDim  = Color3.fromRGB(50, 95, 175),
    Green      = Color3.fromRGB(55, 195, 95),
    Red        = Color3.fromRGB(215, 65, 65),
    Yellow     = Color3.fromRGB(235, 185, 45),
    Text       = Color3.fromRGB(228, 228, 238),
    TextDim    = Color3.fromRGB(125, 125, 152),
    TextOff    = Color3.fromRGB(72, 72, 98),
    White      = Color3.new(1, 1, 1),
}

-- ──────────────────────────────────────────────
--  UI HELPERS
-- ──────────────────────────────────────────────
local function tw(obj, props, t, style, dir)
    TweenService:Create(obj,
        TweenInfo.new(t or 0.16, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props):Play()
end
local function corner(p, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r or 7) c.Parent = p return c end
local function stroke(p, col, th) local s = Instance.new("UIStroke") s.Color = col or T.Border s.Thickness = th or 1 s.Parent = p end
local function pad(p, top, bot, left, right)
    local u = Instance.new("UIPadding")
    u.PaddingTop = UDim.new(0, top or 6); u.PaddingBottom = UDim.new(0, bot or 6)
    u.PaddingLeft = UDim.new(0, left or 8); u.PaddingRight = UDim.new(0, right or 8)
    u.Parent = p
end
local function listlay(p, dir, h, v, spacing)
    local l = Instance.new("UIListLayout")
    l.FillDirection = dir or Enum.FillDirection.Vertical
    l.HorizontalAlignment = h or Enum.HorizontalAlignment.Left
    l.VerticalAlignment = v or Enum.VerticalAlignment.Top
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, spacing or 4)
    l.Parent = p; return l
end
local function mkFrame(parent, name, size, pos, bg, trans)
    local f = Instance.new("Frame")
    f.Name = name or "Frame"; f.Size = size or UDim2.new(1,0,1,0)
    f.Position = pos or UDim2.new(0,0,0,0); f.BackgroundColor3 = bg or T.Panel
    f.BackgroundTransparency = trans or 0; f.BorderSizePixel = 0; f.Parent = parent
    return f
end
local function mkLabel(parent, text, size, pos, font, textsize, color, xalign)
    local l = Instance.new("TextLabel")
    l.Size = size or UDim2.new(1,0,0,20); l.Position = pos or UDim2.new(0,0,0,0)
    l.BackgroundTransparency = 1; l.Text = text or ""
    l.Font = font or Enum.Font.Gotham; l.TextSize = textsize or 13
    l.TextColor3 = color or T.Text; l.TextXAlignment = xalign or Enum.TextXAlignment.Left
    l.TextWrapped = true; l.BorderSizePixel = 0; l.Parent = parent
    return l
end

-- ──────────────────────────────────────────────
--  CLEANUP OLD GUI
-- ──────────────────────────────────────────────
if CoreGui:FindFirstChild("FF2Hub") then CoreGui.FF2Hub:Destroy() end

-- ──────────────────────────────────────────────
--  ROOT GUI
-- ──────────────────────────────────────────────
local Screen = Instance.new("ScreenGui")
Screen.Name = "FF2Hub"; Screen.ResetOnSpawn = false
Screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Screen.DisplayOrder = 999; Screen.Parent = CoreGui

-- ──────────────────────────────────────────────
--  MAIN WINDOW
-- ──────────────────────────────────────────────
local Win = mkFrame(Screen, "Window", UDim2.new(0,800,0,470), UDim2.new(0.5,-400,0.5,-235), T.BG)
corner(Win, 12)
stroke(Win, T.Border, 1.5)
Win.ClipsDescendants = true

-- Shadow
local Shad = Instance.new("ImageLabel")
Shad.AnchorPoint = Vector2.new(0.5,0.5); Shad.Size = UDim2.new(1,50,1,50)
Shad.Position = UDim2.new(0.5,0,0.5,10); Shad.BackgroundTransparency = 1
Shad.Image = "rbxassetid://6014261993"; Shad.ImageColor3 = Color3.new(0,0,0)
Shad.ImageTransparency = 0.5; Shad.ScaleType = Enum.ScaleType.Slice
Shad.SliceCenter = Rect.new(49,49,450,450); Shad.ZIndex = 0; Shad.Parent = Win

-- ──────────────────────────────────────────────
--  TITLE BAR
-- ──────────────────────────────────────────────
local TBar = mkFrame(Win, "TitleBar", UDim2.new(1,0,0,40), UDim2.new(0,0,0,0), T.Panel)
corner(TBar, 12)
mkFrame(TBar, "BotCover", UDim2.new(1,0,0,12), UDim2.new(0,0,1,-12), T.Panel)
local Stripe = mkFrame(TBar, "Stripe", UDim2.new(0,3,0,20), UDim2.new(0,13,0.5,-10), T.Accent)
corner(Stripe, 3)
mkLabel(TBar, "⚽  FF2 Hub  v4.0", UDim2.new(1,-110,1,0), UDim2.new(0,24,0,0), Enum.Font.GothamBold, 14, T.Text)

local function tBarBtn(xoff, col, icon)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0,24,0,24); b.Position = UDim2.new(1,xoff,0.5,-12)
    b.BackgroundColor3 = col; b.Text = icon; b.TextColor3 = T.White
    b.Font = Enum.Font.GothamBold; b.TextSize = 15; b.BorderSizePixel = 0; b.Parent = TBar
    corner(b, 5); return b
end
local CloseBtn = tBarBtn(-10, T.Red, "×")
local MinBtn   = tBarBtn(-40, T.Yellow, "−")

-- Drag
local dragging, dragOff = false, Vector2.new()
TBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragOff = Vector2.new(Mouse.X - Win.AbsolutePosition.X, Mouse.Y - Win.AbsolutePosition.Y)
    end
end)
TBar.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
track(RunService.RenderStepped:Connect(function()
    if dragging then Win.Position = UDim2.new(0, Mouse.X-dragOff.X, 0, Mouse.Y-dragOff.Y) end
end))

local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    tw(Win, {Size = minimized and UDim2.new(0,800,0,40) or UDim2.new(0,800,0,470)}, 0.2)
end)
CloseBtn.MouseButton1Click:Connect(function()
    tw(Win, {Size = UDim2.new(0,800,0,0)}, 0.18)
    task.wait(0.2); Screen:Destroy()
    if getgenv then getgenv().FF2HubLoaded = false end
end)

-- ──────────────────────────────────────────────
--  NOTIFICATIONS
-- ──────────────────────────────────────────────
local NotifHolder = mkFrame(Screen, "Notifs", UDim2.new(0,300,1,-20), UDim2.new(1,-308,0,8), Color3.new(0,0,0), 1)
listlay(NotifHolder, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top, 5)

local function Notify(title, msg, ntype, duration)
    duration = duration or 3.5
    local col = ntype=="success" and T.Green or ntype=="warn" and T.Yellow or ntype=="error" and T.Red or T.Accent
    local n = mkFrame(NotifHolder, "N", UDim2.new(0,285,0,56), nil, T.Panel)
    corner(n, 8); stroke(n, col, 1.5); n.ClipsDescendants = true; n.ZIndex = 20
    mkFrame(n, "Bar", UDim2.new(0,3,1,0), UDim2.new(0,0,0,0), col)
    mkLabel(n, title, UDim2.new(1,-14,0,16), UDim2.new(0,10,0,5), Enum.Font.GothamBold, 12, col)
    mkLabel(n, msg,   UDim2.new(1,-14,0,26), UDim2.new(0,10,0,24), Enum.Font.Gotham, 11, T.TextDim)
    task.delay(duration, function()
        tw(n, {BackgroundTransparency=1}, 0.25)
        task.wait(0.26); pcall(function() n:Destroy() end)
    end)
end

-- ──────────────────────────────────────────────
--  COLUMN LAYOUT
-- ──────────────────────────────────────────────
local ColArea = mkFrame(Win, "ColArea", UDim2.new(1,-8,1,-52), UDim2.new(0,4,0,42), Color3.new(0,0,0), 1)
listlay(ColArea, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top, 4)

local function NewCol(name, accentColor)
    accentColor = accentColor or T.Accent
    local col = mkFrame(ColArea, name, UDim2.new(0,124,1,0), nil, T.Panel)
    corner(col, 9); stroke(col, T.Border, 1); col.ClipsDescendants = true
    local hdr = mkFrame(col, "Hdr", UDim2.new(1,0,0,24), UDim2.new(0,0,0,0), accentColor)
    corner(hdr, 9); mkFrame(hdr, "Cov", UDim2.new(1,0,0,9), UDim2.new(0,0,1,-9), accentColor)
    mkLabel(hdr, name, UDim2.new(1,0,1,0), nil, Enum.Font.GothamBold, 11, T.White, Enum.TextXAlignment.Center)
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1,0,1,-26); scroll.Position = UDim2.new(0,0,0,26)
    scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3; scroll.ScrollBarImageColor3 = accentColor
    scroll.CanvasSize = UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = col
    listlay(scroll, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top, 0)
    pad(scroll, 3, 3, 3, 3)
    return scroll
end

-- ──────────────────────────────────────────────
--  ELEMENT BUILDERS
-- ──────────────────────────────────────────────

-- Toggle
local ToggleRefs = {}
local function AddToggle(parent, label, default, callback)
    default = default or false; callback = callback or function() end
    local state = default
    local row = mkFrame(parent, label, UDim2.new(1,-2,0,26), nil, Color3.new(0,0,0))
    row.BackgroundTransparency = 1
    pad(row, 0, 0, 4, 4)
    mkLabel(row, label, UDim2.new(1,-32,1,0), UDim2.new(0,0,0,0), Enum.Font.Gotham, 11, T.Text)
    local track = mkFrame(row, "T", UDim2.new(0,26,0,14), UDim2.new(1,-28,0.5,-7), state and T.Green or T.PanelDark)
    corner(track, 7); stroke(track, T.Border, 1)
    local knob = mkFrame(track, "K", UDim2.new(0,10,0,10), UDim2.new(0, state and 14 or 2, 0.5,-5), T.White)
    corner(knob, 5)
    local function upd()
        tw(track, {BackgroundColor3 = state and T.Green or T.PanelDark}, 0.12)
        tw(knob,  {Position = UDim2.new(0, state and 14 or 2, 0.5,-5)}, 0.12)
    end
    upd()
    local btn = Instance.new("TextButton"); btn.Size = UDim2.new(1,0,1,0)
    btn.BackgroundTransparency = 1; btn.Text = ""; btn.Parent = row
    btn.MouseButton1Click:Connect(function() state = not state upd() callback(state) end)
    local ref = {Get = function() return state end, Set = function(v) state=v upd() callback(v) end}
    ToggleRefs[label] = ref; return ref
end

-- Dropdown
local function AddDropdown(parent, label, options, default, callback)
    callback = callback or function() end
    local selected = default or options[1] or "None"
    local open = false
    local container = mkFrame(parent, label, UDim2.new(1,-2,0,24), nil, Color3.new(0,0,0))
    container.BackgroundTransparency = 1; container.AutomaticSize = Enum.AutomaticSize.Y
    mkLabel(container, label, UDim2.new(1,0,0,11), UDim2.new(0,4,0,0), Enum.Font.Gotham, 10, T.TextDim)
    local bar = mkFrame(container, "Bar", UDim2.new(1,-2,0,19), UDim2.new(0,1,0,12), T.PanelDark)
    corner(bar, 5); stroke(bar, T.Border, 1)
    local selLbl = mkLabel(bar, selected, UDim2.new(1,-20,1,0), UDim2.new(0,5,0,0), Enum.Font.Gotham, 10, T.Text)
    mkLabel(bar, "▾", UDim2.new(0,16,1,0), UDim2.new(1,-17,0,0), Enum.Font.GothamBold, 10, T.Accent, Enum.TextXAlignment.Center)
    local box = mkFrame(container, "Box", UDim2.new(1,-2,0,0), UDim2.new(0,1,0,33), T.PanelDark)
    corner(box, 5); stroke(box, T.Accent, 1); box.Visible = false
    box.ZIndex = 20; box.AutomaticSize = Enum.AutomaticSize.Y; box.ClipsDescendants = true
    listlay(box)
    for _, opt in ipairs(options) do
        local ob = Instance.new("TextButton"); ob.Size = UDim2.new(1,0,0,17)
        ob.BackgroundTransparency = 1; ob.Text = opt; ob.Font = Enum.Font.Gotham
        ob.TextSize = 10; ob.TextColor3 = T.TextDim
        ob.TextXAlignment = Enum.TextXAlignment.Left; ob.BorderSizePixel = 0; ob.Parent = box
        pad(ob, 0, 0, 6, 2)
        ob.MouseButton1Click:Connect(function()
            selected = opt; selLbl.Text = opt; open = false; box.Visible = false; callback(opt)
        end)
        ob.MouseEnter:Connect(function() ob.TextColor3 = T.Text end)
        ob.MouseLeave:Connect(function() ob.TextColor3 = T.TextDim end)
    end
    local barBtn = Instance.new("TextButton"); barBtn.Size = UDim2.new(1,0,1,0)
    barBtn.BackgroundTransparency = 1; barBtn.Text = ""; barBtn.ZIndex = 5; barBtn.Parent = bar
    barBtn.MouseButton1Click:Connect(function() open = not open; box.Visible = open end)
    return {Get = function() return selected end, Set = function(v) selected=v selLbl.Text=v end}
end

-- Slider
local function AddSlider(parent, label, min, max, default, fmt, callback)
    min = min or 0; max = max or 100; default = default or min
    fmt = fmt or "%d"; callback = callback or function() end
    local value = default
    local cont = mkFrame(parent, label, UDim2.new(1,-2,0,37), nil, Color3.new(0,0,0))
    cont.BackgroundTransparency = 1
    local topRow = mkFrame(cont, "R", UDim2.new(1,0,0,13), UDim2.new(0,0,0,0), Color3.new(0,0,0))
    topRow.BackgroundTransparency = 1
    mkLabel(topRow, label, UDim2.new(0.65,0,1,0), UDim2.new(0,4,0,0), Enum.Font.Gotham, 10, T.TextDim)
    local valLbl = mkLabel(topRow, string.format(fmt, value), UDim2.new(0.35,-4,1,0), UDim2.new(0.65,0,0,0), Enum.Font.GothamBold, 10, T.Accent, Enum.TextXAlignment.Right)
    local track = mkFrame(cont, "Tr", UDim2.new(1,-8,0,6), UDim2.new(0,4,0,16), T.PanelDark)
    corner(track, 3); stroke(track, T.Border, 1)
    local fill = mkFrame(track, "F", UDim2.new((value-min)/(max-min),0,1,0), nil, T.Accent)
    corner(fill, 3)
    local hit = Instance.new("TextButton"); hit.Size = UDim2.new(1,0,3,0)
    hit.Position = UDim2.new(0,0,-1,0); hit.BackgroundTransparency = 1; hit.Text = ""; hit.Parent = track
    local sliding = false
    hit.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then sliding = true end end)
    hit.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then sliding = false end end)
    track(RunService.RenderStepped:Connect(function()
        if not sliding then return end
        local rel = math.clamp((Mouse.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        value = math.floor(min + (max-min)*rel)
        fill.Size = UDim2.new(rel,0,1,0)
        valLbl.Text = string.format(fmt, value)
        callback(value)
    end))
    return {Get = function() return value end, Set = function(v) value=v fill.Size=UDim2.new((v-min)/(max-min),0,1,0) valLbl.Text=string.format(fmt,v) end}
end

-- Keybind
local function AddKeybind(parent, label, default, callback)
    default = default or Enum.KeyCode.Unknown; callback = callback or function() end
    local currentKey = default; local binding = false
    local row = mkFrame(parent, label, UDim2.new(1,-2,0,26), nil, Color3.new(0,0,0))
    row.BackgroundTransparency = 1; pad(row, 0, 0, 4, 4)
    mkLabel(row, label, UDim2.new(1,-48,1,0), nil, Enum.Font.Gotham, 11, T.Text)
    local kbtn = Instance.new("TextButton"); kbtn.Size = UDim2.new(0,42,0,16)
    kbtn.Position = UDim2.new(1,-44,0.5,-8); kbtn.BackgroundColor3 = T.PanelDark
    kbtn.Text = default.Name; kbtn.TextColor3 = T.Accent; kbtn.Font = Enum.Font.GothamBold
    kbtn.TextSize = 9; kbtn.BorderSizePixel = 0; kbtn.Parent = row
    corner(kbtn, 4); stroke(kbtn, T.Border, 1)
    kbtn.MouseButton1Click:Connect(function()
        binding = true; kbtn.Text = "..."
        kbtn.TextColor3 = T.Yellow
    end)
    track(UserInputService.InputBegan:Connect(function(inp, gp)
        if binding and not gp then
            currentKey = inp.KeyCode; binding = false
            kbtn.Text = inp.KeyCode.Name; kbtn.TextColor3 = T.Accent
            callback(inp.KeyCode)
        end
    end))
    return {Get = function() return currentKey end}
end

-- Button
local function AddButton(parent, label, callback)
    callback = callback or function() end
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,-8,0,21); btn.BackgroundColor3 = T.AccentDim
    btn.Text = label; btn.Font = Enum.Font.GothamBold; btn.TextSize = 10
    btn.TextColor3 = T.White; btn.BorderSizePixel = 0; btn.AutoButtonColor = false; btn.Parent = parent
    corner(btn, 5)
    btn.MouseButton1Click:Connect(function()
        tw(btn,{BackgroundColor3=T.Accent},0.07)
        task.delay(0.1, function() tw(btn,{BackgroundColor3=T.AccentDim},0.1) end)
        callback()
    end)
    btn.MouseEnter:Connect(function() tw(btn,{BackgroundColor3=T.Accent},0.08) end)
    btn.MouseLeave:Connect(function() tw(btn,{BackgroundColor3=T.AccentDim},0.08) end)
    return btn
end

-- Section separator
local function AddSep(parent)
    local s = mkFrame(parent, "Sep", UDim2.new(1,-8,0,1), nil, T.Border)
    s.BackgroundTransparency = 0.6
end

-- ═══════════════════════════════════════════════
--  CATCHING COLUMN
-- ═══════════════════════════════════════════════
local catchCol = NewCol("Catching", Color3.fromRGB(60, 140, 255))

local magnetToggle   = AddToggle(catchCol, "Magnets", false)
local magnetsType    = AddDropdown(catchCol, "Mag Type", {"Blatant","Legit","League","Custom"}, "Legit")
local magRadius      = AddSlider(catchCol, "Custom Radius", 0, 70, 20, "%d")
local showHitbox     = AddToggle(catchCol, "Show Hitbox", false)

AddSep(catchCol)

local pullVecToggle  = AddToggle(catchCol, "PullVector", false)
local pullVecDist    = AddSlider(catchCol, "PV Distance", 0, 100, 40, "%d")
local pullVecType    = AddDropdown(catchCol, "PV Type", {"Glide","Teleport"}, "Glide")
local pullVecPower   = AddSlider(catchCol, "PV Power", 1, 5, 2, "%d")

-- ─── magnet hitbox display part ───
local magPart = Instance.new("Part")
magPart.Transparency = 0.5; magPart.Anchored = true
magPart.CanCollide = false; magPart.CastShadow = false

-- ─── catching arm detection ───
local function onCharacterCatching(character)
    local arm = character:WaitForChild("Left Arm")
    arm.ChildAdded:Connect(function(child)
        if not child:IsA("Weld") then return end
        isCatching = true
        task.wait(1.7)
        isCatching = false
    end)
end

-- ─── ball velocity tracking ───
track(workspace.ChildAdded:Connect(function(ball)
    if ball.Name ~= "Football" then return end
    if not ball:IsA("BasePart") then return end
    task.wait()
    local lastPos = ball.Position; local lastCheck = os.clock()
    while ball.Parent do
        task.wait(0.1)
        local t = os.clock() - lastCheck
        velocity[ball] = (ball.Position - lastPos) / t
        lastCheck = os.clock(); lastPos = ball.Position
    end
end))

-- ─── magnets logic ───
task.spawn(function()
    while true do
        task.wait(1/60)
        local ball = findClosestBall(); if not ball then magPart.Parent = nil continue end
        local char = LP.Character; if not char then continue end
        local catchPart = getNearestPartFromParts(ball, {char:FindFirstChild("CatchLeft"), char:FindFirstChild("CatchRight")})
        if not catchPart or not velocity[ball] then continue end
        if not magnetToggle.Get() then magPart.Parent = nil continue end

        local magType = magnetsType.Get()
        if magType == "League" then
            local predicted = ball.Position + (velocity[ball] * ping)
            local dist = (catchPart.Position - predicted).Magnitude
            local radius = magRadius.Get()
            magPart.Position = predicted
            magPart.Size = Vector3.new(radius,radius,radius)
            magPart.Parent = showHitbox.Get() and workspace or nil
            if dist <= radius then
                pcall(firetouchinterest, catchPart, ball, 0)
                pcall(firetouchinterest, catchPart, ball, 1)
            end
        else
            local dist = (catchPart.Position - ball.Position).Magnitude
            local radius = (magType=="Blatant" and 50) or (magType=="Custom" and magRadius.Get()) or 6
            magPart.Position = ball.Position
            magPart.Size = Vector3.new(radius,radius,radius)
            magPart.Parent = showHitbox.Get() and workspace or nil
            if dist < radius then
                pcall(firetouchinterest, catchPart, ball, 0)
                pcall(firetouchinterest, catchPart, ball, 1)
            end
        end
    end
end)

-- ─── pull vector logic ───
task.spawn(function()
    while true do
        task.wait()
        local ball = findClosestBall(); if not ball then continue end
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        if not ball:FindFirstChildWhichIsA("Trail") then continue end
        if not pullVecToggle.Get() then continue end
        if pullVectoredBalls[ball] then continue end
        if ball.Anchored then continue end
        local dist = (hrp.Position - ball.Position).Magnitude
        if dist > pullVecDist.Get() then continue end
        local dir = (ball.Position - hrp.Position).Unit
        if pullVecType.Get() == "Teleport" then
            pullVectoredBalls[ball] = true
            local d = 10 + ((pullVecPower.Get()-1)*5)
            hrp.CFrame = hrp.CFrame + dir*d
        else
            hrp.AssemblyLinearVelocity = dir * pullVecPower.Get() * 25
        end
    end
end)

onCharacterCatching(LP.Character or LP.CharacterAdded:Wait())
LP.CharacterAdded:Connect(onCharacterCatching)

-- ═══════════════════════════════════════════════
--  PHYSICS COLUMN
-- ═══════════════════════════════════════════════
local physCol = NewCol("Physics", Color3.fromRGB(120, 80, 220))

local quickTP        = AddToggle(physCol, "QuickTP", false)
local quickTPSpeed   = AddSlider(physCol, "QTP Speed", 1, 5, 2, "%d")
local quickTPBind    = AddKeybind(physCol, "QTP Bind", Enum.KeyCode.F)

AddSep(physCol)

local ctAimbot       = AddToggle(physCol, "ClickTackleBot", false)
local ctAimbotDist   = AddSlider(physCol, "CT Distance", 0, 15, 8, "%d")

AddSep(physCol)

local antiJam        = AddToggle(physCol, "AntiJam", false)
local antiBlock      = AddToggle(physCol, "AntiBlock", false)
local visBallPath    = AddToggle(physCol, "VisualiseBallPath", false)
local noJumpCD       = AddToggle(physCol, "NoJumpCooldown", false)
local noFreeze       = AddToggle(physCol, "NoFreeze", false)
local optimalJump    = AddToggle(physCol, "OptimalJump", false)
local optJumpType    = AddDropdown(physCol, "Jump Type", {"Jump","Dive"}, "Jump")
local noBallTrail    = AddToggle(physCol, "NoBallTrail", false)
local bigHead        = AddToggle(physCol, "BigHead", false)
local bigHeadSize    = AddSlider(physCol, "Head Size", 1, 5, 2, "%d")
local antiOOB        = AddToggle(physCol, "AntiOOB", false)
local flyToggle      = AddToggle(physCol, "Fly", false)
local flySpeed_ref   = AddSlider(physCol, "Fly Speed", 1, 10, 3, "%d")
local cframeSpeed    = AddToggle(physCol, "CFrameSpeed", false)
local cframeVal      = AddSlider(physCol, "CF Speed", 0, 10, 3, "%d")
local blockExtender  = AddToggle(physCol, "BlockExtender", false)
local blockExtRange  = AddSlider(physCol, "Block Range", 1, 20, 5, "%d")

-- ─── AntiOOB ───
local boundaries = {}
pcall(function()
    if not IS_PRACTICE then
        for _, p in pairs(workspace.Models.Boundaries:GetChildren()) do
            boundaries[#boundaries+1] = p
        end
    end
end)

-- ─── quickTP ───
local quickTPCooldown = os.clock()
track(UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode ~= quickTPBind.Get() then return end
    if not quickTP.Get() then return end
    local char = LP.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    if (os.clock()-quickTPCooldown) < 0.1 then return end
    local speed = 2 + (quickTPSpeed.Get()/4)
    hrp.CFrame = hrp.CFrame + hum.MoveDirection * speed
    quickTPCooldown = os.clock()
end))

-- ─── click tackle aimbot ───
track(Mouse.Button1Down:Connect(function()
    if not ctAimbot.Get() then return end
    local possessor = findPossessor(); local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not hrp or not possessor then return end
    local dist = (possessor.HumanoidRootPart.Position - hrp.Position).Magnitude
    if dist > ctAimbotDist.Get() then return end
    hrp.CFrame = possessor.HumanoidRootPart.CFrame
end))

-- ─── character physics loop ───
local function onCharacterPhysics(char)
    local hum = char:WaitForChild("Humanoid")
    char.DescendantAdded:Connect(function(v)
        task.wait()
        if v.Name:match("FFmover") and antiBlock.Get() then v:Destroy() end
    end)
    task.spawn(function()
        while hum.Parent do
            task.wait()
            if noJumpCD.Get() then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
            local torso = char:FindFirstChild("Torso")
            local head  = char:FindFirstChild("Head")
            if not torso or not head then break end
            if hum:GetState() == Enum.HumanoidStateType.Running and values.Status.Value == "InPlay" then
                torso.CanCollide = not antiJam.Get()
                head.CanCollide  = not antiJam.Get()
            else
                torso.CanCollide = true; head.CanCollide = true
            end
        end
    end)
end

-- ─── BigHead loop ───
task.spawn(function()
    local function applyBigHead(character)
        local head = character and character:FindFirstChild("Head")
        local mesh = head and head:FindFirstChildWhichIsA("SpecialMesh")
        if not mesh then return end
        local bh = bigHead.Get(); local sz = bigHeadSize.Get()
        mesh.MeshType = bh and Enum.MeshType.Sphere or Enum.MeshType.Head
        head.Size = bh and Vector3.new(sz,1,sz) or Vector3.new(2,1,1)
    end
    while true do
        task.wait()
        for _, p in pairs(Players:GetPlayers()) do
            if p == LP then continue end
            if p.Character then applyBigHead(p.Character) end
        end
    end
end)

-- ─── Fly ───
local flying = false
local flyBodyV, flyBodyG
flyToggle.Set = function(self, v)
    -- override
end
track(RunService.Stepped:Connect(function()
    if not flyToggle.Get() then
        if flyBodyV then pcall(function() flyBodyV:Destroy() end) flyBodyV = nil end
        if flyBodyG then pcall(function() flyBodyG:Destroy() end) flyBodyG = nil end
        local char = LP.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
        end
        flying = false
        return
    end
    local char = LP.Character; if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    if not flyBodyV then
        hum.PlatformStand = true
        flyBodyV = Instance.new("BodyVelocity", hrp)
        flyBodyV.MaxForce = Vector3.new(math.huge,math.huge,math.huge)
        flyBodyV.Velocity = Vector3.new(0,0,0)
        flyBodyG = Instance.new("BodyGyro", hrp)
        flyBodyG.P = 15000
        flyBodyG.MaxTorque = Vector3.new(math.huge,math.huge,math.huge)
    end
    flying = true
    local spd = 11 + (flySpeed_ref.Get() * 2.5)
    local endPos = Camera.CFrame.Position + Camera.CFrame.LookVector*500
    flyBodyG.CFrame = CFrame.new(hrp.Position, endPos)
    local vel = Vector3.new()
    if not UserInputService:GetFocusedTextBox() then
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then vel += Camera.CFrame.LookVector * spd end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then vel -= Camera.CFrame.LookVector * spd end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then vel += hrp.CFrame:vectorToWorldSpace(Vector3.new(-spd,0,0)) end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then vel += hrp.CFrame:vectorToWorldSpace(Vector3.new(spd,0,0)) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then vel += Vector3.new(0,spd,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then vel -= Vector3.new(0,spd,0) end
    end
    flyBodyV.Velocity = vel
end))

-- ─── CFrameSpeed ───
task.spawn(function()
    while true do
        task.wait()
        if not cframeSpeed.Get() then continue end
        local char = LP.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then continue end
        local md = hum.MoveDirection
        hrp.CFrame = hrp.CFrame + md * (cframeVal.Get()/58.5)
    end
end)

-- ─── AntiOOB toggle ───
local lastAntiOOB = false
task.spawn(function()
    while true do
        task.wait()
        local v = antiOOB.Get()
        if v ~= lastAntiOOB then
            lastAntiOOB = v
            for _, b in pairs(boundaries) do
                b.Parent = not v and workspace.Models.Boundaries or nil
            end
        end
    end
end)

-- ─── BallPath beam ───
local bpA0, bpA1 = Instance.new("Attachment"), Instance.new("Attachment")
bpA0.Parent = workspace.Terrain; bpA1.Parent = workspace.Terrain
local bpBeam = Instance.new("Beam", workspace.Terrain)
bpBeam.Attachment0 = bpA0; bpBeam.Attachment1 = bpA1
bpBeam.Segments = 500; bpBeam.Width0 = 0.5; bpBeam.Width1 = 0.5
bpBeam.Transparency = NumberSequence.new(0)
bpBeam.Color = ColorSequence.new(Color3.fromHex("#FF8EA5"))

track(workspace.ChildAdded:Connect(function(ball)
    task.wait()
    if ball.Name ~= "Football" or not ball:IsA("BasePart") then return end

    if noBallTrail.Get() and ball:FindFirstChildWhichIsA("Trail") then
        ball:FindFirstChildWhichIsA("Trail").Enabled = false
    end

    -- optimalJump
    task.spawn(function()
        if not optimalJump.Get() then return end
        local iv = ball.AssemblyLinearVelocity
        local currentPos = ball.Position; local t = 0
        local optPos = Vector3.zero
        while true do
            t += 0.05; iv += Vector3.new(0,-28*0.05,0)
            currentPos += iv*0.05
            local rp = RaycastParams.new()
            pcall(function() rp.FilterDescendantsInstances = {workspace:FindFirstChild("Models")} end)
            rp.FilterType = Enum.RaycastFilterType.Include
            local ray = workspace:Raycast(currentPos, Vector3.new(0, optJumpType.Get()=="Jump" and -13 or -15, 0), rp)
            local aRay = workspace:Raycast(currentPos, Vector3.new(0,-500,0), rp)
            if ray and t > 0.75 then optPos = ray.Position + Vector3.new(0,2,0) break end
            if not aRay then optPos = currentPos break end
        end
        local p = Instance.new("Part"); p.Anchored = true
        p.Material = Enum.Material.Neon; p.Size = Vector3.new(1.5,1.5,1.5)
        p.Position = optPos; p.CanCollide = false; p.Parent = workspace
        repeat task.wait() until ball.Parent ~= workspace
        p:Destroy()
    end)

    -- visualise ball path
    task.spawn(function()
        if not visBallPath.Get() then return end
        local iv = ball.AssemblyLinearVelocity
        local g = Vector3.new(0,-28,0); local x0 = ball.Position; local v0 = iv
        local c0,c1,cf1,cf2 = beamProjectile(g,v0,x0,5)
        bpBeam.CurveSize0=c0; bpBeam.CurveSize1=c1
        bpA0.CFrame = bpA0.Parent.CFrame:inverse()*cf1
        bpA1.CFrame = bpA1.Parent.CFrame:inverse()*cf2
        repeat task.wait() until ball.Parent ~= workspace
        bpBeam.CurveSize0=0; bpBeam.CurveSize1=0
    end)
end))

onCharacterPhysics(LP.Character or LP.CharacterAdded:Wait())
LP.CharacterAdded:Connect(onCharacterPhysics)

-- ═══════════════════════════════════════════════
--  THROWING COLUMN
-- ═══════════════════════════════════════════════
local throwCol = NewCol("Throwing", Color3.fromRGB(220, 100, 60))

local qbAimbot        = AddToggle(throwCol, "QBAimbot", false)
local qbVisualise     = AddToggle(throwCol, "Visualise", true)
local qbAutoAngle     = AddToggle(throwCol, "AutoAngle", false)
local qbAutoThrowType = AddToggle(throwCol, "AutoThrowType", false)
local qb95Power       = AddToggle(throwCol, "95PowerOnly", false)
local qbAntiOOB       = AddToggle(throwCol, "AntiOOB", false)
local qbXOffset       = AddSlider(throwCol, "X Offset", -5, 5, 0, "%d")
local qbYOffset       = AddSlider(throwCol, "Y Offset", -5, 5, 0, "%d")
local qbDimeBind      = AddKeybind(throwCol, "Dime Bind", Enum.KeyCode.One)
local qbJumpBind      = AddKeybind(throwCol, "Jump Bind", Enum.KeyCode.Two)
local qbBulletBind    = AddKeybind(throwCol, "Bullet Bind", Enum.KeyCode.Three)
local qbDiveBind      = AddKeybind(throwCol, "Dive Bind", Enum.KeyCode.Four)
local qbMagBind       = AddKeybind(throwCol, "Mag Bind", Enum.KeyCode.Five)
AddSep(throwCol)
local trajectory      = AddToggle(throwCol, "Trajectory", false)

-- ─── throw type key switching ───
local throwType = "Dive"
local throwTypesSwitch = {Dive="Mag",Mag="Bullet",Bullet="Jump",Jump="Dime",Dime="Dive"}

track(UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    local k = inp.KeyCode
    if k == qbDimeBind.Get()   then throwType = "Dime"
    elseif k == qbJumpBind.Get()   then throwType = "Jump"
    elseif k == qbBulletBind.Get() then throwType = "Bullet"
    elseif k == qbDiveBind.Get()   then throwType = "Dive"
    elseif k == qbMagBind.Get()    then throwType = "Mag"
    end
end))

-- ─── trajectory beam ───
local tA0, tA1 = Instance.new("Attachment"), Instance.new("Attachment")
tA0.Parent = workspace.Terrain; tA1.Parent = workspace.Terrain
local tBeam = Instance.new("Beam", workspace.Terrain)
tBeam.Attachment0 = tA0; tBeam.Attachment1 = tA1
tBeam.Segments = 500; tBeam.Width0 = 0.5; tBeam.Width1 = 0.5
tBeam.Transparency = NumberSequence.new(0)
tBeam.Color = ColorSequence.new(Color3.fromHex("#EBAFCC"))

task.spawn(function()
    while true do
        task.wait()
        local ballGui = LP.PlayerGui:FindFirstChild("BallGui")
        local char = LP.Character; local head = char and char:FindFirstChild("Head")
        if not head then continue end
        if not ballGui or not trajectory.Get() then tBeam.Parent = nil continue end
        tBeam.Parent = workspace.Terrain
        local power = tonumber(ballGui:FindFirstChild("Disp",true) and ballGui:FindFirstChild("Disp",true).Text) or 65
        local dir = (Mouse.Hit.Position - Camera.CFrame.Position).Unit
        local origin = head.Position + dir*5
        local c0,c1,cf1,cf2 = beamProjectile(Vector3.new(0,-28,0), power*dir, origin, 10)
        tBeam.CurveSize0=c0; tBeam.CurveSize1=c1
        tA0.CFrame = tA0.Parent.CFrame:inverse()*cf1
        tA1.CFrame = tA1.Parent.CFrame:inverse()*cf2
    end
end)

-- ─── QB Aimbot core logic ───
local qbHighlight = Instance.new("Highlight")
qbHighlight.FillColor = Color3.fromHex("#6a64a2"); qbHighlight.Parent = ReplicatedStorage

local qbAimPart = Instance.new("Part"); qbAimPart.Anchored = true
qbAimPart.CanCollide = false; qbAimPart.Parent = workspace

local qbLocked = false; local qbTarget = nil
local qbAngle = 45; local qbPower = 65; local qbDirection = Vector3.new(0,1,0)

local sidewayRoutes = {"in/out","flat"}
local inAirAdditiveRoutes = {"stationary","curl/comeback"}
local within = table.find

local qbOffsets = {
    Dive={xLead=3,yLead=4.5,routes={["go"]={xzOffset=0,yOffset=0},["post/corner"]={xzOffset=0,yOffset=0},["slant"]={xzOffset=0,yOffset=0},["in/out"]={xzOffset=-1,yOffset=-2},["flat"]={xzOffset=0,yOffset=-2},["curl/comeback"]={xzOffset=4,yOffset=0},["stationary"]={xzOffset=0,yOffset=0}}},
    Mag={xLead=3,yLead=6,routes={["go"]={xzOffset=0,yOffset=0},["post/corner"]={xzOffset=0,yOffset=0},["slant"]={xzOffset=0,yOffset=0},["in/out"]={xzOffset=-1,yOffset=-2},["flat"]={xzOffset=0,yOffset=-2},["curl/comeback"]={xzOffset=6,yOffset=0},["stationary"]={xzOffset=0,yOffset=0}}},
    Jump={xLead=2,yLead=3,routes={["go"]={xzOffset=0,yOffset=-1.5},["post/corner"]={xzOffset=0,yOffset=0},["slant"]={xzOffset=0,yOffset=0},["in/out"]={xzOffset=-1,yOffset=3},["flat"]={xzOffset=0,yOffset=3},["curl/comeback"]={xzOffset=2,yOffset=4},["stationary"]={xzOffset=0,yOffset=7.5}}},
    Dime={xLead=2,routes={["go"]={xzOffset=0,yOffset=0},["post/corner"]={xzOffset=0,yOffset=0},["slant"]={xzOffset=0,yOffset=0},["in/out"]={xzOffset=-1,yOffset=-1},["flat"]={xzOffset=0,yOffset=-1},["curl/comeback"]={xzOffset=2,yOffset=0},["stationary"]={xzOffset=0,yOffset=0}}},
}

local function findTarget(opp)
    local cc = workspace.CurrentCamera; local target = nil; local dist = math.huge
    local targets = {}
    for _, p in pairs(Players:GetPlayers()) do
        if not opp then
            if LP.Team and LP.Team ~= p.Team then continue end
        else
            if LP.Team and LP.Team == p.Team then continue end
        end
        if p.Character then targets[#targets+1] = p.Character end
    end
    if IS_PRACTICE then
        pcall(function()
            targets[#targets+1] = workspace.npcwr.a['bot 1']
            targets[#targets+1] = workspace.npcwr.a['bot 2']
        end)
    end
    for _, v in pairs(targets) do
        local hrp = v and v:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        local sp = cc:WorldToViewportPoint(hrp.Position)
        local ml = UserInputService:GetMouseLocation()
        local check = (Vector2.new(ml.X,ml.Y) - Vector2.new(sp.X,sp.Y)).magnitude
        if check < dist then target = v; dist = check end
    end
    return target
end

local function findRoute(character)
    local isPlayer = Players:GetPlayerFromCharacter(character)
    local md = isPlayer and character.Humanoid.MoveDirection or (character.Humanoid.WalkToPoint - character.HumanoidRootPart.Position).Unit
    local dist = (character.HumanoidRootPart.Position - LP.Character.HumanoidRootPart.Position).Magnitude
    local function isDiag() local a=Vector3.new(math.abs(md.X),0,math.abs(md.Z)) return (a-Vector3.new(0.7,0,0.7)).Magnitude < 0.5 end
    local function isSide() local d=(character.HumanoidRootPart.Position-LP.Character.HumanoidRootPart.Position).Unit local h=math.abs(d.X)>math.abs(d.Z) and "Z" or "X" return math.abs(md[h])>0.8 end
    local function toQB() local nd=((character.HumanoidRootPart.Position+(md*16))-LP.Character.HumanoidRootPart.Position).Magnitude return (dist-nd)>12 end
    local reqs={["go"]=function() return not isDiag() and not toQB() end,["post/corner"]=function() return isDiag() and not toQB() and dist>125 end,["slant"]=function() return isDiag() and not toQB() and dist<=125 end,["in/out"]=function() return isSide() and dist>125 end,["flat"]=function() return isSide() and dist<=125 end,["curl/comeback"]=function() return toQB() end,["stationary"]=function() return md.Magnitude<=0 end}
    local route = nil
    for rname, f in pairs(reqs) do route = f() and rname or route if route then break end end
    return route or "go", md
end

local function determineAutoAngle(dist, route)
    local fn={["go"]=function() return math.min(25+(dist/10),40) end,["in/out"]=function() return 10+math.max((dist-100),0)/10 end,["flat"]=function() return 10+math.max((dist-100),0)/10 end,["curl/comeback"]=function() return 7.5+math.max((dist-100),0)/20 end,["stationary"]=function() return 17+math.max((dist-100),0)/20 end}
    return (fn[route] or fn["go"])()
end

local function determine95Angle(dist, route)
    local IN_AIR = LP.Character and LP.Character.Humanoid and LP.Character.Humanoid.FloorMaterial == Enum.Material.Air
    local fn={["go"]=function()
        return dist>150 and math.max(IN_AIR and (16+math.max(dist-100,0)/5) or (14+math.max(dist-100,0)/5),25)
            or (IN_AIR and 16.5+math.max(dist,0)*(12.5/150) or 14+math.max(dist,0)*(12.5/150))
    end,["in/out"]=function() return 10+math.max((dist-100),0)/10 end,["flat"]=function() return 10+math.max((dist-100),0)/10 end,["curl/comeback"]=function() return 7.5+math.max((dist-100),0)/20 end,["stationary"]=function() return 13.5+math.max((dist-100),0)/20 end}
    return (fn[route] or fn["go"])()
end

local function finalCalc(target, angle, xLead, yLead, sideways)
    local char = LP.Character
    local tHRP = target:FindFirstChild("HumanoidRootPart")
    local dist = (tHRP.Position - char.HumanoidRootPart.Position).Magnitude
    local md = tHRP.CFrame.LookVector * tHRP.AssemblyLinearVelocity.Magnitude
    local predictedPos = tHRP.Position + md*(dist/65) + Vector3.new(xLead*(sideways and 0 or 1),yLead,xLead*(sideways and 1 or 0))
    local head = char:FindFirstChild("Head")
    local diff = predictedPos - head.Position
    local flatDist = Vector3.new(diff.X,0,diff.Z).Magnitude
    local angleRad = math.rad(angle)
    local speed = math.sqrt((9.81 * flatDist) / math.sin(2*angleRad))
    local flatDir = Vector3.new(diff.X,0,diff.Z).Unit
    local vel = Vector3.new(flatDir.X*speed*math.cos(angleRad), speed*math.sin(angleRad), flatDir.Z*speed*math.cos(angleRad))
    local airtime = flatDist / (speed*math.cos(angleRad))
    return vel, predictedPos, airtime
end

-- ─── QB Aimbot main loop ───
task.spawn(function()
    while true do
        task.wait()
        local ok, err = pcall(function()
            local ballGui = LP.PlayerGui:FindFirstChild("BallGui")
            local hasBall = ballGui or (Camera.CameraSubject and Camera.CameraSubject:IsA("BasePart"))

            qbAimPart.Transparency = qbVisualise.Get() and qbAimbot.Get() and hasBall and 0 or 1
            qbHighlight.Enabled = qbVisualise.Get() and qbAimbot.Get() and ballGui ~= nil
            qbHighlight.FillColor = qbLocked and Color3.fromHex("#6a64a2") or Color3.fromRGB(255,255,255)
            qbHighlight.OutlineColor = qbLocked and Color3.fromRGB(255,255,255) or Color3.fromHex("#6a64a2")

            if not ballGui then return end
            if not qbAimbot.Get() then return end
            if not LP.Character or not LP.Character:FindFirstChild("HumanoidRootPart") then return end

            qbTarget = (qbLocked and qbTarget) or findTarget()
            if not qbTarget or not qbTarget.Parent then qbLocked = false return end
            if not qbTarget:FindFirstChild("HumanoidRootPart") then qbLocked = false return end

            local IN_AIR = LP.Character.Humanoid.FloorMaterial == Enum.Material.Air
            local dist = (qbTarget.HumanoidRootPart.Position - LP.Character.HumanoidRootPart.Position).Magnitude
            local route = findRoute(qbTarget)

            local tt = throwType
            if qbAutoThrowType.Get() then
                local forwardRoutes = {"go","post/corner","slant","curl/comeback","stationary"}
                local dbDist = math.huge
                for _, p in pairs(Players:GetPlayers()) do
                    local pChar = p.Character; local pHRP = pChar and pChar:FindFirstChild("HumanoidRootPart")
                    if pHRP then local d=(pHRP.Position-qbTarget.HumanoidRootPart.Position).Magnitude if d<dbDist then dbDist=d end end
                end
                if within(forwardRoutes, route) then
                    tt = dbDist>5 and ((qb95Power.Get() or qbAngle<40) and "Jump" or "Dime") or dbDist>2 and "Dive" or "Mag"
                else tt = dbDist>4 and "Dime" or "Jump" end
            end

            local realTT = tt
            if tt == "Bullet" then tt = IN_AIR and "Jump" or "Dime" end

            local xLead = (qbOffsets[tt] and qbOffsets[tt].xLead) or 0
            local yLead = (qbOffsets[tt] and qbOffsets[tt].yLead) or 0

            if qb95Power.Get() and tt == "Jump" then xLead+=3.5; yLead-=1 end
            if qbAngle > 30 and qb95Power.Get() and route=="go" then yLead -= 0.5+math.min(qbAngle-30,5)/10 end
            if within(sidewayRoutes, route) and IN_AIR then yLead+=8; xLead+=3 end
            if within(inAirAdditiveRoutes, route) and IN_AIR then yLead+=4 end
            if qbOffsets[tt] and qbOffsets[tt].routes and qbOffsets[tt].routes[route] then
                xLead += qbOffsets[tt].routes[route].xzOffset or 0
                yLead += qbOffsets[tt].routes[route].yOffset or 0
            end
            xLead += qbXOffset.Get(); yLead += qbYOffset.Get()
            if IN_AIR and qb95Power.Get() then yLead+=1 end

            qbAngle = qb95Power.Get() and determine95Angle(dist,route)
                or qbAutoAngle.Get() and determineAutoAngle(dist,route) or qbAngle
            if not qbAutoAngle.Get() and not qb95Power.Get() and qbAngle%5 ~= 0 then qbAngle = 45 end

            local s2, vel, pos, airtime = pcall(finalCalc, qbTarget, qbAngle, xLead, yLead, within(sidewayRoutes,route)~=nil)
            if not s2 then return end

            qbPower = math.min(math.round(vel.Magnitude), 95)
            qbDirection = vel.Unit

            local c0,c1,cf1,cf2 = beamProjectile(Vector3.new(0,-28,0), qbPower*qbDirection, LP.Character.Head.Position+(qbDirection*5), airtime)
            tBeam.CurveSize0=c0; tBeam.CurveSize1=c1
            tA0.CFrame = tA0.Parent.CFrame:inverse()*cf1
            tA1.CFrame = tA1.Parent.CFrame:inverse()*cf2

            qbAimPart.Position = pos
            qbHighlight.Adornee = qbTarget
            qbHighlight.Parent = qbTarget
        end)
    end
end)

-- Lock/Unlock keybind (Q)
track(UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.Q and qbAimbot.Get() then
        qbLocked = not qbLocked
        Notify("QB Aimbot", qbLocked and "Target Locked" or "Target Unlocked", qbLocked and "warn" or "success")
    end
end))

-- ═══════════════════════════════════════════════
--  VISUALS COLUMN
-- ═══════════════════════════════════════════════
local visCol = NewCol("Visuals", Color3.fromRGB(60, 190, 140))

local camZoom = AddToggle(visCol, "CameraZoom", false)
local camZoomDist = AddSlider(visCol, "Zoom Dist", 0, 1000, 100, "%d", function(v)
    if camZoom.Get() then LP.CameraMaxZoomDistance = v end
end)
camZoom = AddToggle(visCol, "CameraZoom", false)  -- re-ref with callback
task.spawn(function()
    while true do task.wait()
        if not camZoom.Get() then LP.CameraMaxZoomDistance = 50 end
    end
end)

local noRender = AddToggle(visCol, "NoRender", false, function(v)
    settings().Rendering.QualityLevel = v and 1 or 21
end)

local renderTextures = AddToggle(visCol, "Remove Textures", false, function(v)
    for _, p in pairs(workspace:GetDescendants()) do
        if not p:IsA("BasePart") then continue end
        if v then
            p:SetAttribute("origMat", p.Material.Name)
            p.Material = Enum.Material.SmoothPlastic
        else
            if p:GetAttribute("origMat") then
                pcall(function() p.Material = Enum.Material[p:GetAttribute("origMat")] end)
            end
        end
    end
end)

local silentMode = AddToggle(visCol, "SilentMode", false)
AddSep(visCol)

local fullBright = AddToggle(visCol, "FullBright", false, function(v)
    Lighting.Brightness = v and 2 or 1
    Lighting.GlobalShadows = not v
    Lighting.Ambient = v and Color3.fromRGB(178,178,178) or Color3.fromRGB(127,127,127)
end)

local playerESP = AddToggle(visCol, "Player ESP", false)
task.spawn(function()
    while true do task.wait()
        for _, p in pairs(Players:GetPlayers()) do
            if p == LP or not p.Character then continue end
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end
            local existingBB = hrp:FindFirstChild("FF2ESP")
            if playerESP.Get() and not existingBB then
                local bb = Instance.new("BillboardGui")
                bb.Name = "FF2ESP"; bb.Adornee = hrp
                bb.Size = UDim2.new(0,60,0,20); bb.StudsOffset = Vector3.new(0,3.5,0)
                bb.AlwaysOnTop = true; bb.Parent = hrp
                local lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1
                lbl.Text = p.Name; lbl.TextColor3 = T.Accent
                lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 11; lbl.Parent = bb
            elseif not playerESP.Get() and existingBB then
                existingBB:Destroy()
            end
        end
    end
end)

local fovSlider = AddSlider(visCol, "FOV", 60, 120, 70, "%d°", function(v)
    workspace.CurrentCamera.FieldOfView = v
end)

-- ═══════════════════════════════════════════════
--  AUTOMATICS COLUMN
-- ═══════════════════════════════════════════════
local autoCol = NewCol("Automatics", Color3.fromRGB(200, 80, 80))

local autoQB      = AddToggle(autoCol, "AutoQB", false)
local autoQBType  = AddDropdown(autoCol, "QB Type", {"Blatant","Legit"}, "Legit")
local autoCaptain = AddToggle(autoCol, "AutoCaptain", false)
local autoCatch   = AddToggle(autoCol, "AutoCatch", false)
local autoCatchR  = AddSlider(autoCol, "Catch Radius", 0, 50, 15, "%d")
local autoSwat    = AddToggle(autoCol, "AutoSwat", false)
local autoSwatR   = AddSlider(autoCol, "Swat Radius", 0, 50, 15, "%d")

AddSep(autoCol)

local autoKick    = AddToggle(autoCol, "AutoKick", false)
local kickPower   = AddSlider(autoCol, "Kick Power", 0, 100, 100, "%d")
local kickAccuracy= AddSlider(autoCol, "Kick Accuracy", 0, 100, 100, "%d")
local kickRandom  = AddToggle(autoCol, "Random Kick", false)

AddSep(autoCol)

local autoRush    = AddToggle(autoCol, "AutoRush", false)
local autoRushDel = AddSlider(autoCol, "Rush Delay", 0, 1, 0, "%.2f")
local autoRushPred= AddToggle(autoCol, "Rush Predict", false)
local autoBoost   = AddToggle(autoCol, "AutoBoost", false)
local autoBoostPow= AddSlider(autoCol, "Boost Power", 1, 15, 5, "%d")
local autoGuard   = AddToggle(autoCol, "AutoGuard", false)
local guardBind   = AddKeybind(autoCol, "Guard Lock", Enum.KeyCode.G)

-- ─── AutoCaptain ───
pcall(function()
    local finishLine = not IS_PRACTICE and workspace.Models.LockerRoomA.FinishLine or Instance.new("Part")
    finishLine:GetPropertyChangedSignal("CFrame"):Connect(function()
        if autoCaptain.Get() and not isCatching and finishLine.Position.Y > 0 then
            for i = 1,7 do
                task.wait(0.2)
                if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
                    LP.Character.HumanoidRootPart.CFrame = finishLine.CFrame + Vector3.new(0,2,0)
                end
            end
        end
    end)
end)

-- ─── AutoKick ───
track(LP.PlayerGui.ChildAdded:Connect(function(child)
    if child.Name == "KickerGui" and autoKick.Get() then
        local cursor = child:FindFirstChild("Cursor", true)
        if kickRandom.Get() then
            kickPower.Set(math.floor(Random.new():NextNumber(75,100)))
            kickAccuracy.Set(math.floor(Random.new():NextNumber(75,100)))
        end
        local pw = kickPower.Get(); local acc = kickAccuracy.Get()
        repeat task.wait() until cursor.Position.Y.Scale < 0.01 + ((100-pw)*0.012) + (fps<45 and 0.01 or 0)
        pcall(mouse1click)
        repeat task.wait() until cursor.Position.Y.Scale > 0.9 - ((100-acc)*0.001)
        pcall(mouse1click)
    end
end))

-- ─── AutoCatch / AutoSwat ───
task.spawn(function()
    while true do
        task.wait()
        local ball = findClosestBall(); if not ball then continue end
        local char = LP.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        local dist = (hrp.Position - ball.Position).Magnitude
        if autoCatch.Get() and dist < autoCatchR.Get() then pcall(mouse1click) end
        if autoSwat.Get() and dist < autoSwatR.Get() then pcall(function() keypress(0x52); keyrelease(0x52) end) end
    end
end)

-- ─── AutoQB ───
task.spawn(function()
    local lastTP = os.clock()
    while true do
        task.wait()
        if not autoQB.Get() then continue end
        pcall(function()
            if values.Status.Value ~= "PrePlay" then return end
            if values.PlayType and values.PlayType.Value ~= "normal" then return end
            if values.PossessionTag and LP.Team and values.PossessionTag.Value ~= LP.Team.Name then return end
        end)
        local char = LP.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then continue end
        local ball = findClosestBall(); if not ball then continue end
        if autoQBType.Get() == "Blatant" then
            if (os.clock()-lastTP) < 3 then continue end
            lastTP = os.clock()
            hrp.CFrame = ball.CFrame
        else
            moveToUsing[#moveToUsing+1] = os.clock()
            hum:MoveTo(ball.Position)
        end
    end
end)

-- ─── AutoRush ───
task.spawn(function()
    local log = {}
    while true do
        task.wait(1/30)
        local possessor = findPossessor()
        local char = LP.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then continue end
        if not possessor then log = {} continue end
        if not possessor:FindFirstChild("HumanoidRootPart") then continue end
        local delayed = log[math.max(#log - math.round(autoRushDel.Get()/(1/30)),1)]
        log[#log+1] = possessor.HumanoidRootPart.Position
        if not delayed then continue end
        if not autoRush.Get() then continue end
        local timeToMove = (hrp.Position - delayed).Magnitude / 20
        local predicted = delayed + (possessor.Humanoid.MoveDirection * timeToMove * 20)
        moveToUsing[#moveToUsing+1] = os.clock()
        hum:MoveTo(autoRushPred.Get() and predicted or delayed)
    end
end)

-- ─── AutoGuard ───
task.spawn(function()
    local guardLocked = false; local guardTarget = nil
    track(UserInputService.InputBegan:Connect(function(inp, gp)
        if gp then return end
        if inp.KeyCode == guardBind.Get() then guardLocked = not guardLocked end
    end))
    while true do
        task.wait()
        if not autoGuard.Get() then continue end
        guardTarget = guardLocked and guardTarget or findTarget(true)
        if not guardTarget then continue end
        local char = LP.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then continue end
        local pos = guardTarget.HumanoidRootPart.Position
        local timeToMove = (hrp.Position-pos).Magnitude/20
        local predicted = pos + (guardTarget.Humanoid.MoveDirection * timeToMove * 20)
        moveToUsing[#moveToUsing+1] = os.clock()
        hum:MoveTo(predicted)
    end
end)

-- ─── AutoBoost ───
local function onCharacterAutomatics(char)
    local leftLeg  = char:WaitForChild("Left Leg")
    local rightLeg = char:WaitForChild("Right Leg")
    local function onTouch(hit)
        if not hit.Name:match("Arm") and not hit.Name:match("Head") then return end
        if hit:IsDescendantOf(char) then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.FloorMaterial ~= Enum.Material.Air then return end
        if autoBoost.Get() then
            char:FindFirstChild("HumanoidRootPart").AssemblyLinearVelocity += Vector3.new(0,autoBoostPow.Get(),0)
        end
    end
    leftLeg.Touched:Connect(onTouch); rightLeg.Touched:Connect(onTouch)
end
onCharacterAutomatics(LP.Character or LP.CharacterAdded:Wait())
LP.CharacterAdded:Connect(onCharacterAutomatics)

-- ═══════════════════════════════════════════════
--  PLAYER COLUMN
-- ═══════════════════════════════════════════════
local playerCol = NewCol("Player", Color3.fromRGB(160, 200, 80))

local speedToggle  = AddToggle(playerCol, "Speed", false)
local speedVal     = AddSlider(playerCol, "Walk Speed", 20, 23, 20, "%d")
local jumpToggle   = AddToggle(playerCol, "JumpPower", false)
local jumpVal      = AddSlider(playerCol, "Jump Power", 50, 70, 50, "%d")

AddSep(playerCol)

local angleEnh     = AddToggle(playerCol, "AngleEnhancer", false)
local angleJP      = AddSlider(playerCol, "AE Jump Power", 50, 70, 55, "%d")
local angleInd     = AddToggle(playerCol, "AE Indicator", false)

AddSep(playerCol)

local repLag       = AddToggle(playerCol, "ReplicationLag", false)
local repLagVal    = AddSlider(playerCol, "Lag Value", 0, 100, 0, "%d")

AddSep(playerCol)

AddButton(playerCol, "Rejoin Server", function()
    pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId, LP) end)
end)
AddButton(playerCol, "Copy UserID", function()
    pcall(function() setclipboard(tostring(LP.UserId)) end)
    Notify("Player", "UserID copied!", "success")
end)
AddButton(playerCol, "Reset Character", function()
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.Health = 0 end
end)

-- ─── Speed via AssemblyLinearVelocity (actual paid method) ───
track(RunService:BindToRenderStep("FF2HubWalkSpeed", Enum.RenderPriority.Character.Value, function()
    local char = LP.Character; local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return end
    if hum:GetState() ~= Enum.HumanoidStateType.Running then return end
    if not char:FindFirstChild("HumanoidRootPart") then return end
    if not speedToggle.Get() and not noFreeze.Get() then return end
    local md = ((os.clock()-(moveToUsing[#moveToUsing] or 0))<0.5 and (hum.WalkToPoint-char.HumanoidRootPart.Position).Unit) or hum.MoveDirection
    local cv = char.HumanoidRootPart.AssemblyLinearVelocity
    local sv = speedToggle.Get() and (speedVal.Get()>20 and speedVal.Get()) or 20
    char.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(md.X*sv, cv.Y, md.Z*sv)
end))

-- ─── JumpPower ───
local function onCharacterMovement(char)
    local hum = char:WaitForChild("Humanoid")
    local hrp = char:WaitForChild("HumanoidRootPart")
    hum.Jumping:Connect(function()
        if hum:GetState() ~= Enum.HumanoidStateType.Jumping then return end
        task.wait(0.05)
        if jumpToggle.Get() then
            hrp.AssemblyLinearVelocity += Vector3.new(0, jumpVal.Get()-50, 0)
        end
    end)
end
onCharacterMovement(LP.Character or LP.CharacterAdded:Wait())
LP.CharacterAdded:Connect(onCharacterMovement)

-- ─── ReplicationLag ───
task.spawn(function()
    while true do
        task.wait()
        pcall(function()
            settings():GetService("NetworkSettings").IncomingReplicationLag = repLag.Get() and repLagVal.Get()/100 or 0
        end)
    end
end)

-- ─── AngleEnhancer ───
task.spawn(function()
    local angleTick = os.clock()
    local oldLook = Vector3.new()
    local shiftLock = false; local lastEnabled = false

    local function hookAngle(char)
        local hum = char:WaitForChild("Humanoid")
        local hrp = char:WaitForChild("HumanoidRootPart")
        hum.Jumping:Connect(function()
            if hum:GetState() ~= Enum.HumanoidStateType.Jumping then return end
            if os.clock()-angleTick > 0.2 then return end
            if not angleEnh.Get() then return end
            if angleInd.Get() then
                local h = Instance.new("Hint"); h.Text = "Angled"; h.Parent = workspace
                Debris:AddItem(h, 1)
            end
            task.wait(0.05)
            hrp.AssemblyLinearVelocity += Vector3.new(0, angleJP.Get()-50, 0)
        end)
    end
    hookAngle(LP.Character or LP.CharacterAdded:Wait())
    LP.CharacterAdded:Connect(hookAngle)

    track(UserInputService:GetPropertyChangedSignal("MouseBehavior"):Connect(function()
        shiftLock = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
    end))

    while true do
        task.wait()
        local char = LP.Character; if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then continue end
        local lookVec = hrp.CFrame.LookVector
        if not shiftLock and lastEnabled then angleTick = os.clock() end
        oldLook = lookVec; lastEnabled = shiftLock
    end
end)

-- ═══════════════════════════════════════════════
--  STATUS BAR
-- ═══════════════════════════════════════════════
local StatBar = mkFrame(Win, "StatBar", UDim2.new(1,-8,0,24), UDim2.new(0,4,1,-28), T.Panel)
corner(StatBar, 6); stroke(StatBar, T.Border, 1)
listlay(StatBar, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center, 10)
pad(StatBar, 0, 0, 10, 10)

local fpsLbl  = mkLabel(StatBar, "FPS: --",     UDim2.new(0,60,1,0), nil, Enum.Font.Gotham, 10, T.TextDim)
local pingLbl = mkLabel(StatBar, "Ping: --ms",  UDim2.new(0,80,1,0), nil, Enum.Font.Gotham, 10, T.TextDim)
local statusLbl = mkLabel(StatBar, "Status: --", UDim2.new(0,90,1,0), nil, Enum.Font.Gotham, 10, T.TextDim)
mkLabel(StatBar, "FF2 Hub v4.0  |  RightShift = toggle", UDim2.new(1,0,1,0), nil, Enum.Font.Gotham, 10, T.TextOff)

-- FPS update
local fpsCount = 0
track(RunService.RenderStepped:Connect(function()
    fpsCount += 1
    task.delay(1, function() fpsCount -= 1 end)
    fpsLbl.Text = "FPS: " .. fpsCount
end))

-- Ping/status update
task.spawn(function()
    while true do
        task.wait(2)
        pcall(function() pingLbl.Text = "Ping: " .. math.floor((getPing()+getServerPing())/2) .. "ms" end)
        pcall(function() statusLbl.Text = "Status: " .. (values and values:FindFirstChild("Status") and values.Status.Value or "?") end)
    end
end)

-- ═══════════════════════════════════════════════
--  TOGGLE KEY
-- ═══════════════════════════════════════════════
local hubVisible = true
track(UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.RightShift then
        hubVisible = not hubVisible
        tw(Win, {Size = hubVisible and UDim2.new(0,800,0,470) or UDim2.new(0,0,0,0)}, 0.2)
    end
end))

-- ═══════════════════════════════════════════════
--  OPEN ANIMATION
-- ═══════════════════════════════════════════════
Win.Size = UDim2.new(0,0,0,0)
tw(Win, {Size = UDim2.new(0,800,0,470)}, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
task.wait(0.5)
Notify("FF2 Hub v4.0", "Loaded! RightShift to toggle.", "success", 5)
print("[FF2Hub v4.0] Loaded successfully.")
