-- LocalScript: StarterGui 또는 StarterPlayerScripts 에 배치
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- RemoteEvent (서버 ↔ 클라이언트 명령 통신)
local Remote = game:GetService("ReplicatedStorage"):WaitForChild("TerminalRemote")

----------------------------------------------------------------------
-- GUI 생성
----------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LuaOS_Terminal"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- 메인 윈도우 프레임
local window = Instance.new("Frame")
window.Name = "Window"
window.Size = UDim2.new(0, 780, 0, 480)
window.Position = UDim2.new(0.5, -390, 0.5, -240)
window.BackgroundColor3 = Color3.fromRGB(13, 13, 13)
window.BorderSizePixel = 0
window.Active = true
window.Draggable = true
window.Parent = screenGui

-- 모서리 둥글게
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = window

-- 타이틀바
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
titleBar.BorderSizePixel = 0
titleBar.Parent = window

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 6)
titleCorner.Parent = titleBar

-- 타이틀 텍스트
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -100, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "LuaOS Terminal"
titleLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
titleLabel.Font = Enum.Font.Code
titleLabel.TextSize = 13
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

-- 닫기/최소화 버튼 (macOS 스타일)
local function makeBtn(color, posX)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 13, 0, 13)
	btn.Position = UDim2.new(0, posX, 0.5, -6)
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.Parent = titleBar
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = btn
	return btn
end

local closeBtn  = makeBtn(Color3.fromRGB(255, 95, 87),  10)
local minBtn    = makeBtn(Color3.fromRGB(255, 189, 46), 28)
local maxBtn    = makeBtn(Color3.fromRGB(39, 201, 63),  46)

-- 출력 스크롤 영역
local outputFrame = Instance.new("ScrollingFrame")
outputFrame.Name = "Output"
outputFrame.Size = UDim2.new(1, -16, 1, -80)
outputFrame.Position = UDim2.new(0, 8, 0, 36)
outputFrame.BackgroundTransparency = 1
outputFrame.BorderSizePixel = 0
outputFrame.ScrollBarThickness = 4
outputFrame.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
outputFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
outputFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
outputFrame.Parent = window

local outputLayout = Instance.new("UIListLayout")
outputLayout.SortOrder = Enum.SortOrder.LayoutOrder
outputLayout.Padding = UDim.new(0, 1)
outputLayout.Parent = outputFrame

-- 입력 바
local inputBar = Instance.new("Frame")
inputBar.Size = UDim2.new(1, -16, 0, 32)
inputBar.Position = UDim2.new(0, 8, 1, -40)
inputBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
inputBar.BorderSizePixel = 0
inputBar.Parent = window

local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 4)
inputCorner.Parent = inputBar

-- 프롬프트 라벨
local promptLabel = Instance.new("TextLabel")
promptLabel.Size = UDim2.new(0, 0, 1, 0)
promptLabel.AutomaticSize = Enum.AutomaticSize.X
promptLabel.Position = UDim2.new(0, 8, 0, 0)
promptLabel.BackgroundTransparency = 1
promptLabel.Text = "root@luaos:~$ "
promptLabel.TextColor3 = Color3.fromRGB(80, 200, 120)
promptLabel.Font = Enum.Font.Code
promptLabel.TextSize = 14
promptLabel.TextXAlignment = Enum.TextXAlignment.Left
promptLabel.Parent = inputBar

-- 실제 입력 박스
local inputBox = Instance.new("TextBox")
inputBox.Name = "InputBox"
inputBox.Size = UDim2.new(1, -110, 1, 0)
inputBox.Position = UDim2.new(0, 102, 0, 0)
inputBox.BackgroundTransparency = 1
inputBox.Text = ""
inputBox.PlaceholderText = ""
inputBox.TextColor3 = Color3.fromRGB(220, 220, 220)
inputBox.Font = Enum.Font.Code
inputBox.TextSize = 14
inputBox.TextXAlignment = Enum.TextXAlignment.Left
inputBox.ClearTextOnFocus = false
inputBox.Parent = inputBar

----------------------------------------------------------------------
-- 터미널 로직
----------------------------------------------------------------------
local history = {}
local historyIndex = 0
local lineCount = 0

local COLORS = {
	default = Color3.fromRGB(220, 220, 220),
	green   = Color3.fromRGB(80, 200, 120),
	red     = Color3.fromRGB(255, 100, 100),
	yellow  = Color3.fromRGB(255, 220, 80),
	cyan    = Color3.fromRGB(80, 210, 230),
	gray    = Color3.fromRGB(130, 130, 130),
}

local function printLine(text, color)
	color = color or COLORS.default
	lineCount += 1

	local label = Instance.new("TextLabel")
	label.Name = "Line_" .. lineCount
	label.Size = UDim2.new(1, 0, 0, 18)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.RichText = false
	label.LayoutOrder = lineCount
	label.Parent = outputFrame

	-- 항상 맨 아래로 스크롤
	task.defer(function()
		outputFrame.CanvasPosition = Vector2.new(0, math.huge)
	end)
end

local function printPrompt(cmd)
	printLine("root@luaos:~$ " .. cmd, COLORS.green)
end

local function submitCommand(cmd)
	cmd = cmd:match("^%s*(.-)%s*$")  -- trim
	if cmd == "" then return end

	printPrompt(cmd)

	-- 히스토리 저장
	table.insert(history, cmd)
	historyIndex = #history + 1

	-- 서버로 명령 전송
	Remote:FireServer(cmd)
end

-- Enter 키
inputBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		local cmd = inputBox.Text
		inputBox.Text = ""
		submitCommand(cmd)
		inputBox:CaptureFocus()
	end
end)

-- 히스토리 탐색 (위/아래 화살표)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Up then
		historyIndex = math.max(1, historyIndex - 1)
		if history[historyIndex] then
			inputBox.Text = history[historyIndex]
			-- 커서 끝으로
			inputBox.CursorPosition = #inputBox.Text + 1
		end
	elseif input.KeyCode == Enum.KeyCode.Down then
		historyIndex = math.min(#history + 1, historyIndex + 1)
		inputBox.Text = history[historyIndex] or ""
	end
end)

-- 서버 응답 수신
Remote.OnClientEvent:Connect(function(lines)
	if type(lines) == "string" then lines = { lines } end
	for _, line in ipairs(lines) do
		local color = COLORS.default
		-- 간단한 색상 힌트 파싱: "[ERROR]", "[OK]", "[WARN]"
		if line:sub(1,7) == "[ERROR]" then
			color = COLORS.red
		elseif line:sub(1,4) == "[OK]" then
			color = COLORS.green
		elseif line:sub(1,6) == "[WARN]" then
			color = COLORS.yellow
		elseif line:sub(1,5) == "[SYS]" then
			color = COLORS.cyan
		elseif line:sub(1,1) == "#" then
			color = COLORS.gray
		end
		printLine(line, color)
	end
end)

-- 닫기 버튼
closeBtn.MouseButton1Click:Connect(function()
	window.Visible = false
end)

-- 최소화 (토글)
minBtn.MouseButton1Click:Connect(function()
	outputFrame.Visible = not outputFrame.Visible
	inputBar.Visible = not inputBar.Visible
	window.Size = outputFrame.Visible
		and UDim2.new(0, 780, 0, 480)
		or  UDim2.new(0, 780, 0, 30)
end)

-- 최대화 토글
local maximized = false
maxBtn.MouseButton1Click:Connect(function()
	maximized = not maximized
	window.Size = maximized
		and UDim2.new(1, 0, 1, 0)
		or  UDim2.new(0, 780, 0, 480)
	window.Position = maximized
		and UDim2.new(0, 0, 0, 0)
		or  UDim2.new(0.5, -390, 0.5, -240)
end)

-- 부팅 메시지
printLine("LuaOS v0.1  —  built on Roblox", COLORS.cyan)
printLine("Type 'help' for available commands.", COLORS.gray)
printLine("", COLORS.default)

inputBox:CaptureFocus()
