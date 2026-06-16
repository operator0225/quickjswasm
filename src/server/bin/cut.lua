return function(proc, sys, argv)
	local function absPath(p)
		if p:sub(1,1) == "/" then return p end
		return proc.cwd .. "/" .. p
	end

	local delim = "\t"
	local fields = nil  -- list of field indices
	local chars = nil   -- list of char indices
	local files = {}
	local i = 2
	while i <= #argv do
		local a = argv[i]
		if a == "-d" then
			i = i + 1; delim = argv[i] or "\t"
		elseif a == "-f" then
			i = i + 1; fields = argv[i]
		elseif a == "-c" then
			i = i + 1; chars = argv[i]
		elseif a:sub(1,2) == "-d" then
			delim = a:sub(3)
		elseif a:sub(1,2) == "-f" then
			fields = a:sub(3)
		elseif a:sub(1,2) == "-c" then
			chars = a:sub(3)
		elseif a ~= "-" then
			files[#files+1] = a
		else
			files[#files+1] = "-"
		end
		i = i + 1
	end

	if not fields and not chars then
		sys.write(STDERR, "cut: you must specify a list of bytes, characters, or fields\nUsage: cut -f FIELDS [-d DELIM] or cut -c CHARS [FILE...]\n")
		return 2
	end

	-- Parse field/char list like "1,3-5,7"
	local function parseList(spec)
		local result = {}
		for part in spec:gmatch("[^,]+") do
			local a2, b = part:match("^(%d+)-(%d+)$")
			if a2 then
				for n = tonumber(a2), tonumber(b) do result[#result+1] = n end
			else
				local n = tonumber(part)
				if n then result[#result+1] = n end
			end
		end
		table.sort(result)
		return result
	end

	local fieldList = fields and parseList(fields)
	local charList = chars and parseList(chars)

	local function processLine(line)
		if charList then
			local out = {}
			for _, idx in ipairs(charList) do
				if idx <= #line then out[#out+1] = line:sub(idx, idx) end
			end
			return table.concat(out)
		elseif fieldList then
			-- split by delim
			local parts = {}
			local pat = delim:gsub("([%(%)%.%%%+%-%*%?%[%^%$%]])", "%%%1")
			local pos = 1
			while true do
				local s, e = line:find(pat, pos, false)
				if s then
					parts[#parts+1] = line:sub(pos, s-1)
					pos = e+1
				else
					parts[#parts+1] = line:sub(pos)
					break
				end
			end
			local out = {}
			for _, idx in ipairs(fieldList) do
				if parts[idx] then out[#out+1] = parts[idx] end
			end
			return table.concat(out, delim)
		end
		return line
	end

	local function processData(data)
		local pos = 1
		while pos <= #data do
			local nl = data:find("\n", pos, true)
			local line
			if nl then line = data:sub(pos, nl-1); pos = nl+1
			else line = data:sub(pos); pos = #data+1
			end
			sys.write(STDOUT, processLine(line) .. "\n")
		end
	end

	local function readAll(fd)
		local chunks = {}
		while true do
			local d = sys.read(fd, 4096); if not d or #d == 0 then break end
			chunks[#chunks+1] = d
		end
		return table.concat(chunks)
	end

	if #files == 0 then
		processData(readAll(STDIN))
	else
		for _, f in ipairs(files) do
			if f == "-" then
				processData(readAll(STDIN))
			else
				local p = absPath(f)
				local fd, err = sys.open(p, {rdonly=true})
				if not fd then sys.write(STDERR, "cut: " .. f .. ": " .. tostring(err) .. "\n")
				else processData(readAll(fd)); sys.close(fd)
				end
			end
		end
	end
	return 0
end
