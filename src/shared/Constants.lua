-- OS 전역 상수
local Constants = {
	SECTOR_SIZE = 4 * 1024 * 1024,   -- 4MB per sector (DataStore 키 하나)
	TOTAL_SECTORS = 256,              -- 유저당 최대 256섹터 = 1GB
	AUTOSAVE_INTERVAL = 300,          -- 5분마다 자동저장
	DATASTORE_NAME = "LUAOS_v1",
	META_KEY_PREFIX = "meta_",        -- 메타데이터 키
	SECTOR_KEY_PREFIX = "sector_",    -- 섹터 키
}

return Constants
