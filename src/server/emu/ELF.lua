-- ELF64 파서 (RISC-V 64용)
local ELF = {}

local function readU8(data, i)   return data:byte(i) end
local function readU16(data, i)  return data:byte(i) + data:byte(i+1)*256 end
local function readU32(data, i)
	return data:byte(i) + data:byte(i+1)*0x100
	     + data:byte(i+2)*0x10000 + data:byte(i+3)*0x1000000
end
local function readU64(data, i)
	local lo = readU32(data, i)
	local hi = readU32(data, i+4)
	return lo + hi * 0x100000000
end

-- ELF 매직 확인 및 파싱
function ELF.parse(data)
	-- 매직 넘버 확인
	if data:sub(1,4) ~= "\x7fELF" then
		return nil, "not an ELF file"
	end

	local class = readU8(data, 5)
	if class ~= 2 then return nil, "not ELF64 (class=" .. class .. ")" end

	local endian = readU8(data, 6)
	if endian ~= 1 then return nil, "not little-endian" end

	local machine = readU16(data, 19)
	if machine ~= 243 then return nil, "not RISC-V (machine=" .. machine .. ")" end

	local elf = {}
	elf.type      = readU16(data, 17)  -- 2=EXEC, 3=DYN
	elf.entry     = readU64(data, 25)  -- 진입점
	elf.phoff     = readU64(data, 33)  -- 프로그램 헤더 오프셋
	elf.shoff     = readU64(data, 41)  -- 섹션 헤더 오프셋
	elf.phentsize = readU16(data, 55)  -- 프로그램 헤더 엔트리 크기
	elf.phnum     = readU16(data, 57)  -- 프로그램 헤더 개수
	elf.shentsize = readU16(data, 59)
	elf.shnum     = readU16(data, 61)
	elf.shstrndx  = readU16(data, 63)

	-- 프로그램 헤더 파싱
	elf.phdrs = {}
	for i = 0, elf.phnum - 1 do
		local base = elf.phoff + i * elf.phentsize + 1
		local ph = {
			type   = readU32(data, base),
			flags  = readU32(data, base+4),
			offset = readU64(data, base+8),
			vaddr  = readU64(data, base+16),
			paddr  = readU64(data, base+24),
			filesz = readU64(data, base+32),
			memsz  = readU64(data, base+40),
			align  = readU64(data, base+48),
		}
		table.insert(elf.phdrs, ph)
	end

	return elf
end

-- ELF를 메모리에 로드
-- 반환: { entry, heapStart, stackTop }
function ELF.load(elf, data, mem)
	local PT_LOAD = 1
	local heapStart = 0

	for _, ph in ipairs(elf.phdrs) do
		if ph.type == PT_LOAD and ph.memsz > 0 then
			-- 파일에서 데이터 복사
			local fileData = data:sub(ph.offset + 1, ph.offset + ph.filesz)
			for i = 1, #fileData do
				mem:write8(ph.vaddr + i - 1, fileData:byte(i))
			end
			-- BSS (memsz > filesz 부분) 0으로 초기화
			for i = ph.filesz, ph.memsz - 1 do
				mem:write8(ph.vaddr + i, 0)
			end
			mem:addRegion(ph.vaddr, ph.memsz, ph.flags, "LOAD")

			local end_ = ph.vaddr + ph.memsz
			if end_ > heapStart then heapStart = end_ end
		end
	end

	-- 힙 시작 주소 4KB 정렬
	heapStart = math.ceil(heapStart / 4096) * 4096

	-- 스택: 0x7FFF0000 ~ 0x80000000
	local STACK_TOP  = 0x7FFFFFFFE000
	local STACK_SIZE = 8 * 1024 * 1024  -- 8MB

	-- 스택 메모리 예약
	mem:addRegion(STACK_TOP - STACK_SIZE, STACK_SIZE, 6, "STACK")

	return {
		entry      = elf.entry,
		heapStart  = heapStart,
		stackTop   = STACK_TOP,
	}
end

-- base64 디코드 (ELF 바이너리는 base64로 VFS에 저장)
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64dec = {}
for i = 1, #b64chars do b64dec[b64chars:sub(i,i)] = i - 1 end

function ELF.decodeBase64(s)
	s = s:gsub("[^A-Za-z0-9+/=]", "")
	local out = ""
	for i = 1, #s, 4 do
		local a = b64dec[s:sub(i,i)]   or 0
		local b = b64dec[s:sub(i+1,i+1)] or 0
		local c = b64dec[s:sub(i+2,i+2)] or 0
		local d = b64dec[s:sub(i+3,i+3)] or 0
		local n = a*0x40000 + b*0x1000 + c*0x40 + d
		out ..= string.char(
			math.floor(n / 0x10000),
			math.floor(n / 0x100) % 256,
			n % 256
		)
	end
	-- padding 제거
	local pad = s:match("=+$")
	if pad then out = out:sub(1, -(#pad+1)) end
	return out
end

return ELF
