return function(proc, sys, argv)
	local append = false
	local files = {}
	for i = 2, #argv do
		if argv[i] == "-a" then append = true
		else table.insert(files, argv[i]) end
	end
	local fds = {}
	for _, f in ipairs(files) do
		local fd = sys.open(f, { create = true, append = append })
		if fd then table.insert(fds, fd) end
	end
	while true do
		local data = sys.read(0, 65536)
		if not data or data == "" then break end
		sys.write(1, data)
		for _, fd in ipairs(fds) do sys.write(fd, data) end
	end
	for _, fd in ipairs(fds) do sys.close(fd) end
	return 0
end
