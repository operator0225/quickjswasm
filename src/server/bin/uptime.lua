return function(proc, sys, argv)
	local data = sys.read(sys.open("/proc/uptime", {rdonly=true}), 256) or "0 0"
	local up = tonumber(data:match("^([%d%.]+)")) or 0
	local h = math.floor(up / 3600)
	local m = math.floor((up % 3600) / 60)
	sys.write(1, string.format(" up %d:%02d,  1 user,  load average: 0.00, 0.00, 0.00\n", h, m))
	return 0
end
