-- LocalScript: StarterGui 에 배치
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remote    = game:GetService("ReplicatedStorage"):WaitForChild("TerminalRemote")

----------------------------------------------------------------------
-- GUI 생성
----------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name          = "LuaOS_Terminal"
screenGui.ResetOnSpawn  = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent        = playerGui

local window = Instance.new("Frame")
window.Name            = "Window"
window.Size            = UDim2.new(0, 800, 0, 500)
window.Position        = UDim2.new(0.5, -400, 0.5, -250)
window.BackgroundColor3 = Color3.fromRGB(13, 13, 13)
window.BorderSizePixel = 0
window.Active          = true
window.Draggable       = true
window.Parent          = screenGui
Instance.new("UICorner", window).CornerRadius = UDim.new(0,6)

-- 타이틀바
local titleBar = Instance.new("Frame")
titleBar.Size            = UDim2.new(1,0,0,30)
titleBar.BackgroundColor3 = Color3.fromRGB(30,30,30)
titleBar.BorderSizePixel = 0
titleBar.Parent          = window
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0,6)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size              = UDim2.new(1,-100,1,0)
titleLabel.Position          = UDim2.new(0,12,0,0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text              = "LuaOS Terminal"
titleLabel.TextColor3        = Color3.fromRGB(200,200,200)
titleLabel.Font              = Enum.Font.Code
titleLabel.TextSize          = 13
titleLabel.TextXAlignment    = Enum.TextXAlignment.Left
titleLabel.Parent            = titleBar

local function makeBtn(col, x)
	local b = Instance.new("TextButton")
	b.Size            = UDim2.new(0,13,0,13)
	b.Position        = UDim2.new(0,x,0.5,-6)
	b.BackgroundColor3 = col
	b.BorderSizePixel = 0
	b.Text            = ""
	b.Parent          = titleBar
	Instance.new("UICorner",b).CornerRadius = UDim.new(1,0)
	return b
end
local closeBtn = makeBtn(Color3.fromRGB(255,95,87),  10)
local minBtn   = makeBtn(Color3.fromRGB(255,189,46), 28)
local maxBtn   = makeBtn(Color3.fromRGB(39,201,63),  46)

-- 출력 영역
local outputFrame = Instance.new("ScrollingFrame")
outputFrame.Name              = "Output"
outputFrame.Size              = UDim2.new(1,-16,1,-80)
outputFrame.Position          = UDim2.new(0,8,0,36)
outputFrame.BackgroundTransparency = 1
outputFrame.BorderSizePixel   = 0
outputFrame.ScrollBarThickness = 4
outputFrame.ScrollBarImageColor3 = Color3.fromRGB(80,80,80)
outputFrame.CanvasSize        = UDim2.new(0,0,0,0)
outputFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
outputFrame.Parent            = window

local outputLayout = Instance.new("UIListLayout")
outputLayout.SortOrder = Enum.SortOrder.LayoutOrder
outputLayout.Padding   = UDim.new(0,0)
outputLayout.Parent    = outputFrame

-- 입력 바
local inputBar = Instance.new("Frame")
inputBar.Size            = UDim2.new(1,-16,0,34)
inputBar.Position        = UDim2.new(0,8,1,-42)
inputBar.BackgroundColor3 = Color3.fromRGB(20,20,20)
inputBar.BorderSizePixel = 0
inputBar.Parent          = window
Instance.new("UICorner", inputBar).CornerRadius = UDim.new(0,4)

local inputBox = Instance.new("TextBox")
inputBox.Size              = UDim2.new(1,-8,1,0)
inputBox.Position          = UDim2.new(0,8,0,0)
inputBox.BackgroundTransparency = 1
inputBox.Text              = ""
inputBox.TextColor3        = Color3.fromRGB(220,220,220)
inputBox.Font              = Enum.Font.Code
inputBox.TextSize          = 14
inputBox.TextXAlignment    = Enum.TextXAlignment.Left
inputBox.ClearTextOnFocus  = false
inputBox.Parent            = inputBar

----------------------------------------------------------------------
-- ANSI 색상 파서
----------------------------------------------------------------------
local ANSI_COLORS = {
	[0]  = Color3.fromRGB(220,220,220),  -- reset → default
	[30] = Color3.fromRGB(0,0,0),
	[31] = Color3.fromRGB(205,49,49),
	[32] = Color3.fromRGB(13,188,121),
	[33] = Color3.fromRGB(229,229,16),
	[34] = Color3.fromRGB(36,114,200),
	[35] = Color3.fromRGB(188,63,188),
	[36] = Color3.fromRGB(17,168,205),
	[37] = Color3.fromRGB(220,220,220),
	[90] = Color3.fromRGB(102,102,102),
	[91] = Color3.fromRGB(241,76,76),
	[92] = Color3.fromRGB(35,209,139),
	[93] = Color3.fromRGB(245,245,67),
	[94] = Color3.fromRGB(59,142,234),
	[95] = Color3.fromRGB(214,112,214),
	[96] = Color3.fromRGB(41,184,219),
	[97] = Color3.fromRGB(255,255,255),
}

-- 터미널 상태
local lineCount    = 0
local history      = {}
local historyIdx   = 0
local clearPending = false

local DEFAULT_COLOR = Color3.fromRGB(220,220,220)

-- ANSI 이스케이프 파싱 후 색상 세그먼트 분리
-- 반환: { {text, color, bold} }
local function parseANSI(raw)
	local segments = {}
	local curColor = DEFAULT_COLOR
	local curBold  = false
	local i        = 1

	while i <= #raw do
		local esc = raw:find("\27%[", i)
		if not esc then
			table.insert(segments, { text = raw:sub(i), color = curColor, bold = curBold })
			break
		end

		if esc > i then
			table.insert(segments, { text = raw:sub(i, esc-1), color = curColor, bold = curBold })
		end

		-- 시퀀스 파싱
		local seq_end = raw:find("[A-Za-z]", esc + 2)
		if not seq_end then break end

		local cmd = raw:sub(seq_end, seq_end)
		local params = raw:sub(esc + 2, seq_end - 1)

		if cmd == "m" then
			-- SGR (색상)
			if params == "" then params = "0" end
			for code in (params .. ";"):gmatch("(%d*);") do
				local n = tonumber(code) or 0
				if n == 0 then curColor = DEFAULT_COLOR; curBold = false
				elseif n == 1 then curBold = true
				elseif n == 7 then curColor = Color3.fromRGB(180,180,180)  -- reverse
				elseif ANSI_COLORS[n] then curColor = ANSI_COLORS[n]
				end
			end
		elseif cmd == "J" then
			-- 화면 지우기
			clearPending = true
		end
		-- 커서 이동(A/B/C/D/H)은 무시 (텍스트 출력 방식에서는 의미 없음)

		i = seq_end + 1
	end
	return segments
end

-- 줄 단위 라벨 출력
local function printLine(text, color, bold)
	lineCount += 1
	local label = Instance.new("TextLabel")
	label.Name              = "L" .. lineCount
	label.LayoutOrder       = lineCount
	label.Size              = UDim2.new(1,0,0,0)
	label.AutomaticSize     = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Text              = text
	label.TextColor3        = color or DEFAULT_COLOR
	label.Font              = bold and Enum.Font.CodeBold or Enum.Font.Code
	label.TextSize          = 13
	label.TextXAlignment    = Enum.TextXAlignment.Left
	label.TextWrapped       = true
	label.RichText          = false
	label.Parent            = outputFrame

	task.defer(function()
		outputFrame.CanvasPosition = Vector2.new(0, math.huge)
	end)
end

-- ANSI 포함 raw 텍스트를 터미널에 출력
local currentLine = ""
local currentColor = DEFAULT_COLOR
local currentBold  = false

local function flushLine()
	if currentLine ~= "" or true then
		printLine(currentLine, currentColor, currentBold)
		currentLine  = ""
		currentColor = DEFAULT_COLOR
		currentBold  = false
	end
end

local function renderRaw(raw)
	if clearPending then
		for _, child in ipairs(outputFrame:GetChildren()) do
			if child:IsA("TextLabel") then child:Destroy() end
		end
		lineCount    = 0
		clearPending = false
	end

	local segments = parseANSI(raw)
	for _, seg in ipairs(segments) do
		local text = seg.text
		-- 줄 분리
		local lines = {}
		for l in (text):gmatch("([^\n]*)\n?") do
			table.insert(lines, l)
		end
		-- 마지막 항목이 빈 문자열이면 제거 (줄 끝 \n 아티팩트)
		if lines[#lines] == "" and text:sub(-1) ~= "\n" then
			table.remove(lines)
		end

		for idx, l in ipairs(lines) do
			currentLine  ..= l
			currentColor  = seg.color
			currentBold   = seg.bold
			if idx < #lines or text:sub(-1) == "\n" then
				flushLine()
			end
		end
	end
end

----------------------------------------------------------------------
-- 입력 처리
----------------------------------------------------------------------
inputBox.FocusLost:Connect(function(enter)
	if enter then
		local cmd = inputBox.Text
		inputBox.Text = ""
		if cmd ~= "" then
			table.insert(history, cmd)
			historyIdx = #history + 1
		end
		Remote:FireServer(cmd)
		inputBox:CaptureFocus()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Up then
		historyIdx = math.max(1, historyIdx - 1)
		if history[historyIdx] then
			inputBox.Text = history[historyIdx]
			inputBox.CursorPosition = #inputBox.Text + 1
		end
	elseif input.KeyCode == Enum.KeyCode.Down then
		historyIdx = math.min(#history + 1, historyIdx + 1)
		inputBox.Text = history[historyIdx] or ""
	end
end)

-- 서버 출력 수신
Remote.OnClientEvent:Connect(function(data)
	if type(data) == "string" then
		renderRaw(data)
	elseif type(data) == "table" then
		for _, line in ipairs(data) do
			renderRaw(line .. "\n")
		end
	end
end)

-- 버튼
closeBtn.MouseButton1Click:Connect(function() window.Visible = false end)
minBtn.MouseButton1Click:Connect(function()
	outputFrame.Visible = not outputFrame.Visible
	inputBar.Visible    = outputFrame.Visible
	window.Size = outputFrame.Visible and UDim2.new(0,800,0,500) or UDim2.new(0,800,0,30)
end)
local maximized = false
maxBtn.MouseButton1Click:Connect(function()
	maximized = not maximized
	window.Size     = maximized and UDim2.new(1,0,1,0) or UDim2.new(0,800,0,500)
	window.Position = maximized and UDim2.new(0,0,0,0) or UDim2.new(0.5,-400,0.5,-250)
end)

inputBox:CaptureFocus()
