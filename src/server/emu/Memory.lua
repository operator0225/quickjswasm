-- RISC-V 64 가상 메모리
-- 페이지 크기 4KB, Luau table로 페이지 관리
local Memory = {}
Memory.__index = Memory

local PAGE_SIZE  = 4096
local PAGE_SHIFT = 12

local function newPage()
	return { bytes = {} }
end

function Memory.new()
	local m = setmetatable({}, Memory)
	m.pages   = {}   -- { [pageAddr] = page }
	m.regions = {}   -- { {start, size, perm, name} } 디버그용
	return m
end

-- 페이지 가져오기 (없으면 생성)
function Memory:getPage(addr)
	local pageAddr = math.floor(addr / PAGE_SIZE) * PAGE_SIZE
	if not self.pages[pageAddr] then
		self.pages[pageAddr] = newPage()
	end
	return self.pages[pageAddr], addr - pageAddr
end

----------------------------------------------------------------------
-- 바이트 단위 읽기/쓰기
----------------------------------------------------------------------
function Memory:read8(addr)
	local page, off = self:getPage(addr)
	return page.bytes[off] or 0
end

function Memory:write8(addr, val)
	local page, off = self:getPage(addr)
	page.bytes[off] = val % 256
end

-- 16비트 리틀엔디안
function Memory:read16(addr)
	return self:read8(addr) + self:read8(addr+1) * 256
end

function Memory:write16(addr, val)
	val = val % 65536
	self:write8(addr,   val % 256)
	self:write8(addr+1, math.floor(val / 256) % 256)
end

-- 32비트 리틀엔디안
function Memory:read32(addr)
	local b0 = self:read8(addr)
	local b1 = self:read8(addr+1)
	local b2 = self:read8(addr+2)
	local b3 = self:read8(addr+3)
	return b0 + b1*0x100 + b2*0x10000 + b3*0x1000000
end

function Memory:write32(addr, val)
	-- 부호 없는 32비트로 정규화
	val = val % 0x100000000
	self:write8(addr,   val % 256)
	self:write8(addr+1, math.floor(val / 0x100)    % 256)
	self:write8(addr+2, math.floor(val / 0x10000)  % 256)
	self:write8(addr+3, math.floor(val / 0x1000000)% 256)
end

-- 64비트 리틀엔디안 (Luau는 53비트 정수 정밀도 한계 있음 → 상위/하위 32비트 분리)
function Memory:read64(addr)
	local lo = self:read32(addr)
	local hi = self:read32(addr + 4)
	return lo + hi * 0x100000000
end

function Memory:write64(addr, val)
	-- val을 상위/하위 32비트로 분리
	local lo = val % 0x100000000
	local hi = math.floor(val / 0x100000000) % 0x100000000
	self:write32(addr,     lo)
	self:write32(addr + 4, hi)
end

-- 바이트 배열 블록 쓰기 (ELF 로딩용)
function Memory:writeBytes(addr, bytes)
	for i, b in ipairs(bytes) do
		self:write8(addr + i - 1, b)
	end
end

-- 문자열 쓰기 (null 포함)
function Memory:writeString(addr, s)
	for i = 1, #s do
		self:write8(addr + i - 1, s:byte(i))
	end
	self:write8(addr + #s, 0)
end

-- 문자열 읽기 (null 종료)
function Memory:readString(addr)
	local s = ""
	local i = 0
	while true do
		local b = self:read8(addr + i)
		if b == 0 then break end
		s ..= string.char(b)
		i += 1
		if i > 4096 then break end  -- 안전장치
	end
	return s
end

-- 영역 등록 (디버그)
function Memory:addRegion(start, size, perm, name)
	table.insert(self.regions, { start=start, size=size, perm=perm, name=name })
end

return Memory
