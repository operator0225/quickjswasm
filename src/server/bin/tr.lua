return function(proc, sys, argv)
	local deleteMode, squeezeMode, complementMode = false, false, false
	local set1, set2 = nil, nil
	local i = 2
	while i <= #argv do
		local a = argv[i]
		if a:sub(1,1) == "-" and #a > 1 then
			for j = 2, #a do
				local c = a:sub(j,j)
				if c == "d" then deleteMode = true
				elseif c == "s" then squeezeMode = true
				elseif c == "c" then complementMode = true
				end
			end
		else
			if not set1 then set1 = a
			elseif not set2 then set2 = a
			end
		end
		i = i + 1
	end

	if not set1 then
		sys.write(STDERR, "tr: missing operand\nUsage: tr [-dsc] SET1 [SET2]\n")
		return 2
	end

	-- Expand escape sequences and ranges in a set
	local function expandSet(s)
		if not s then return {} end
		local chars = {}
		local i2 = 1
		while i2 <= #s do
			local c = s:sub(i2,i2)
			if c == "\\" then
				i2 = i2 + 1
				local nc = s:sub(i2,i2)
				if nc == "n" then chars[#chars+1] = "\n"
				elseif nc == "t" then chars[#chars+1] = "\t"
				elseif nc == "r" then chars[#chars+1] = "\r"
				elseif nc == "a" then chars[#chars+1] = "\a"
				elseif nc == "\\" then chars[#chars+1] = "\\"
				elseif nc == "0" then chars[#chars+1] = "\0"
				else chars[#chars+1] = nc
				end
			elseif i2+2 <= #s and s:sub(i2+1,i2+1) == "-" then
				-- range
				local from = c:byte()
				local to = s:sub(i2+2,i2+2):byte()
				if from <= to then
					for b = from, to do chars[#chars+1] = string.char(b) end
				else
					chars[#chars+1] = c
				end
				i2 = i2 + 2
			else
				chars[#chars+1] = c
			end
			i2 = i2 + 1
		end
		return chars
	end

	local expanded1 = expandSet(set1)
	local expanded2 = set2 and expandSet(set2) or {}

	-- Build translation/deletion sets
	local deleteSet = {}
	local transMap = {}

	if complementMode then
		-- complement: build set of all chars NOT in set1
		local inSet1 = {}
		for _, c in ipairs(expanded1) do inSet1[c] = true end
		local compSet = {}
		for b = 0, 255 do
			local c = string.char(b)
			if not inSet1[c] then compSet[#compSet+1] = c end
		end
		expanded1 = compSet
	end

	if deleteMode then
		for _, c in ipairs(expanded1) do deleteSet[c] = true end
	else
		-- build translation map
		for idx, c in ipairs(expanded1) do
			local to = expanded2[idx] or expanded2[#expanded2]
			if to then transMap[c] = to end
		end
	end

	-- Process stdin
	local function processChunk(data)
		local out = {}
		local lastChar = nil
		for p = 1, #data do
			local c = data:sub(p,p)
			if deleteMode then
				if not deleteSet[c] then
					if squeezeMode then
						if c ~= lastChar then out[#out+1] = c; lastChar = c end
					else
						out[#out+1] = c
					end
				end
			else
				local mapped = transMap[c] or c
				if squeezeMode and mapped == lastChar and transMap[c] then
					-- squeeze: skip repeated translated chars
				else
					out[#out+1] = mapped
					lastChar = mapped
				end
			end
		end
		return table.concat(out)
	end

	while true do
		local data = sys.read(STDIN, 4096)
		if not data or #data == 0 then break end
		sys.write(STDOUT, processChunk(data))
	end
	return 0
end
