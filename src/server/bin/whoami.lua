return function(proc, sys, argv)
	sys.write(1, (proc.env["USER"] or "user") .. "\n")
	return 0
end
