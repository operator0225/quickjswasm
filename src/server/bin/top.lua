return function(proc, sys, argv)
	local PT = require(script.Parent.Parent.kernel.ProcessTable)
	local iters = tonumber(argv[2]) or 5

	for iter = 1, iters do
		-- 화면 지우기 (ANSI)
		sys.write(1, "\27[2J\27[H")
		sys.write(1, "\27[1;36mtop - LuaOS Process Monitor\27[0m\n\n")
		sys.write(1, string.format("%-6s %-6s %-10s %-8s %-10s %s\n",
			"PID", "PPID", "STATE", "UID", "CPU%", "COMMAND"))
		sys.write(1, string.rep("-", 60) .. "\n")

		for pid, p in pairs(PT.all()) do
			sys.write(1, string.format("%-6d %-6d %-10s %-8d %-10.1f %s\n",
				p.pid, p.ppid, p.state, p.uid, math.random(0, 100)/10, p.name))
		end

		sys.write(1, "\n[" .. iter .. "/" .. iters .. "] q to quit\n")
		sys.sleep(2)
	end
	return 0
end
