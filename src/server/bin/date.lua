return function(proc, sys, argv)
	local fmt = argv[2] and argv[2]:sub(1,1) == "+" and argv[2]:sub(2) or "%Y-%m-%d %H:%M:%S %Z"
	local t = os.date("*t", os.time())
	local out = fmt
		:gsub("%%Y", string.format("%04d", t.year))
		:gsub("%%m", string.format("%02d", t.month))
		:gsub("%%d", string.format("%02d", t.day))
		:gsub("%%H", string.format("%02d", t.hour))
		:gsub("%%M", string.format("%02d", t.min))
		:gsub("%%S", string.format("%02d", t.sec))
		:gsub("%%Z", "UTC")
		:gsub("%%n", "\n")
	sys.write(1, out .. "\n")
	return 0
end
