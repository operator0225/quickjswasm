return function(proc, sys, argv)
	local SM = require(script.Parent.Parent.StorageManager)
	sys.write(1, string.format("%-20s %10s %10s %10s %5s %s\n",
		"Filesystem", "1K-blocks", "Used", "Available", "Use%", "Mounted on"))

	local meta = SM.getMeta(proc.uid >= 1000 and (proc.uid - 1000) or proc.uid)
	if meta and meta.usedSectors then
		local used = 0
		for _ in pairs(meta.usedSectors) do used += 1 end
		local total = 256
		local avail = total - used
		local pct   = math.floor(used / total * 100)
		sys.write(1, string.format("%-20s %10d %10d %10d %4d%% %s\n",
			"/dev/sda1", total*4096, used*4096, avail*4096, pct, "/"))
	end
	sys.write(1, string.format("%-20s %10d %10d %10d %4d%% %s\n",
		"tmpfs", 65536, 0, 65536, 0, "/tmp"))
	sys.write(1, string.format("%-20s %10s %10s %10s %4s  %s\n",
		"proc", "-", "-", "-", "-", "/proc"))
	return 0
end
