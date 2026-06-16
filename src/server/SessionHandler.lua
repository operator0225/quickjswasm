local Players = game:GetService("Players")
local StorageManager = require(script.Parent.StorageManager)
local Constants = require(script.Parent.Parent.shared.Constants)

-- 접속 시 로드
Players.PlayerAdded:Connect(function(player)
	StorageManager.loadUser(player.UserId)
end)

-- 나갈 때 저장 후 언로드
Players.PlayerRemoving:Connect(function(player)
	StorageManager.unloadUser(player.UserId)
end)

-- 서버 종료 시 전원 저장
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		StorageManager.unloadUser(player.UserId)
	end
end)

-- 5분마다 자동저장 (크래시 대비)
task.spawn(function()
	while true do
		task.wait(Constants.AUTOSAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			StorageManager.saveUser(player.UserId)
		end
		print("[AutoSave] 자동저장 완료")
	end
end)
