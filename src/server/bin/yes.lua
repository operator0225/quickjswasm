return function(proc, sys, argv)
	local str = #argv > 1 and table.concat(argv, " ", 2) or "y"
	while true do
		local ok = sys.write(1, str .. "\n")
		if not ok then return 0 end
	end
end
