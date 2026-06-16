-- Script: ServerScriptService 에 배치
-- 커널을 부팅하고 플레이어마다 셸 프로세스를 생성
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kernel = require(script.Parent.kernel.Kernel)
local SessionHandler = require(script.Parent.SessionHandler)  -- 스토리지 로드/저장

-- RemoteEvent 생성 (클라이언트 ↔ 서버 터미널 통신)
local Remote = Instance.new("RemoteEvent")
Remote.Name  = "TerminalRemote"
Remote.Parent = ReplicatedStorage

-- pid ↔ player 매핑
local playerShells = {}  -- { [userId] = pid }

-- 커널 부팅
Kernel.boot()

-- 플레이어 접속 시 셸 생성
Players.PlayerAdded:Connect(function(player)
	-- 스토리지 로드 (SessionHandler가 처리)
	task.wait(1)  -- 스토리지 로드 대기

	local pid = Kernel.spawnShell(player.UserId, function(output)
		-- 셸 출력 → 클라이언트로 전송
		if output and #output > 0 then
			Remote:FireClient(player, output)
		end
	end)

	if pid then
		playerShells[player.UserId] = pid
	end
end)

-- 클라이언트 입력 → 셸 stdin
Remote.OnServerEvent:Connect(function(player, input)
	if type(input) ~= "string" then return end
	if #input > 4096 then return end  -- 입력 길이 제한

	local pid = playerShells[player.UserId]
	if pid then
		Kernel.sendInput(pid, input)
	end
end)

-- 퇴장 시 정리
Players.PlayerRemoving:Connect(function(player)
	local pid = playerShells[player.UserId]
	if pid then
		Kernel.cleanup(pid)
		playerShells[player.UserId] = nil
	end
end)
