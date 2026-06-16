local DataStoreService = game:GetService("DataStoreService")
local Constants = require(script.Parent.Parent.shared.Constants)

local StorageManager = {}

-- 유저별 메모리 세션 { [userId] = { meta, sectors, dirtySet } }
local sessions = {}

local function getMetaKey(userId)
	return Constants.META_KEY_PREFIX .. userId
end

local function getSectorKey(userId, index)
	return Constants.SECTOR_KEY_PREFIX .. userId .. "_" .. index
end

local function getStore()
	return DataStoreService:GetDataStore(Constants.DATASTORE_NAME)
end

-- 접속 시 전체 로드 → 메모리에 올림
function StorageManager.loadUser(userId)
	if sessions[userId] then return end

	local store = getStore()
	local ok, meta = pcall(function()
		return store:GetAsync(getMetaKey(userId))
	end)

	if not ok or meta == nil then
		-- 최초 접속: 빈 메타 생성
		meta = {
			usedSectors = {},   -- { [index] = true } 사용 중인 섹터
			fileTable = {},     -- 파일시스템 테이블 (경로 → 섹터인덱스)
			totalUsed = 0,      -- 사용 바이트 수
		}
	end

	-- 사용 중인 섹터 전부 로드
	local sectors = {}
	for index, _ in pairs(meta.usedSectors) do
		local sok, data = pcall(function()
			return store:GetAsync(getSectorKey(userId, index))
		end)
		sectors[index] = (sok and data) or {}
	end

	sessions[userId] = {
		meta = meta,
		sectors = sectors,
		dirtySet = {},   -- 변경된 섹터 인덱스 목록
		metaDirty = false,
	}

	print("[StorageManager] 유저 로드 완료:", userId)
end

-- 메모리에서 섹터 읽기
function StorageManager.readSector(userId, index)
	local session = sessions[userId]
	if not session then return nil end
	return session.sectors[index]
end

-- 메모리에서 섹터 쓰기 (dirty 표시)
function StorageManager.writeSector(userId, index, data)
	local session = sessions[userId]
	if not session then return false end
	session.sectors[index] = data
	session.meta.usedSectors[index] = true
	session.dirtySet[index] = true
	session.metaDirty = true
	return true
end

-- 섹터 해제 (파일 삭제)
function StorageManager.freeSector(userId, index)
	local session = sessions[userId]
	if not session then return end
	session.sectors[index] = nil
	session.meta.usedSectors[index] = nil
	session.dirtySet[index] = true
	session.metaDirty = true
end

-- 빈 섹터 인덱스 찾기
function StorageManager.allocSector(userId)
	local session = sessions[userId]
	if not session then return nil end
	for i = 0, Constants.TOTAL_SECTORS - 1 do
		if not session.meta.usedSectors[i] then
			return i
		end
	end
	return nil  -- 디스크 꽉 참
end

-- 파일 테이블 접근
function StorageManager.getMeta(userId)
	local session = sessions[userId]
	return session and session.meta or nil
end

function StorageManager.setMetaDirty(userId)
	local session = sessions[userId]
	if session then session.metaDirty = true end
end

-- 변경된 섹터만 DataStore에 저장
function StorageManager.saveUser(userId)
	local session = sessions[userId]
	if not session then return end

	local store = getStore()

	-- dirty 섹터 저장
	for index, _ in pairs(session.dirtySet) do
		if session.sectors[index] then
			pcall(function()
				store:SetAsync(getSectorKey(userId, index), session.sectors[index])
			end)
		else
			-- 해제된 섹터는 삭제
			pcall(function()
				store:RemoveAsync(getSectorKey(userId, index))
			end)
		end
	end
	session.dirtySet = {}

	-- 메타데이터 저장
	if session.metaDirty then
		pcall(function()
			store:SetAsync(getMetaKey(userId), session.meta)
		end)
		session.metaDirty = false
	end

	print("[StorageManager] 유저 저장 완료:", userId)
end

-- 세션 언로드
function StorageManager.unloadUser(userId)
	StorageManager.saveUser(userId)
	sessions[userId] = nil
end

return StorageManager
