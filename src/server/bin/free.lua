return function(proc, sys, argv)
	local h = argv[2] == "-h"
	local function fmt(n)
		if h then
			if n > 1024*1024 then return string.format("%.1fG", n/1024/1024)
			elseif n > 1024 then return string.format("%.1fM", n/1024)
			else return n.."K" end
		end
		return tostring(n)
	end
	sys.write(1, string.format("%14s %12s %12s %12s %12s %12s\n",
		"", "total", "used", "free", "shared", "available"))
	sys.write(1, string.format("%-14s %12s %12s %12s %12s %12s\n",
		"Mem:", fmt(1048576), fmt(524288), fmt(524288), fmt(0), fmt(786432)))
	sys.write(1, string.format("%-14s %12s %12s %12s\n",
		"Swap:", fmt(0), fmt(0), fmt(0)))
	return 0
end
