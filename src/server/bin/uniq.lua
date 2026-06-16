return function(proc, sys, argv)
	local function absPath(p)
		if p:sub(1,1) == "/" then return p end
		return proc.cwd .. "/" .. p
	end

	local countMode, dupOnly, uniqOnly, caseInsensitive = false, false, false, false
	local files = {}
	local i = 2
	while i <= #argv do
		local a = argv[i]
		if a:sub(1,1) == "-" and #a > 1 then
			for j = 2, #a do
				local c = a:sub(j,j)
				if c == "c" then countMode = true
				elseif c == "d" then dupOnly = true
				elseif c == "u" then uniqOnly = true
				elseif c == "i" then caseInsensitive = true
				end
			end
		else
			files[#files+1] = a
		end
		i = i + 1
	end

	local function readAll(fd)
		local chunks = {}
		while true do
			local d = sys.read(fd, 4096); if not d or #d == 0 then break end
			chunks[#chunks+1] = d
		end
		return table.concat(chunks)
	end

	local function getLines(data)
		local lines = {}
		local pos = 1
		while pos <= #data do
			local nl = data:find("\n", pos, true)
			if nl then lines[#lines+1] = data:sub(pos, nl-1); pos = nl+1
			else
				if pos <= #data then lines[#lines+1] = data:sub(pos) end
				pos = #data+1
			end
		end
		return lines
	end

	local function process(data)
		local lines = getLines(data)
		local i2 = 1
		while i2 <= #lines do
			local line = lines[i2]
			local cmp = caseInsensitive and line:lower() or line
			local count = 1
			while i2 + count <= #lines do
				local next = lines[i2 + count]
				local ncmp = caseInsensitive and next:lower() or next
				if ncmp ~= cmp then break end
				count = count + 1
			end
			local print_it = true
			if dupOnly and count == 1 then print_it = false end
			if uniqOnly and count > 1 then print_it = false end
			if print_it then
				if countMode then
					sys.write(STDOUT, string.format("%7d %s\n", count, line))
				else
					sys.write(STDOUT, line .. "\n")
				end
			end
			i2 = i2 + count
		end
	end

	if #files == 0 then
		process(readAll(STDIN))
	else
		for _, f in ipairs(files) do
			local p = absPath(f)
			local fd, err = sys.open(p, {rdonly=true})
			if not fd then sys.write(STDERR, "uniq: " .. f .. ": " .. tostring(err) .. "\n")
			else process(readAll(fd)); sys.close(fd)
			end
		end
	end
	return 0
end
