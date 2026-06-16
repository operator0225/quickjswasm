local CPU = require("./CPU")
print("type:", type(CPU))
print("u64:", type(CPU.u64))
if CPU.u64 then
	print("CPU.u64(-1):", CPU.u64(-1))
	print("0xFFFF..:", 0xFFFFFFFFFFFFFFFF)
	print("equal:", CPU.u64(-1) == 0xFFFFFFFFFFFFFFFF)
end
