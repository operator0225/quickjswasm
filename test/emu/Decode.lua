-- RISC-V 64 명령어 디코더
-- 고정 32비트 및 C 확장(16비트) 명령어 디코딩
local Decode = {}

-- opcode 필드 (bits 6:0)
local OP = {
	LOAD      = 0x03,
	LOAD_FP   = 0x07,
	MISC_MEM  = 0x0F,
	OP_IMM    = 0x13,
	AUIPC     = 0x17,
	OP_IMM_32 = 0x1B,
	STORE     = 0x23,
	STORE_FP  = 0x27,
	AMO       = 0x2F,
	OP        = 0x33,
	LUI       = 0x37,
	OP_32     = 0x3B,
	MADD      = 0x43,
	MSUB      = 0x47,
	NMSUB     = 0x4B,
	NMADD     = 0x4F,
	OP_FP     = 0x53,
	BRANCH    = 0x63,
	JALR      = 0x67,
	JAL       = 0x6F,
	SYSTEM    = 0x73,
}

-- 비트 추출 헬퍼
local function bits(val, hi, lo)
	local mask = bit32.lshift(1, hi - lo + 1) - 1
	return bit32.band(bit32.rshift(val, lo), mask)
end

local function bit_(val, pos)
	return bit32.band(bit32.rshift(val, pos), 1)
end

-- 부호 확장
local function sext(val, nbits)
	if bit_(val, nbits-1) == 1 then
		val = val - bit32.lshift(1, nbits)
	end
	return val
end

-- R-type 디코드
local function decodeR(instr)
	return {
		rd     = bits(instr, 11, 7),
		funct3 = bits(instr, 14, 12),
		rs1    = bits(instr, 19, 15),
		rs2    = bits(instr, 24, 20),
		funct7 = bits(instr, 31, 25),
	}
end

-- I-type 디코드
local function decodeI(instr)
	return {
		rd     = bits(instr, 11, 7),
		funct3 = bits(instr, 14, 12),
		rs1    = bits(instr, 19, 15),
		imm    = sext(bits(instr, 31, 20), 12),
	}
end

-- S-type 디코드
local function decodeS(instr)
	local imm = bit32.bor(
		bit32.lshift(bits(instr, 31, 25), 5),
		bits(instr, 11, 7)
	)
	return {
		funct3 = bits(instr, 14, 12),
		rs1    = bits(instr, 19, 15),
		rs2    = bits(instr, 24, 20),
		imm    = sext(imm, 12),
	}
end

-- B-type 디코드
local function decodeB(instr)
	local imm = bit32.bor(
		bit32.lshift(bit_(instr, 31), 12),
		bit32.lshift(bit_(instr, 7),  11),
		bit32.lshift(bits(instr, 30, 25), 5),
		bit32.lshift(bits(instr, 11, 8),  1)
	)
	return {
		funct3 = bits(instr, 14, 12),
		rs1    = bits(instr, 19, 15),
		rs2    = bits(instr, 24, 20),
		imm    = sext(imm, 13),
	}
end

-- U-type 디코드
local function decodeU(instr)
	return {
		rd  = bits(instr, 11, 7),
		imm = sext(bit32.band(instr, 0xFFFFF000), 32),
	}
end

-- J-type 디코드
local function decodeJ(instr)
	local imm = bit32.bor(
		bit32.lshift(bit_(instr, 31), 20),
		bit32.lshift(bits(instr, 19, 12), 12),
		bit32.lshift(bit_(instr, 20), 11),
		bit32.lshift(bits(instr, 30, 21), 1)
	)
	return {
		rd  = bits(instr, 11, 7),
		imm = sext(imm, 21),
	}
end

-- C 확장 (16비트) 디코딩
local function decodeC(instr)
	local op    = bit32.band(instr, 3)
	local funct3 = bits(instr, 15, 13)
	return { raw = instr, cop = op, cfunct3 = funct3 }
end

function Decode.decode(instr)
	-- C 확장 확인 (하위 2비트 != 11)
	local low2 = bit32.band(instr, 3)
	if low2 ~= 3 then
		-- 16비트 압축 명령어
		return { size = 2, compressed = true, raw = bit32.band(instr, 0xFFFF),
		         cop = low2, cfunct3 = bits(instr, 15, 13) }
	end

	local op = bit32.band(instr, 0x7F)
	local d = { size = 4, op = op }

	if op == OP.LUI or op == OP.AUIPC then
		local u = decodeU(instr)
		d.rd  = u.rd
		d.imm = u.imm

	elseif op == OP.JAL then
		local j = decodeJ(instr)
		d.rd  = j.rd
		d.imm = j.imm

	elseif op == OP.JALR or op == OP.LOAD or op == OP.LOAD_FP
	    or op == OP.OP_IMM or op == OP.OP_IMM_32 or op == OP.SYSTEM
	    or op == OP.MISC_MEM then
		local i = decodeI(instr)
		d.rd = i.rd; d.funct3 = i.funct3; d.rs1 = i.rs1; d.imm = i.imm
		if (op == OP.OP_IMM or op == OP.OP_IMM_32) and
		   (i.funct3 == 1 or i.funct3 == 5) then
			-- shamt 필드
			d.shamt  = bits(instr, 25, 20)
			d.funct7 = bits(instr, 31, 26)
		end

	elseif op == OP.STORE or op == OP.STORE_FP then
		local s = decodeS(instr)
		d.funct3 = s.funct3; d.rs1 = s.rs1; d.rs2 = s.rs2; d.imm = s.imm

	elseif op == OP.BRANCH then
		local b = decodeB(instr)
		d.funct3 = b.funct3; d.rs1 = b.rs1; d.rs2 = b.rs2; d.imm = b.imm

	elseif op == OP.OP or op == OP.OP_32 or op == OP.OP_FP
	    or op == OP.AMO then
		local r = decodeR(instr)
		d.rd = r.rd; d.funct3 = r.funct3; d.rs1 = r.rs1
		d.rs2 = r.rs2; d.funct7 = r.funct7

	elseif op == OP.MADD or op == OP.MSUB or op == OP.NMADD or op == OP.NMSUB then
		-- R4-type (FMA)
		d.rd     = bits(instr, 11, 7)
		d.funct3 = bits(instr, 14, 12)
		d.rs1    = bits(instr, 19, 15)
		d.rs2    = bits(instr, 24, 20)
		d.rs3    = bits(instr, 31, 27)
		d.fmt    = bits(instr, 26, 25)
	end

	return d
end

Decode.OP   = OP
Decode.bits = bits
Decode.sext = sext

return Decode
