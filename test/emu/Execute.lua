-- RISC-V 64 명령어 실행기
-- RV64IMAFD + C + Zicsr (약 200개 명령어)
local Decode  = require("./Decode")
local Syscall = require("./Syscall")

local Execute = {}

local OP   = Decode.OP
local bits = Decode.bits
local sext = Decode.sext

-- 64비트 헬퍼
local function u64(v)
	if type(v) ~= "number" then v = 0 end
	return v % 0x10000000000000000
end
local function i64(v)
	v = u64(v)
	if v >= 0x8000000000000000 then v = v - 0x10000000000000000 end
	return v
end
local function u32(v) return v % 0x100000000 end
local function i32(v)
	v = u32(v)
	if v >= 0x80000000 then v = v - 0x100000000 end
	return v
end

-- 부호 없는 64비트 비교
local function ltu(a, b)
	a = u64(a); b = u64(b)
	return a < b
end

-- 32비트 곱셈 (오버플로 방지)
local function mulh(a, b)
	-- 128비트 결과의 상위 64비트 (근사: Luau double로)
	return math.floor(i64(a) * i64(b) / 0x10000000000000000)
end
local function mulhu(a, b)
	return math.floor(u64(a) * u64(b) / 0x10000000000000000)
end
local function mulhsu(a, b)
	return math.floor(i64(a) * u64(b) / 0x10000000000000000)
end

-- C 확장 명령어 실행
local function execCompressed(cpu, mem, instr)
	local op     = bit32.band(instr, 3)
	local f3     = bits(instr, 15, 13)
	local nextPC = cpu.pc + 2

	-- CL/CS 레지스터 (x8~x15 = c.rd/c.rs1/c.rs2)
	local function creg(n) return n + 8 end

	if op == 0 then  -- Quadrant 0
		if f3 == 0 then  -- C.ADDI4SPN
			local nzuimm = bit32.bor(
				bit32.lshift(bits(instr, 12, 11), 4),
				bit32.lshift(bits(instr, 10, 9),  6),
				bit32.lshift(bits(instr, 8,  8),  2),
				bit32.lshift(bits(instr, 7,  7),  3)
			) * 4
			local rd = creg(bits(instr, 4, 2))
			cpu:setReg(rd, u64(cpu:getReg(2) + nzuimm))
		elseif f3 == 1 then  -- C.FLD
			local imm = bit32.bor(bit32.lshift(bits(instr,12,10),3), bit32.lshift(bits(instr,6,5),6))
			local rd  = creg(bits(instr, 4, 2))
			local rs1 = creg(bits(instr, 9, 7))
			local addr = u64(cpu:getReg(rs1) + imm)
			local lo = mem:read32(addr); local hi = mem:read32(addr+4)
			cpu.f[rd] = lo + hi * 0x100000000  -- 저장만
		elseif f3 == 2 then  -- C.LW
			local imm  = bit32.bor(bit32.lshift(bits(instr,12,10),3), bit32.lshift(bits(instr,6,6),2), bit32.lshift(bits(instr,5,5),6))
			local rd   = creg(bits(instr, 4, 2))
			local rs1  = creg(bits(instr, 9, 7))
			local addr = u64(cpu:getReg(rs1) + imm)
			cpu:setReg(rd, u64(i32(mem:read32(addr))))
		elseif f3 == 3 then  -- C.LD
			local imm  = bit32.bor(bit32.lshift(bits(instr,12,10),3), bit32.lshift(bits(instr,6,5),6))
			local rd   = creg(bits(instr, 4, 2))
			local rs1  = creg(bits(instr, 9, 7))
			cpu:setReg(rd, mem:read64(u64(cpu:getReg(rs1) + imm)))
		elseif f3 == 5 then  -- C.FSD
			local imm  = bit32.bor(bit32.lshift(bits(instr,12,10),3), bit32.lshift(bits(instr,6,5),6))
			local rs1  = creg(bits(instr, 9, 7))
			local rs2  = creg(bits(instr, 4, 2))
			local addr = u64(cpu:getReg(rs1) + imm)
			local v    = cpu.f[rs2] or 0
			mem:write32(addr,   u32(v))
			mem:write32(addr+4, u32(math.floor(v / 0x100000000)))
		elseif f3 == 6 then  -- C.SW
			local imm  = bit32.bor(bit32.lshift(bits(instr,12,10),3), bit32.lshift(bits(instr,6,6),2), bit32.lshift(bits(instr,5,5),6))
			local rs1  = creg(bits(instr, 9, 7))
			local rs2  = creg(bits(instr, 4, 2))
			mem:write32(u64(cpu:getReg(rs1) + imm), u32(cpu:getReg(rs2)))
		elseif f3 == 7 then  -- C.SD
			local imm  = bit32.bor(bit32.lshift(bits(instr,12,10),3), bit32.lshift(bits(instr,6,5),6))
			local rs1  = creg(bits(instr, 9, 7))
			local rs2  = creg(bits(instr, 4, 2))
			mem:write64(u64(cpu:getReg(rs1) + imm), cpu:getReg(rs2))
		end

	elseif op == 1 then  -- Quadrant 1
		if f3 == 0 then  -- C.ADDI / C.NOP
			local rd  = bits(instr, 11, 7)
			local imm = sext(bit32.bor(bit32.lshift(bits(instr,12,12),5), bits(instr,6,2)), 6)
			cpu:setReg(rd, u64(cpu:getRegSigned(rd) + imm))
		elseif f3 == 1 then  -- C.ADDIW
			local rd  = bits(instr, 11, 7)
			local imm = sext(bit32.bor(bit32.lshift(bits(instr,12,12),5), bits(instr,6,2)), 6)
			cpu:setReg(rd, u64(i32(i32(cpu:getReg(rd)) + imm)))
		elseif f3 == 2 then  -- C.LI
			local rd  = bits(instr, 11, 7)
			local imm = sext(bit32.bor(bit32.lshift(bits(instr,12,12),5), bits(instr,6,2)), 6)
			cpu:setReg(rd, u64(imm))
		elseif f3 == 3 then
			local rd = bits(instr, 11, 7)
			if rd == 2 then  -- C.ADDI16SP
				local imm = sext(bit32.bor(
					bit32.lshift(bits(instr,12,12),9),
					bit32.lshift(bits(instr,6,6),4),
					bit32.lshift(bits(instr,5,5),6),
					bit32.lshift(bits(instr,4,3),7),
					bit32.lshift(bits(instr,2,2),5)
				), 10)
				cpu:setReg(2, u64(cpu:getRegSigned(2) + imm))
			else  -- C.LUI
				local imm = sext(bit32.bor(bit32.lshift(bits(instr,12,12),17), bit32.lshift(bits(instr,6,2),12)), 18)
				cpu:setReg(rd, u64(imm))
			end
		elseif f3 == 4 then  -- C.SRLI/C.SRAI/C.ANDI/C.SUB/C.XOR/C.OR/C.AND/C.SUBW/C.ADDW
			local f2  = bits(instr, 11, 10)
			local rd  = creg(bits(instr, 9, 7))
			local shamt = bit32.bor(bit32.lshift(bits(instr,12,12),5), bits(instr,6,2))
			if f2 == 0 then  -- C.SRLI
				cpu:setReg(rd, bit32.rshift(cpu:getReg(rd), shamt))
			elseif f2 == 1 then  -- C.SRAI
				local v = i64(cpu:getReg(rd))
				cpu:setReg(rd, u64(math.floor(v / 2^shamt)))
			elseif f2 == 2 then  -- C.ANDI
				local imm = sext(bit32.bor(bit32.lshift(bits(instr,12,12),5), bits(instr,6,2)), 6)
				cpu:setReg(rd, u64(bit32.band(cpu:getReg(rd), imm)))
			elseif f2 == 3 then
				local rs2 = creg(bits(instr, 4, 2))
				local b11 = bits(instr, 12, 12)
				local f1  = bits(instr, 6, 5)
				if b11 == 0 then
					if f1==0 then cpu:setReg(rd, u64(i64(cpu:getReg(rd)) - i64(cpu:getReg(rs2))))
					elseif f1==1 then cpu:setReg(rd, bit32.bxor(cpu:getReg(rd), cpu:getReg(rs2)))
					elseif f1==2 then cpu:setReg(rd, bit32.bor(cpu:getReg(rd), cpu:getReg(rs2)))
					elseif f1==3 then cpu:setReg(rd, bit32.band(cpu:getReg(rd), cpu:getReg(rs2))) end
				else
					if f1==0 then cpu:setReg(rd, u64(i32(i32(cpu:getReg(rd)) - i32(cpu:getReg(rs2)))))
					elseif f1==1 then cpu:setReg(rd, u64(i32(i32(cpu:getReg(rd)) + i32(cpu:getReg(rs2))))) end
				end
			end
		elseif f3 == 5 then  -- C.J
			local imm = sext(bit32.bor(
				bit32.lshift(bits(instr,12,12),11), bit32.lshift(bits(instr,11,11),4),
				bit32.lshift(bits(instr,10,9),8),   bit32.lshift(bits(instr,8,8),10),
				bit32.lshift(bits(instr,7,7),6),    bit32.lshift(bits(instr,6,6),7),
				bit32.lshift(bits(instr,5,3),1),    bit32.lshift(bits(instr,2,2),5)
			), 12)
			nextPC = u64(cpu.pc + imm)
		elseif f3 == 6 then  -- C.BEQZ
			local rs1 = creg(bits(instr, 9, 7))
			local imm = sext(bit32.bor(
				bit32.lshift(bits(instr,12,12),8), bit32.lshift(bits(instr,11,10),3),
				bit32.lshift(bits(instr,6,5),6),   bit32.lshift(bits(instr,4,3),1),
				bit32.lshift(bits(instr,2,2),5)
			), 9)
			if cpu:getReg(rs1) == 0 then nextPC = u64(cpu.pc + imm) end
		elseif f3 == 7 then  -- C.BNEZ
			local rs1 = creg(bits(instr, 9, 7))
			local imm = sext(bit32.bor(
				bit32.lshift(bits(instr,12,12),8), bit32.lshift(bits(instr,11,10),3),
				bit32.lshift(bits(instr,6,5),6),   bit32.lshift(bits(instr,4,3),1),
				bit32.lshift(bits(instr,2,2),5)
			), 9)
			if cpu:getReg(rs1) ~= 0 then nextPC = u64(cpu.pc + imm) end
		end

	elseif op == 2 then  -- Quadrant 2
		if f3 == 0 then  -- C.SLLI
			local rd    = bits(instr, 11, 7)
			local shamt = bit32.bor(bit32.lshift(bits(instr,12,12),5), bits(instr,6,2))
			cpu:setReg(rd, u64(cpu:getReg(rd) * 2^shamt))
		elseif f3 == 1 then  -- C.FLDSP
			local rd  = bits(instr, 11, 7)
			local imm = bit32.bor(bit32.lshift(bits(instr,12,12),5), bit32.lshift(bits(instr,6,5),3), bit32.lshift(bits(instr,4,2),6))
			local addr = u64(cpu:getReg(2) + imm)
			cpu.f[rd] = mem:read64(addr)
		elseif f3 == 2 then  -- C.LWSP
			local rd  = bits(instr, 11, 7)
			local imm = bit32.bor(bit32.lshift(bits(instr,12,12),5), bit32.lshift(bits(instr,6,4),2), bit32.lshift(bits(instr,3,2),6))
			cpu:setReg(rd, u64(i32(mem:read32(u64(cpu:getReg(2) + imm)))))
		elseif f3 == 3 then  -- C.LDSP
			local rd  = bits(instr, 11, 7)
			local imm = bit32.bor(bit32.lshift(bits(instr,12,12),5), bit32.lshift(bits(instr,6,5),3), bit32.lshift(bits(instr,4,2),6))
			cpu:setReg(rd, mem:read64(u64(cpu:getReg(2) + imm)))
		elseif f3 == 4 then
			local b12 = bits(instr, 12, 12)
			local rs1 = bits(instr, 11, 7)
			local rs2 = bits(instr, 6, 2)
			if b12 == 0 then
				if rs2 == 0 then  -- C.JR
					nextPC = u64(cpu:getReg(rs1))
				else  -- C.MV
					cpu:setReg(rs1, cpu:getReg(rs2))
				end
			else
				if rs1 == 0 and rs2 == 0 then  -- C.EBREAK
					cpu.running = false
				elseif rs2 == 0 then  -- C.JALR
					local t = u64(cpu.pc + 2)
					nextPC = u64(cpu:getReg(rs1))
					cpu:setReg(1, t)
				else  -- C.ADD
					cpu:setReg(rs1, u64(cpu:getRegSigned(rs1) + cpu:getRegSigned(rs2)))
				end
			end
		elseif f3 == 5 then  -- C.FSDSP
			local imm  = bit32.bor(bit32.lshift(bits(instr,12,10),3), bit32.lshift(bits(instr,9,7),6))
			local rs2  = bits(instr, 6, 2)
			local addr = u64(cpu:getReg(2) + imm)
			local v    = cpu.f[rs2] or 0
			mem:write64(addr, math.floor(v) % 0x10000000000000000)
		elseif f3 == 6 then  -- C.SWSP
			local imm  = bit32.bor(bit32.lshift(bits(instr,12,9),2), bit32.lshift(bits(instr,8,7),6))
			local rs2  = bits(instr, 6, 2)
			mem:write32(u64(cpu:getReg(2) + imm), u32(cpu:getReg(rs2)))
		elseif f3 == 7 then  -- C.SDSP
			local imm  = bit32.bor(bit32.lshift(bits(instr,12,10),3), bit32.lshift(bits(instr,9,7),6))
			local rs2  = bits(instr, 6, 2)
			mem:write64(u64(cpu:getReg(2) + imm), cpu:getReg(rs2))
		end
	end

	cpu.pc = nextPC
end

-- 32비트 명령어 실행
local function exec32(cpu, mem, instr, kernelSys)
	local d      = Decode.decode(instr)
	local nextPC = u64(cpu.pc + 4)
	local op     = d.op

	---------------------------------------------------------------
	-- LUI
	if op == OP.LUI then
		cpu:setReg(d.rd, u64(d.imm))

	-- AUIPC
	elseif op == OP.AUIPC then
		cpu:setReg(d.rd, u64(cpu.pc + d.imm))

	-- JAL
	elseif op == OP.JAL then
		cpu:setReg(d.rd, u64(cpu.pc + 4))
		nextPC = u64(cpu.pc + d.imm)

	-- JALR
	elseif op == OP.JALR then
		local t = u64(cpu.pc + 4)
		nextPC  = u64(bit32.band(cpu:getReg(d.rs1) + d.imm, 0xFFFFFFFFFFFFFFFE))
		cpu:setReg(d.rd, t)

	-- BRANCH
	elseif op == OP.BRANCH then
		local rs1 = cpu:getReg(d.rs1)
		local rs2 = cpu:getReg(d.rs2)
		local taken = false
		local f = d.funct3
		if     f == 0 then taken = rs1 == rs2                -- BEQ
		elseif f == 1 then taken = rs1 ~= rs2                -- BNE
		elseif f == 4 then taken = i64(rs1) <  i64(rs2)     -- BLT
		elseif f == 5 then taken = i64(rs1) >= i64(rs2)     -- BGE
		elseif f == 6 then taken = ltu(rs1, rs2)             -- BLTU
		elseif f == 7 then taken = not ltu(rs1, rs2) and rs1 ~= rs2 or rs1 == rs2 -- BGEU
			taken = u64(rs1) >= u64(rs2)
		end
		if taken then nextPC = u64(cpu.pc + d.imm) end

	-- LOAD
	elseif op == OP.LOAD then
		local addr = u64(cpu:getRegSigned(d.rs1) + d.imm)
		local val
		local f = d.funct3
		if     f == 0 then val = u64(sext(mem:read8(addr),  8))   -- LB
		elseif f == 1 then val = u64(sext(mem:read16(addr), 16))  -- LH
		elseif f == 2 then val = u64(i32(mem:read32(addr)))       -- LW
		elseif f == 3 then val = mem:read64(addr)                  -- LD
		elseif f == 4 then val = mem:read8(addr)                   -- LBU
		elseif f == 5 then val = mem:read16(addr)                  -- LHU
		elseif f == 6 then val = u32(mem:read32(addr))             -- LWU
		end
		if val then cpu:setReg(d.rd, val) end

	-- STORE
	elseif op == OP.STORE then
		local addr = u64(cpu:getRegSigned(d.rs1) + d.imm)
		local val  = cpu:getReg(d.rs2)
		local f = d.funct3
		if     f == 0 then mem:write8(addr,  val)   -- SB
		elseif f == 1 then mem:write16(addr, val)   -- SH
		elseif f == 2 then mem:write32(addr, val)   -- SW
		elseif f == 3 then mem:write64(addr, val)   -- SD
		end

	-- OP-IMM (64비트)
	elseif op == OP.OP_IMM then
		local rs1 = cpu:getReg(d.rs1)
		local imm = d.imm
		local val
		local f = d.funct3
		if     f == 0 then val = u64(i64(rs1) + imm)              -- ADDI
		elseif f == 1 then val = u64(rs1 * 2^d.shamt)             -- SLLI
		elseif f == 2 then val = u64(i64(rs1) < imm and 1 or 0)   -- SLTI
		elseif f == 3 then val = ltu(rs1, u64(imm)) and 1 or 0    -- SLTIU
		elseif f == 4 then val = bit32.bxor(u32(rs1), u32(imm))   -- XORI (32비트 근사)
			val = u64(bit32.bxor(u32(rs1), u32(imm)) + (i64(rs1) < 0 and 0xFFFFFFFF00000000 or 0))
			-- 정확한 64비트 XOR
			local lo = bit32.bxor(u32(rs1), u32(imm))
			local hi_rs1 = math.floor(rs1 / 0x100000000)
			local hi_imm = imm < 0 and 0xFFFFFFFF or 0
			val = u64(lo + bit32.bxor(u32(hi_rs1), hi_imm) * 0x100000000)
		elseif f == 5 then
			if d.funct7 == 0 then  -- SRLI
				val = math.floor(rs1 / 2^d.shamt)
			else  -- SRAI
				val = u64(math.floor(i64(rs1) / 2^d.shamt))
			end
		elseif f == 6 then  -- ORI
			local lo = bit32.bor(u32(rs1), u32(imm))
			local hi_rs1 = math.floor(rs1 / 0x100000000)
			local hi_imm = imm < 0 and 0xFFFFFFFF or 0
			val = u64(lo + bit32.bor(u32(hi_rs1), hi_imm) * 0x100000000)
		elseif f == 7 then  -- ANDI
			local lo = bit32.band(u32(rs1), u32(imm))
			local hi_rs1 = math.floor(rs1 / 0x100000000)
			local hi_imm = imm < 0 and 0xFFFFFFFF or 0
			val = u64(lo + bit32.band(u32(hi_rs1), hi_imm) * 0x100000000)
		end
		if val then cpu:setReg(d.rd, val) end

	-- OP-IMM-32 (32비트 연산, 부호확장 결과)
	elseif op == OP.OP_IMM_32 then
		local rs1 = i32(cpu:getReg(d.rs1))
		local imm = d.imm
		local val
		local f = d.funct3
		if     f == 0 then val = i32(rs1 + imm)           -- ADDIW
		elseif f == 1 then val = i32(u32(rs1) * 2^(imm % 32))  -- SLLIW
		elseif f == 5 then
			if d.funct7 == 0 then
				val = i32(math.floor(u32(rs1) / 2^(imm%32)))  -- SRLIW
			else
				val = i32(math.floor(rs1 / 2^(imm%32)))       -- SRAIW
			end
		end
		if val then cpu:setReg(d.rd, u64(val)) end

	-- OP (64비트)
	elseif op == OP.OP then
		local rs1 = cpu:getReg(d.rs1)
		local rs2 = cpu:getReg(d.rs2)
		local f3 = d.funct3
		local f7 = d.funct7
		local val

		if f7 == 0x01 then  -- M 확장
			if     f3 == 0 then val = u64(i64(rs1) * i64(rs2))        -- MUL
			elseif f3 == 1 then val = u64(mulh(rs1, rs2))             -- MULH
			elseif f3 == 2 then val = u64(mulhsu(rs1, rs2))           -- MULHSU
			elseif f3 == 3 then val = u64(mulhu(rs1, rs2))            -- MULHU
			elseif f3 == 4 then  -- DIV
				local a, b = i64(rs1), i64(rs2)
				val = b == 0 and u64(-1) or u64(math.floor(a / b))
			elseif f3 == 5 then  -- DIVU
				val = rs2 == 0 and u64(-1) or math.floor(rs1 / rs2)
			elseif f3 == 6 then  -- REM
				local a, b = i64(rs1), i64(rs2)
				val = b == 0 and rs1 or u64(a - math.floor(a/b)*b)
			elseif f3 == 7 then  -- REMU
				val = rs2 == 0 and rs1 or (rs1 % rs2)
			end
		else  -- 기본 정수 연산
			if     f3 == 0 and f7 == 0  then val = u64(i64(rs1) + i64(rs2))  -- ADD
			elseif f3 == 0 and f7 == 32 then val = u64(i64(rs1) - i64(rs2))  -- SUB
			elseif f3 == 1 then val = u64(rs1 * 2^(rs2%64))                   -- SLL
			elseif f3 == 2 then val = i64(rs1) < i64(rs2) and 1 or 0         -- SLT
			elseif f3 == 3 then val = ltu(rs1,rs2) and 1 or 0                 -- SLTU
			elseif f3 == 4 then  -- XOR
				local lo = bit32.bxor(u32(rs1), u32(rs2))
				local hi = bit32.bxor(u32(math.floor(rs1/0x100000000)), u32(math.floor(rs2/0x100000000)))
				val = u64(lo + hi * 0x100000000)
			elseif f3 == 5 and f7 == 0  then val = math.floor(rs1 / 2^(rs2%64))                -- SRL
			elseif f3 == 5 and f7 == 32 then val = u64(math.floor(i64(rs1) / 2^(rs2%64)))      -- SRA
			elseif f3 == 6 then  -- OR
				local lo = bit32.bor(u32(rs1), u32(rs2))
				local hi = bit32.bor(u32(math.floor(rs1/0x100000000)), u32(math.floor(rs2/0x100000000)))
				val = u64(lo + hi * 0x100000000)
			elseif f3 == 7 then  -- AND
				local lo = bit32.band(u32(rs1), u32(rs2))
				local hi = bit32.band(u32(math.floor(rs1/0x100000000)), u32(math.floor(rs2/0x100000000)))
				val = u64(lo + hi * 0x100000000)
			end
		end
		if val then cpu:setReg(d.rd, val) end

	-- OP-32 (32비트 결과, 부호확장)
	elseif op == OP.OP_32 then
		local rs1 = i32(cpu:getReg(d.rs1))
		local rs2 = cpu:getReg(d.rs2)
		local f3 = d.funct3
		local f7 = d.funct7
		local val

		if f7 == 0x01 then  -- M 확장 32비트
			if     f3 == 0 then val = i32(rs1 * i32(rs2))               -- MULW
			elseif f3 == 4 then  -- DIVW
				local b = i32(rs2)
				val = b == 0 and -1 or i32(math.floor(rs1 / b))
			elseif f3 == 5 then  -- DIVUW
				local a, b = u32(rs1), u32(rs2)
				val = b == 0 and i32(-1) or i32(math.floor(a / b))
			elseif f3 == 6 then  -- REMW
				local b = i32(rs2)
				val = b == 0 and rs1 or i32(rs1 - math.floor(rs1/b)*b)
			elseif f3 == 7 then  -- REMUW
				local a, b = u32(rs1), u32(rs2)
				val = b == 0 and i32(a) or i32(a % b)
			end
		else
			if     f3 == 0 and f7 == 0  then val = i32(rs1 + i32(rs2)) -- ADDW
			elseif f3 == 0 and f7 == 32 then val = i32(rs1 - i32(rs2)) -- SUBW
			elseif f3 == 1 then val = i32(u32(rs1) * 2^(rs2%32))       -- SLLW
			elseif f3 == 5 and f7 == 0  then val = i32(math.floor(u32(rs1)/2^(rs2%32)))  -- SRLW
			elseif f3 == 5 and f7 == 32 then val = i32(math.floor(rs1/2^(rs2%32)))       -- SRAW
			end
		end
		if val then cpu:setReg(d.rd, u64(val)) end

	-- LOAD_FP
	elseif op == OP.LOAD_FP then
		local addr = u64(cpu:getRegSigned(d.rs1) + d.imm)
		if d.funct3 == 2 then  -- FLW
			local bits32 = mem:read32(addr)
			-- IEEE 754 단정밀도 → Lua double (근사)
			cpu.f[d.rd] = bits32  -- 비트 그대로 저장
		elseif d.funct3 == 3 then  -- FLD
			cpu.f[d.rd] = mem:read64(addr)
		end

	-- STORE_FP
	elseif op == OP.STORE_FP then
		local addr = u64(cpu:getRegSigned(d.rs1) + d.imm)
		if d.funct3 == 2 then  -- FSW
			mem:write32(addr, u32(cpu.f[d.rs2] or 0))
		elseif d.funct3 == 3 then  -- FSD
			mem:write64(addr, (cpu.f[d.rs2] or 0) % 0x10000000000000000)
		end

	-- OP_FP (부동소수점 연산)
	elseif op == OP.OP_FP then
		local f7 = d.funct7
		local rs1v = cpu.f[d.rs1] or 0
		local rs2v = cpu.f[d.rs2] or 0
		-- 단정밀도(f7 & 3 == 0) vs 배정밀도(f7 & 3 == 1)
		-- 비트 표현 ↔ float 변환은 생략, 수치 연산만 처리
		if     f7 == 0x00 or f7 == 0x01 then cpu.f[d.rd] = rs1v + rs2v  -- FADD
		elseif f7 == 0x04 or f7 == 0x05 then cpu.f[d.rd] = rs1v - rs2v  -- FSUB
		elseif f7 == 0x08 or f7 == 0x09 then cpu.f[d.rd] = rs1v * rs2v  -- FMUL
		elseif f7 == 0x0C or f7 == 0x0D then cpu.f[d.rd] = rs1v / rs2v  -- FDIV
		elseif f7 == 0x2C or f7 == 0x2D then cpu.f[d.rd] = math.sqrt(rs1v)  -- FSQRT
		elseif f7 == 0x10 or f7 == 0x11 then  -- FSGNJ
			if     d.funct3 == 0 then cpu.f[d.rd] = math.abs(rs1v) * (rs2v >= 0 and 1 or -1)
			elseif d.funct3 == 1 then cpu.f[d.rd] = math.abs(rs1v) * (rs2v >= 0 and -1 or 1)
			elseif d.funct3 == 2 then cpu.f[d.rd] = (rs1v >= 0) == (rs2v >= 0) and rs1v or -rs1v
			end
		elseif f7 == 0x14 or f7 == 0x15 then  -- FMIN/FMAX
			if d.funct3 == 0 then cpu.f[d.rd] = math.min(rs1v, rs2v)
			else cpu.f[d.rd] = math.max(rs1v, rs2v) end
		elseif f7 == 0x50 or f7 == 0x51 then  -- FCMP
			local cmp
			if     d.funct3 == 0 then cmp = rs1v == rs2v and 1 or 0  -- FEQ
			elseif d.funct3 == 1 then cmp = rs1v < rs2v  and 1 or 0  -- FLT
			elseif d.funct3 == 2 then cmp = rs1v <= rs2v and 1 or 0  -- FLE
			end
			cpu:setReg(d.rd, cmp or 0)
		elseif f7 == 0x60 or f7 == 0x61 then  -- FCVT.W/WU/L/LU
			local rm = d.funct3
			local v = rs1v
			if     d.rs2 == 0 then cpu:setReg(d.rd, u64(i32(math.floor(v))))   -- FCVT.W
			elseif d.rs2 == 1 then cpu:setReg(d.rd, u64(u32(math.floor(v))))   -- FCVT.WU
			elseif d.rs2 == 2 then cpu:setReg(d.rd, u64(i64(math.floor(v))))   -- FCVT.L
			elseif d.rs2 == 3 then cpu:setReg(d.rd, u64(math.max(0, math.floor(v)))) -- FCVT.LU
			end
		elseif f7 == 0x68 or f7 == 0x69 then  -- FCVT (int→float)
			local v = cpu:getReg(d.rs1)
			if     d.rs2 == 0 then cpu.f[d.rd] = i32(v)
			elseif d.rs2 == 1 then cpu.f[d.rd] = u32(v)
			elseif d.rs2 == 2 then cpu.f[d.rd] = i64(v)
			elseif d.rs2 == 3 then cpu.f[d.rd] = v
			end
		elseif f7 == 0x70 or f7 == 0x71 then  -- FMV.X.W / FMV.X.D / FCLASS
			if d.funct3 == 0 then
				cpu:setReg(d.rd, u64(i32(cpu.f[d.rs1] or 0)))
			else  -- FCLASS: 간소화
				cpu:setReg(d.rd, 0x10)  -- 양의 정규 수
			end
		elseif f7 == 0x78 or f7 == 0x79 then  -- FMV.W.X / FMV.D.X
			cpu.f[d.rd] = cpu:getReg(d.rs1)
		end

	-- MADD/MSUB/NMADD/NMSUB (FMA)
	elseif op == OP.MADD or op == OP.MSUB or op == OP.NMADD or op == OP.NMSUB then
		local a = cpu.f[d.rs1] or 0
		local b = cpu.f[d.rs2] or 0
		local c = cpu.f[d.rs3] or 0
		if     op == OP.MADD  then cpu.f[d.rd] = a*b + c
		elseif op == OP.MSUB  then cpu.f[d.rd] = a*b - c
		elseif op == OP.NMADD then cpu.f[d.rd] = -(a*b) - c
		elseif op == OP.NMSUB then cpu.f[d.rd] = -(a*b) + c
		end

	-- AMO (원자적 메모리 연산)
	elseif op == OP.AMO then
		local addr = cpu:getReg(d.rs1)
		local f5 = bits(instr, 31, 27)
		local rs2v = cpu:getReg(d.rs2)

		-- 64비트 여부
		local is64 = d.funct3 == 3
		local memVal = is64 and mem:read64(addr) or u64(i32(mem:read32(addr)))

		cpu:setReg(d.rd, memVal)

		local newVal = memVal
		if     f5 == 0x00 then newVal = u64(i64(memVal) + i64(rs2v))         -- AMOADD
		elseif f5 == 0x01 then -- AMOSWAP
			newVal = rs2v
		elseif f5 == 0x04 then  -- AMOXOR
			local lo = bit32.bxor(u32(memVal), u32(rs2v))
			local hi = bit32.bxor(u32(math.floor(memVal/0x100000000)), u32(math.floor(rs2v/0x100000000)))
			newVal = u64(lo + hi*0x100000000)
		elseif f5 == 0x08 then  -- AMOOR
			local lo = bit32.bor(u32(memVal), u32(rs2v))
			local hi = bit32.bor(u32(math.floor(memVal/0x100000000)), u32(math.floor(rs2v/0x100000000)))
			newVal = u64(lo + hi*0x100000000)
		elseif f5 == 0x0C then  -- AMOAND
			local lo = bit32.band(u32(memVal), u32(rs2v))
			local hi = bit32.band(u32(math.floor(memVal/0x100000000)), u32(math.floor(rs2v/0x100000000)))
			newVal = u64(lo + hi*0x100000000)
		elseif f5 == 0x10 then newVal = u64(math.min(i64(memVal), i64(rs2v)))  -- AMOMIN
		elseif f5 == 0x14 then newVal = u64(math.max(i64(memVal), i64(rs2v)))  -- AMOMAX
		elseif f5 == 0x18 then newVal = math.min(memVal, rs2v)                  -- AMOMINU
		elseif f5 == 0x1C then newVal = math.max(memVal, rs2v)                  -- AMOMAXU
		elseif f5 == 0x02 then  -- LR.W/D: 그냥 load
			newVal = memVal
		elseif f5 == 0x03 then  -- SC.W/D: 항상 성공
			newVal = rs2v
			cpu:setReg(d.rd, 0)  -- 성공 = 0
		end

		if f5 ~= 0x02 and f5 ~= 0x03 then
			if is64 then mem:write64(addr, newVal)
			else mem:write32(addr, u32(newVal)) end
		elseif f5 == 0x03 then
			if is64 then mem:write64(addr, newVal)
			else mem:write32(addr, u32(newVal)) end
		end

	-- MISC-MEM (FENCE: 무시)
	elseif op == OP.MISC_MEM then
		-- FENCE, FENCE.I: 우리 에뮬레이터에서 순서 보장 필요 없음

	-- SYSTEM
	elseif op == OP.SYSTEM then
		local f3 = d.funct3
		if f3 == 0 then
			local funct12 = bits(instr, 31, 20)
			if funct12 == 0 then  -- ECALL
				-- a7 = syscall number, a0~a5 = args
				local nr = cpu:getReg(17)  -- x17 = a7
				local a0 = cpu:getReg(10)
				local a1 = cpu:getReg(11)
				local a2 = cpu:getReg(12)
				local a3 = cpu:getReg(13)
				local a4 = cpu:getReg(14)
				local a5 = cpu:getReg(15)
				local ret = Syscall.handle(cpu, mem, kernelSys, nr, a0, a1, a2, a3, a4, a5)
				cpu:setReg(10, u64(ret or 0))
			elseif funct12 == 1 then  -- EBREAK
				cpu.running = false
			end
		else  -- Zicsr
			local csr  = bits(instr, 31, 20)
			local rs1v = cpu:getReg(d.rs1)
			local old  = cpu:readCSR(csr)
			cpu:setReg(d.rd, old)
			if     f3 == 1 then cpu:writeCSR(csr, rs1v)                  -- CSRRW
			elseif f3 == 2 then cpu:writeCSR(csr, bit32.bor(u32(old), u32(rs1v)))  -- CSRRS
			elseif f3 == 3 then cpu:writeCSR(csr, bit32.band(u32(old), bit32.bnot(u32(rs1v))))  -- CSRRC
			elseif f3 == 5 then cpu:writeCSR(csr, d.rs1)                 -- CSRRWI
			elseif f3 == 6 then cpu:writeCSR(csr, bit32.bor(u32(old), d.rs1))  -- CSRRSI
			elseif f3 == 7 then cpu:writeCSR(csr, bit32.band(u32(old), bit32.bnot(d.rs1)))  -- CSRRCI
			end
		end
	end

	cpu.pc = nextPC
end

-- 메인 실행 루프
function Execute.run(cpu, mem, kernelSys, maxCycles)
	maxCycles = maxCycles or 10000000
	cpu.running = true

	while cpu.running and cpu.cycles < maxCycles do
		-- 명령어 페치
		local instr16 = mem:read16(cpu.pc)
		local low2    = bit32.band(instr16, 3)

		if low2 ~= 3 then
			-- 압축 명령어 (16비트)
			execCompressed(cpu, mem, instr16)
		else
			-- 일반 명령어 (32비트)
			local instr32 = mem:read32(cpu.pc)
			exec32(cpu, mem, instr32, kernelSys)
		end

		cpu.cycles += 1

		-- 코루틴 양보 (매 1000 사이클마다)
		if cpu.cycles % 1000 == 0 then
			coroutine.yield()
		end
	end

	return cpu.exitCode
end

return Execute
