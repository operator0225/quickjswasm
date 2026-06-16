local Memory  = require("./Memory")
local CPU     = require("./CPU")
local Execute = require("./Execute")

local m = Memory.new()
local c = CPU.new(m)
c.pc = 0x1000
c:setReg(2, 0x7FFFFF00)

-- addi x10, x0, 1  → 0x00100513
m:write32(0x1000, 0x00100513)
-- addi x11, x0, 2  → 0x00200593
m:write32(0x1004, 0x00200593)
-- add x10, x10, x11 → 0x00B50533
m:write32(0x1008, 0x00B50533)
-- addi x17, x0, 93 → 0x05D00893
m:write32(0x100C, 0x05D00893)
-- ecall            → 0x00000073
m:write32(0x1010, 0x00000073)
-- 무한루프 방지: ebreak
m:write32(0x1014, 0x00100073)

local exitCode = nil
local sys = {
	write = function(fd, data)
		print("[write fd="..fd.."]", data)
		return #data
	end,
	read    = function() return "" end,
	open    = function() return nil end,
	close   = function() end,
	stat    = function() return nil end,
	readdir = function() return {} end,
	mkdir   = function() end,
	unlink  = function() end,
	rename  = function() end,
	chdir   = function() return 0 end,
	sleep   = function() end,
	getpid  = function() return 1 end,
	exit    = function(code)
		print("[exit] code=", code)
		exitCode = code
		c.running = false
	end,
}

print("실행 전: x10=", c:getReg(10), "pc=", string.format("%X", c.pc))
Execute.run(c, m, sys, 100)
print("실행 후: x10=", c:getReg(10), "x17=", c:getReg(17), "exitCode=", exitCode)
print("running=", c.running)
