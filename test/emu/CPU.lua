-- RISC-V 64 CPU 상태 및 유틸리티
local CPU = {}
CPU.__index = CPU

-- 64비트 정수 헬퍼 (Luau 53비트 정밀도 한계 보완)
local INT32_MAX  =  0x7FFFFFFF
local INT32_MIN  = -0x80000000
local UINT32_MAX =  0xFFFFFFFF
local INT64_MAX  =  0x7FFFFFFFFFFFFFFF  -- 근사값
local UINT64_MAX =  0xFFFFFFFFFFFFFFFF  -- 근사값

-- 부호 확장
local function signExt(val, bits)
	local shift = 2^(bits-1)
	if val >= shift then val = val - 2*shift end
	return val
end

local function signExt8(v)  return signExt(v % 256,          8)  end
local function signExt16(v) return signExt(v % 65536,        16) end
local function signExt32(v) return signExt(v % 0x100000000,  32) end

-- 64비트 부호 없는 값을 Luau 숫자로
-- Luau double은 53비트 정밀도 한계로 2^64 정확한 표현 불가
-- 음수 → 양수 변환은 2^64 덧셈 대신 부호 비트 처리로
local UINT64_MOD = 2^64  -- ≈ 1.8446744073709552e19

local function u64(v)
	if type(v) ~= "number" then return 0 end
	-- Lua double 범위에서 양수로 정규화
	v = v % UINT64_MOD
	if v < 0 then v = v + UINT64_MOD end
	return v
end

-- 64비트 부호 있는 값
-- Luau double 정밀도 한계: 상위 32비트 부호 비트로 판단
local function i64(v)
	v = u64(v)
	-- 상위 32비트 추출
	local hi = math.floor(v / 0x100000000) % 0x100000000
	if bit32.band(hi, 0x80000000) ~= 0 then
		-- 음수: 2^64 빼기
		-- 직접 빼기 불가(정밀도 손실), 대신 상하위 분리
		local lo = v % 0x100000000
		local signedHi = hi - 0x100000000  -- 상위 32비트 부호 있는 값
		return signedHi * 0x100000000 + lo
	end
	return v
end

-- 32비트 부호 없는
local function u32(v)
	return v % 0x100000000
end

-- 32비트 부호 있는
local function i32(v)
	return signExt32(v)
end

function CPU.new(memory)
	local c = setmetatable({}, CPU)
	c.mem   = memory
	-- 정수 레지스터 x0~x31
	c.x     = {}
	for i = 0, 31 do c.x[i] = 0 end
	-- 부동소수점 레지스터 f0~f31
	c.f     = {}
	for i = 0, 31 do c.f[i] = 0.0 end
	-- 프로그램 카운터
	c.pc    = 0
	-- CSR (Control and Status Registers)
	c.csr   = {}
	-- 상태
	c.running   = false
	c.exitCode  = 0
	c.cycles    = 0
	-- 훅 (syscall 처리용)
	c.syscallHandler = nil
	return c
end

-- x0는 항상 0
function CPU:setReg(n, v)
	if n ~= 0 then self.x[n] = u64(v) end
end

function CPU:getReg(n)
	if n == 0 then return 0 end
	return self.x[n]
end

function CPU:getRegSigned(n)
	return i64(self:getReg(n))
end

-- CSR 읽기/쓰기
local CSR_FFLAGS  = 0x001
local CSR_FRM     = 0x002
local CSR_FCSR    = 0x003
local CSR_CYCLE   = 0xC00
local CSR_TIME    = 0xC01
local CSR_INSTRET = 0xC02
local CSR_MSTATUS = 0x300

function CPU:readCSR(addr)
	if addr == CSR_CYCLE or addr == CSR_TIME or addr == CSR_INSTRET then
		return self.cycles
	end
	return self.csr[addr] or 0
end

function CPU:writeCSR(addr, val)
	self.csr[addr] = u64(val)
end

-- 헬퍼 익스포트
CPU.signExt   = signExt
CPU.signExt8  = signExt8
CPU.signExt16 = signExt16
CPU.signExt32 = signExt32
CPU.u64 = u64
CPU.i64 = i64
CPU.u32 = u32
CPU.i32 = i32

return CPU
