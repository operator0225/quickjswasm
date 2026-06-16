-- RISC-V Hello World ELF 실행 테스트
-- 손으로 만든 최소 ELF64 바이너리를 에뮬레이터로 실행

local Emulator = require("./Emulator")
local ELF      = require("./ELF")

-- ============================================================
-- 최소 RISC-V ELF64 바이너리 생성
-- "Hello, World!\n" 을 write(1,...) 후 exit(0)
-- ============================================================

-- 리틀 엔디언 바이트 인코더
local function u8(v)  return string.char(v % 256) end
local function u16(v) return string.char(v%256, math.floor(v/256)%256) end
local function u32(v)
	local b0 = v % 256;             v = math.floor(v / 256)
	local b1 = v % 256;             v = math.floor(v / 256)
	local b2 = v % 256;             v = math.floor(v / 256)
	local b3 = v % 256
	return string.char(b0, b1, b2, b3)
end
local function u64(lo, hi)
	hi = hi or 0
	return u32(lo) .. u32(hi)
end

-- RISC-V 명령어 인코더 (32비트)
local function instr(v) return u32(v) end

-- ============================================================
-- 레이아웃
-- ELF header:     64 bytes  (offset 0x00)
-- Program header: 56 bytes  (offset 0x40)
-- Code:            9 instrs  (offset 0x78 → vaddr 0x10078)
-- String:         15 bytes   (offset 0x9C → vaddr 0x1009C)
-- ============================================================

local LOAD_VADDR = 0x10000   -- 세그먼트 로드 주소
local CODE_OFF   = 0x78      -- 파일 내 코드 오프셋
local CODE_VADDR = LOAD_VADDR + CODE_OFF   -- 0x10078

local STR        = "Hello, World!\n"
local STR_OFF    = CODE_OFF + 9 * 4         -- 0x78 + 36 = 0x9C
local STR_VADDR  = LOAD_VADDR + STR_OFF     -- 0x1009C

local FILE_SIZE  = STR_OFF + #STR           -- 0x9C + 14 = 0xAA

local function shl(v, n) return bit32.lshift(v, n) end
local function bor(...) return bit32.bor(...) end

-- lui x11, 0x10  → x11 = 0x10000
-- lui: imm[31:12]=upper20, rd=11, opcode=0x37
local LUI_A1_10  = bor(shl(0x10, 12), shl(11, 7), 0x37)  -- 0x000105B7

-- addi x11, x11, STR_OFF  → x11 = STR_VADDR
local ADJ = STR_OFF  -- 0x9C
local ADDI_A1    = bor(shl(ADJ, 20), shl(11, 15), shl(11, 7), 0x13)

-- addi x10, x0, 1   (fd=stdout)
local ADDI_A0_1  = bor(shl(1, 20), shl(10, 7), 0x13)

-- addi x12, x0, 14  (len)
local ADDI_A2_14 = bor(shl(14, 20), shl(12, 7), 0x13)

-- addi x17, x0, 64  (syscall: write)
local ADDI_A7_64 = bor(shl(64, 20), shl(17, 7), 0x13)

-- ecall
local ECALL      = 0x00000073

-- addi x10, x0, 0   (exit code 0)
local ADDI_A0_0  = bor(shl(10, 7), 0x13)

-- addi x17, x0, 93  (syscall: exit)
local ADDI_A7_93 = bor(shl(93, 20), shl(17, 7), 0x13)

-- ============================================================
-- ELF 헤더 (64 bytes)
-- ============================================================
local elfHeader = table.concat({
	"\x7fELF",    -- magic
	u8(2),         -- EI_CLASS   = ELFCLASS64
	u8(1),         -- EI_DATA    = ELFDATA2LSB
	u8(1),         -- EI_VERSION = 1
	u8(0),         -- EI_OSABI   = ELFOSABI_NONE
	string.rep("\0", 8),  -- padding

	u16(2),        -- e_type    = ET_EXEC
	u16(243),      -- e_machine = EM_RISCV
	u32(1),        -- e_version = 1
	u64(CODE_VADDR), -- e_entry
	u64(0x40),     -- e_phoff (program header at offset 64)
	u64(0),        -- e_shoff (no section headers)
	u32(0),        -- e_flags
	u16(64),       -- e_ehsize
	u16(56),       -- e_phentsize
	u16(1),        -- e_phnum
	u16(64),       -- e_shentsize
	u16(0),        -- e_shnum
	u16(0),        -- e_shstrndx
})

-- ============================================================
-- 프로그램 헤더 (56 bytes, PT_LOAD)
-- ============================================================
local progHeader = table.concat({
	u32(1),          -- p_type  = PT_LOAD
	u32(5),          -- p_flags = PF_R | PF_X
	u64(0),          -- p_offset (file offset 0)
	u64(LOAD_VADDR), -- p_vaddr
	u64(LOAD_VADDR), -- p_paddr
	u64(FILE_SIZE),  -- p_filesz
	u64(FILE_SIZE),  -- p_memsz
	u64(0x1000),     -- p_align
})

-- ============================================================
-- 코드 섹션
-- ============================================================
local code = table.concat({
	instr(ADDI_A0_1),   -- addi x10, x0, 1       (fd=1)
	instr(LUI_A1_10),   -- lui  x11, 0x10         (x11=0x10000)
	instr(ADDI_A1),     -- addi x11, x11, STR_OFF (x11=str addr)
	instr(ADDI_A2_14),  -- addi x12, x0, 14       (len)
	instr(ADDI_A7_64),  -- addi x17, x0, 64       (write)
	instr(ECALL),       -- ecall
	instr(ADDI_A0_0),   -- addi x10, x0, 0        (exit code)
	instr(ADDI_A7_93),  -- addi x17, x0, 93       (exit)
	instr(ECALL),       -- ecall
})

-- ============================================================
-- 전체 바이너리
-- ============================================================
-- 헤더와 코드 사이 패딩 (0x78 - 64 - 56 = 0)
assert(#elfHeader == 64, "ELF header size: " .. #elfHeader)
assert(#progHeader == 56, "Program header size: " .. #progHeader)
assert(CODE_OFF == #elfHeader + #progHeader, "CODE_OFF mismatch")

local elfBinary = elfHeader .. progHeader .. code .. STR

print(string.format("ELF binary size: %d bytes", #elfBinary))
print(string.format("Entry: 0x%X, String at: 0x%X", CODE_VADDR, STR_VADDR))

-- ============================================================
-- base64 인코딩
-- ============================================================
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64Encode(data)
	local result = {}
	local i = 1
	while i <= #data do
		local b0 = data:byte(i)     or 0
		local b1 = data:byte(i + 1) or 0
		local b2 = data:byte(i + 2) or 0

		local n = b0 * 65536 + b1 * 256 + b2

		local c0 = math.floor(n / 262144) % 64 + 1
		local c1 = math.floor(n / 4096)   % 64 + 1
		local c2 = math.floor(n / 64)     % 64 + 1
		local c3 = n % 64 + 1

		result[#result + 1] = b64chars:sub(c0, c0)
		result[#result + 1] = b64chars:sub(c1, c1)

		if i + 1 <= #data then
			result[#result + 1] = b64chars:sub(c2, c2)
		else
			result[#result + 1] = "="
		end
		if i + 2 <= #data then
			result[#result + 1] = b64chars:sub(c3, c3)
		else
			result[#result + 1] = "="
		end

		i += 3
	end
	return table.concat(result)
end

local elfB64 = base64Encode(elfBinary)
print(string.format("base64 length: %d", #elfB64))

-- ============================================================
-- 에뮬레이터 실행
-- ============================================================
print("\n--- 에뮬레이터 실행 ---")

local output = ""
local kernelSys = {
	write = function(fd, data)
		if fd == 1 or fd == 2 then
			output ..= data
		end
		return #data
	end,
	read    = function(fd, n) return "" end,
	open    = function(path, flags) return nil end,
	close   = function(fd) end,
	stat    = function(path) return nil end,
	readdir = function(path) return {} end,
	mkdir   = function(path) return true end,
	unlink  = function(path) return true end,
	rename  = function(a, b) return true end,
	chdir   = function(path) return true end,
	sleep   = function(t) end,
	getpid  = function() return 1 end,
	exit    = function(code)
		-- exit syscall은 Syscall.lua에서 cpu.running=false로 처리
	end,
}

local kernelProc = {
	uid  = 1000,
	gid  = 1000,
	cwd  = "/",
	env  = { PATH = "/usr/bin:/bin", HOME = "/home/user" },
}

local exitCode = Emulator.exec(kernelProc, kernelSys, elfB64, { "hello" })

print(string.format("\n--- 종료 코드: %d ---", exitCode))

if output == "Hello, World!\n" then
	print("✓ PASS: 출력 일치")
else
	print("✗ FAIL: 출력 불일치 → " .. string.format("%q", output))
	os.exit(1)
end
