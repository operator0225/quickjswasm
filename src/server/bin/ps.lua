return function(proc, sys, argv)
	local PT = require(script.Parent.Parent.kernel.ProcessTable)
	local showAll = false
	for i = 2, #argv do
		if argv[i] == "-a" or argv[i] == "-e" or argv[i] == "aux" or argv[i] == "-aux" then
			showAll = true
		end
	end

	sys.write(1, string.format("%-6s %-6s %-10s %-8s %s\n", "PID", "PPID", "STATE", "UID", "COMMAND"))
	for pid, p in pairs(PT.all()) do
		if showAll or p.uid == proc.uid then
			sys.write(1, string.format("%-6d %-6d %-10s %-8d %s\n",
				p.pid, p.ppid, p.state, p.uid, p.name))
		end
	end
	return 0
end
