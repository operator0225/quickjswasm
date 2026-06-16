return function(proc, sys, argv)
	if #argv > 1 then
		for i = 2, #argv do
			local v = proc.env[argv[i]]
			if v then sys.write(1, v .. "\n") end
		end
	else
		for k, v in pairs(proc.env) do
			sys.write(1, k .. "=" .. tostring(v) .. "\n")
		end
	end
	return 0
end
