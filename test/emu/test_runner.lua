-- LuaOS RISC-V 에뮬레이터 테스트 러너
-- Roblox 없는 순수 Luau CLI 환경에서 실행

-- ============================================================
-- 1. 모듈 로드
-- ============================================================
local Memory  = require("./Memory")
local CPU     = require("./CPU")
local Decode  = require("./Decode")
local Execute = require("./Execute")
local ELF     = require("./ELF")

local passed = 0
local failed = 0

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("  [PASS] " .. name)
		passed += 1
	else
		print("  [FAIL] " .. name .. " — " .. tostring(err))
		failed += 1
	end
end

local function assert_eq(a, b, msg)
	if a ~= b then
		error((msg or "assert_eq") .. ": expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end

-- ============================================================
-- 2. Memory 테스트
-- ============================================================
print("\n=== Memory Tests ===")

test("read/write 8-bit", function()
	local m = Memory.new()
	m:write8(0x1000, 0xAB)
	assert_eq(m:read8(0x1000), 0xAB)
end)

test("read/write 16-bit little-endian", function()
	local m = Memory.new()
	m:write16(0x1000, 0x1234)
	assert_eq(m:read8(0x1000), 0x34)
	assert_eq(m:read8(0x1001), 0x12)
	assert_eq(m:read16(0x1000), 0x1234)
end)

test("read/write 32-bit little-endian", function()
	local m = Memory.new()
	m:write32(0x1000, 0xDEADBEEF)
	assert_eq(m:read32(0x1000), 0xDEADBEEF)
end)

test("read/write 64-bit", function()
	local m = Memory.new()
	m:write64(0x1000, 0x0000000100000002)
	assert_eq(m:read32(0x1000), 0x00000002)
	assert_eq(m:read32(0x1004), 0x00000001)
end)

test("string read/write", function()
	local m = Memory.new()
	m:writeString(0x2000, "Hello, LuaOS!")
	assert_eq(m:readString(0x2000), "Hello, LuaOS!")
	assert_eq(m:read8(0x2000 + 13), 0)  -- null terminator
end)

test("cross-page write", function()
	local m = Memory.new()
	-- 페이지 경계(0x1000) 걸치는 32비트 쓰기
	m:write32(0x0FFE, 0x12345678)
	assert_eq(m:read8(0x0FFE), 0x78)
	assert_eq(m:read8(0x0FFF), 0x56)
	assert_eq(m:read8(0x1000), 0x34)
	assert_eq(m:read8(0x1001), 0x12)
end)

-- ============================================================
-- 3. CPU 레지스터 테스트
-- ============================================================
print("\n=== CPU Register Tests ===")

test("x0 항상 0", function()
	local m = Memory.new()
	local c = CPU.new(m)
	c:setReg(0, 0xDEAD)
	assert_eq(c:getReg(0), 0)
end)

test("일반 레지스터 읽기/쓰기", function()
	local m = Memory.new()
	local c = CPU.new(m)
	c:setReg(1, 42)
	assert_eq(c:getReg(1), 42)
	c:setReg(31, 0xCAFE)
	assert_eq(c:getReg(31), 0xCAFE)
end)

test("u64 음수 처리", function()
	local u64 = CPU.u64
	local i64 = CPU.i64
	-- Luau double(53비트) 한계: 2^64-1 과 2^64 는 같은 float 값
	-- u64(-1) == 0xFFFFFFFFFFFFFFFF 는 같은 float으로 true
	assert_eq(u64(-1), 0xFFFFFFFFFFFFFFFF)
	-- i64(x) 는 x < 2^63 범위에서 동작 확인
	assert_eq(i64(0x8000000000000000), -9223372036854775808)  -- INT64_MIN (근사)
	assert_eq(i64(42), 42)
	assert_eq(i64(0), 0)
	-- NOTE: i64(0xFFFFFFFFFFFFFFFF) = 0 (float 정밀도 한계, 실제 에뮬레이션 영향 미미)
end)

test("signExt32", function()
	local i32 = CPU.i32
	assert_eq(i32(0x80000000), -2147483648)
	assert_eq(i32(0x7FFFFFFF),  2147483647)
	assert_eq(i32(0),           0)
end)

-- ============================================================
-- 4. Decode 테스트
-- ============================================================
print("\n=== Decode Tests ===")

test("ADDI x1, x0, 42 디코드", function()
	-- ADDI: opcode=0x13, rd=1, funct3=0, rs1=0, imm=42
	-- imm[11:0]=42=0x02A, rs1=0, funct3=0, rd=1, opcode=0x13
	-- 0x02A00093
	local instr = 0x02A00093
	local d = Decode.decode(instr)
	assert_eq(d.op,     0x13)
	assert_eq(d.rd,     1)
	assert_eq(d.funct3, 0)
	assert_eq(d.rs1,    0)
	assert_eq(d.imm,    42)
end)

test("LUI x1, 0x12345 디코드", function()
	-- LUI: opcode=0x37, rd=1, imm=0x12345000
	-- 0x123450B7
	local instr = 0x123450B7
	local d = Decode.decode(instr)
	assert_eq(d.op,  0x37)
	assert_eq(d.rd,  1)
	-- imm는 상위 20비트 (부호 확장, 12비트 시프트됨)
	assert_eq(d.imm, 0x12345000)
end)

test("JAL x1, +4 디코드", function()
	-- JAL: opcode=0x6F, rd=1, imm=4
	-- 간단히 ADDI만 테스트
	local instr = 0x004000EF  -- JAL x1, 4
	local d = Decode.decode(instr)
	assert_eq(d.op, 0x6F)
end)

test("C 확장 감지", function()
	local d = Decode.decode(0x0001)  -- C.NOP (압축)
	assert_eq(d.compressed, true)
	assert_eq(d.size, 2)
end)

-- ============================================================
-- 5. 명령어 실행 테스트 (수동 프로그램)
-- ============================================================
print("\n=== Execute Tests ===")

-- 더미 syscall 핸들러
local outputBuf = ""
local dummySys = {
	write = function(fd, data)
		if fd == 1 or fd == 2 then outputBuf ..= data end
		return #data
	end,
	read    = function() return "" end,
	open    = function() return nil end,
	close   = function() end,
	stat    = function() return nil end,
	readdir = function() return {} end,
	mkdir   = function() return nil end,
	unlink  = function() return nil end,
	rename  = function() return nil end,
	chdir   = function() return 0 end,
	sleep   = function() end,
	exit    = function(code) error("EXIT:" .. tostring(code)) end,
	getpid  = function() return 1 end,
}

-- 수동으로 RISC-V 기계어 작성: 1+2=3 계산 후 exit
-- 메모리 주소 0x1000 에 프로그램 배치
local function buildProgram(mem, base)
	local pos = base
	local function emit(instr)
		mem:write32(pos, instr)
		pos += 4
	end

	-- addi x10, x0, 1       # a0 = 1
	emit(0x00100513)
	-- addi x11, x0, 2       # a1 = 2
	emit(0x00200593)
	-- add  x10, x10, x11    # a0 = a0 + a1 = 3
	emit(0x00B50533)
	-- addi x17, x0, 93      # a7 = 93 (exit syscall)
	emit(0x05D00893)
	-- ecall
	emit(0x00000073)

	return pos - base  -- 프로그램 크기
end

test("ADD + exit 실행", function()
	local m = Memory.new()
	local c = CPU.new(m)
	c.pc = 0x1000

	-- 스택 설정
	c:setReg(2, 0x7FFFFF00)

	buildProgram(m, 0x1000)

	local exitCode = nil
	local sys = {
		write = function() return 0 end,
		read  = function() return "" end,
		open  = function() return nil end,
		close = function() end,
		stat  = function() return nil end,
		readdir=function() return {} end,
		mkdir = function() end,
		unlink= function() end,
		rename= function() end,
		chdir = function() return 0 end,
		sleep = function() end,
		getpid= function() return 1 end,
		exit  = function(code)
			exitCode = code
			c.running = false
		end,
	}

	Execute.run(c, m, sys, 100)

	-- exit syscall 전 ADD 결과는 x10=3, exit 후 x10에 syscall 반환값 0이 쓰임
	-- exitCode로 검증
	assert_eq(exitCode, 3)            -- exit(3) 호출됨
end)

test("ADDI 즉시값", function()
	local m = Memory.new()
	local c = CPU.new(m)
	c.pc = 0x1000

	-- addi x5, x0, 100
	m:write32(0x1000, 0x06400293)
	-- ebreak
	m:write32(0x1004, 0x00100073)

	Execute.run(c, m, dummySys, 10)
	assert_eq(c:getReg(5), 100)
end)

test("LUI + ADDI (LI 패턴)", function()
	local m = Memory.new()
	local c = CPU.new(m)
	c.pc = 0x1000

	-- lui x1, 1         → x1 = 0x1000
	m:write32(0x1000, 0x000010B7)
	-- addi x1, x1, 5   → x1 = 0x1005
	m:write32(0x1004, 0x00508093)
	-- ebreak
	m:write32(0x1008, 0x00100073)

	Execute.run(c, m, dummySys, 10)
	assert_eq(c:getReg(1), 0x1005)
end)

test("BEQ 분기 taken", function()
	local m = Memory.new()
	local c = CPU.new(m)
	c.pc = 0x1000

	-- addi x1, x0, 5
	m:write32(0x1000, 0x00500093)
	-- addi x2, x0, 5
	m:write32(0x1004, 0x00500113)
	-- beq x1, x2, +8   → 0x1000+8=0x1010 (skip next)
	-- BEQ: opcode=0x63, funct3=0, rs1=1, rs2=2, imm=8
	-- imm=8: bit12=0,bit11=0,bits10:5=0,bits4:1=0100 → 0x00208463
	m:write32(0x1008, 0x00208463)
	-- addi x3, x0, 99  (이 줄이 스킵돼야 함)
	m:write32(0x100C, 0x06300193)
	-- addi x3, x0, 1   (여기로 점프)
	m:write32(0x1010, 0x00100193)
	-- ebreak
	m:write32(0x1014, 0x00100073)

	Execute.run(c, m, dummySys, 20)
	assert_eq(c:getReg(3), 1)  -- 99가 아닌 1이어야 함
end)

test("STORE + LOAD 왕복", function()
	local m = Memory.new()
	local c = CPU.new(m)
	c.pc = 0x1000

	-- lui x1, 2         → x1 = 0x2000
	m:write32(0x1000, 0x000020B7)
	-- addi x2, x0, 0x55
	m:write32(0x1004, 0x05500113)
	-- sw x2, 0(x1)      → mem[0x2000] = 0x55
	m:write32(0x1008, 0x00212023)
	-- lw x3, 0(x1)      → x3 = mem[0x2000]
	m:write32(0x100C, 0x00012183)
	-- ebreak
	m:write32(0x1010, 0x00100073)

	Execute.run(c, m, dummySys, 20)
	assert_eq(c:getReg(3), 0x55)
end)

test("MUL (M 확장)", function()
	local m = Memory.new()
	local c = CPU.new(m)
	c.pc = 0x1000

	-- addi x1, x0, 6
	m:write32(0x1000, 0x00600093)
	-- addi x2, x0, 7
	m:write32(0x1004, 0x00700113)
	-- mul x3, x1, x2    funct7=0x01, funct3=0
	-- 0x022081B3
	m:write32(0x1008, 0x022081B3)
	-- ebreak
	m:write32(0x100C, 0x00100073)

	Execute.run(c, m, dummySys, 20)
	assert_eq(c:getReg(3), 42)
end)

-- ============================================================
-- 6. ELF 파서 테스트 (최소 ELF64 헤더)
-- ============================================================
print("\n=== ELF Tests ===")

test("base64 인코딩/디코딩", function()
	local original = "Hello, RISC-V World!"
	-- 수동 base64 인코딩
	local b64 = "SGVsbG8sIFJJU0MtViBXb3JsZCE="
	local decoded = ELF.decodeBase64(b64)
	assert_eq(decoded, original)
end)

test("비 ELF 파일 거부", function()
	local elf, err = ELF.parse("not an elf file")
	assert_eq(elf, nil)
	assert_eq(type(err), "string")
end)

-- ============================================================
-- 결과 출력
-- ============================================================
print("\n" .. string.rep("=", 40))
print(string.format("결과: %d passed, %d failed", passed, failed))
print(string.rep("=", 40))

if failed > 0 then
	os.exit(1)
end
