local StorageManager = require(script.Parent.StorageManager)

local FileSystem = {}

-- 경로 정규화
local function normPath(path)
	if path:sub(1,1) ~= "/" then path = "/" .. path end
	return path:gsub("//+", "/"):gsub("/$", "")
end

-- 파일 쓰기
function FileSystem.write(userId, path, content)
	path = normPath(path)
	local meta = StorageManager.getMeta(userId)
	if not meta then return false, "세션 없음" end

	-- 기존 섹터 있으면 재사용, 없으면 새로 할당
	local sectorIndex = meta.fileTable[path]
	if not sectorIndex then
		sectorIndex = StorageManager.allocSector(userId)
		if not sectorIndex then return false, "디스크 꽉 참" end
		meta.fileTable[path] = sectorIndex
	end

	StorageManager.writeSector(userId, sectorIndex, { content = content })
	StorageManager.setMetaDirty(userId)
	return true
end

-- 파일 읽기
function FileSystem.read(userId, path)
	path = normPath(path)
	local meta = StorageManager.getMeta(userId)
	if not meta then return nil, "세션 없음" end

	local sectorIndex = meta.fileTable[path]
	if not sectorIndex then return nil, "파일 없음" end

	local sector = StorageManager.readSector(userId, sectorIndex)
	if not sector then return nil, "섹터 읽기 실패" end
	return sector.content
end

-- 파일 삭제
function FileSystem.delete(userId, path)
	path = normPath(path)
	local meta = StorageManager.getMeta(userId)
	if not meta then return false, "세션 없음" end

	local sectorIndex = meta.fileTable[path]
	if not sectorIndex then return false, "파일 없음" end

	StorageManager.freeSector(userId, sectorIndex)
	meta.fileTable[path] = nil
	StorageManager.setMetaDirty(userId)
	return true
end

-- 파일 목록 (디렉토리)
function FileSystem.list(userId, dir)
	dir = normPath(dir)
	local meta = StorageManager.getMeta(userId)
	if not meta then return nil end

	local results = {}
	for path, _ in pairs(meta.fileTable) do
		if path:sub(1, #dir) == dir then
			local rest = path:sub(#dir + 2)  -- dir/ 이후 부분
			if rest ~= "" and not rest:find("/") then
				table.insert(results, rest)
			end
		end
	end
	return results
end

-- 파일 존재 여부
function FileSystem.exists(userId, path)
	path = normPath(path)
	local meta = StorageManager.getMeta(userId)
	return meta and meta.fileTable[path] ~= nil
end

return FileSystem
