-- Script: ServerScriptService 에 배치
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FileSystem = require(script.Parent.FileSystem)
local StorageManager = require(script.Parent.StorageManager)

-- RemoteEvent 생성
local Remote = Instance.new("RemoteEvent")
Remote.Name = "TerminalRemote"
Remote.Parent = ReplicatedStorage

-- 유저별 현재 디렉토리
local cwdMap = {}  -- { [userId] = "/home/user" }

local function getCwd(userId)
	return cwdMap[userId] or "/home"
end

local function resolvePath(userId, path)
	if path:sub(1,1) == "/" then return path end
	local cwd = getCwd(userId)
	return cwd .. "/" .. path
end

----------------------------------------------------------------------
-- 명령어 핸들러
----------------------------------------------------------------------
local commands = {}

commands["help"] = function(userId, args)
	return {
		"[SYS] LuaOS 사용 가능한 명령어:",
		"  ls [경로]       — 파일 목록",
		"  cat <경로>      — 파일 내용 출력",
		"  write <경로>    — 파일 쓰기 (다음 줄에 내용 입력)",
		"  rm <경로>       — 파일 삭제",
		"  cd <경로>       — 디렉토리 이동",
		"  pwd             — 현재 경로 출력",
		"  mkdir <경로>    — 디렉토리 생성 (.keep 파일 생성)",
		"  clear           — 화면 지우기",
		"  whoami          — 현재 유저 정보",
		"  df              — 디스크 사용량",
	}
end

commands["pwd"] = function(userId, args)
	return { getCwd(userId) }
end

commands["cd"] = function(userId, args)
	local target = args[1]
	if not target then return { "[ERROR] 경로를 입력하세요" } end
	local path = resolvePath(userId, target)
	cwdMap[userId] = path
	return { "[OK] " .. path }
end

commands["ls"] = function(userId, args)
	local path = args[1] and resolvePath(userId, args[1]) or getCwd(userId)
	local files = FileSystem.list(userId, path)
	if not files or #files == 0 then
		return { "# (비어 있음)" }
	end
	local result = {}
	for _, name in ipairs(files) do
		table.insert(result, "  " .. name)
	end
	return result
end

commands["cat"] = function(userId, args)
	local path = args[1]
	if not path then return { "[ERROR] 경로를 입력하세요" } end
	local content, err = FileSystem.read(userId, resolvePath(userId, path))
	if not content then return { "[ERROR] " .. (err or "읽기 실패") } end
	local lines = {}
	for line in (content .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(lines, line)
	end
	return lines
end

commands["write"] = function(userId, args)
	-- write <경로> <내용...>
	local path = args[1]
	if not path then return { "[ERROR] 경로를 입력하세요" } end
	table.remove(args, 1)
	local content = table.concat(args, " ")
	local ok, err = FileSystem.write(userId, resolvePath(userId, path), content)
	if not ok then return { "[ERROR] " .. (err or "쓰기 실패") } end
	return { "[OK] 저장됨: " .. path }
end

commands["rm"] = function(userId, args)
	local path = args[1]
	if not path then return { "[ERROR] 경로를 입력하세요" } end
	local ok, err = FileSystem.delete(userId, resolvePath(userId, path))
	if not ok then return { "[ERROR] " .. (err or "삭제 실패") } end
	return { "[OK] 삭제됨: " .. path }
end

commands["mkdir"] = function(userId, args)
	local path = args[1]
	if not path then return { "[ERROR] 경로를 입력하세요" } end
	local fullPath = resolvePath(userId, path) .. "/.keep"
	local ok, err = FileSystem.write(userId, fullPath, "")
	if not ok then return { "[ERROR] " .. (err or "생성 실패") } end
	return { "[OK] 디렉토리 생성됨: " .. path }
end

commands["whoami"] = function(userId, args)
	local player = Players:GetPlayerByUserId(userId)
	return {
		"[SYS] 유저: " .. (player and player.Name or "unknown"),
		"[SYS] ID:   " .. userId,
		"[SYS] 경로: " .. getCwd(userId),
	}
end

commands["df"] = function(userId, args)
	local meta = StorageManager.getMeta(userId)
	if not meta then return { "[ERROR] 세션 없음" } end
	local used = 0
	for _ in pairs(meta.usedSectors) do used += 1 end
	local total = 256
	local pct = math.floor(used / total * 100)
	return {
		"[SYS] 디스크 사용량",
		string.format("  사용: %d / %d 섹터  (%d%%)", used, total, pct),
		string.format("  가용: %d MB  /  전체: 1024 MB", (total - used) * 4),
	}
end

commands["clear"] = function(userId, args)
	-- 클라이언트에서 특수 명령으로 처리
	return { "__CLEAR__" }
end

----------------------------------------------------------------------
-- 명령 파싱 및 라우팅
----------------------------------------------------------------------
local function handleCommand(player, raw)
	local userId = player.UserId
	local parts = {}
	for token in raw:gmatch("%S+") do
		table.insert(parts, token)
	end
	if #parts == 0 then return end

	local cmd = table.remove(parts, 1):lower()
	local handler = commands[cmd]

	local result
	if handler then
		local ok, res = pcall(handler, userId, parts)
		result = ok and res or { "[ERROR] 내부 오류: " .. tostring(res) }
	else
		result = { "[ERROR] 알 수 없는 명령: " .. cmd .. "  (help 참조)" }
	end

	Remote:FireClient(player, result)
end

Remote.OnServerEvent:Connect(function(player, raw)
	if type(raw) ~= "string" then return end
	if #raw > 512 then
		Remote:FireClient(player, { "[ERROR] 명령이 너무 깁니다" })
		return
	end
	handleCommand(player, raw)
end)

-- 접속 시 cwd 초기화
Players.PlayerAdded:Connect(function(player)
	cwdMap[player.UserId] = "/home"
end)

Players.PlayerRemoving:Connect(function(player)
	cwdMap[player.UserId] = nil
end)
