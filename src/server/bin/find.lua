return function(proc, sys, argv)
	local function absPath(p)
		if p:sub(1,1) == "/" then return p end
		return proc.cwd .. "/" .. p
	end

	-- Parse arguments
	local startPaths = {}
	local tests = {}
	local maxdepth = math.huge
	local i = 2

	-- Collect start paths (args before first -)
	while i <= #argv do
		local a = argv[i]
		if a:sub(1,1) ~= "-" and #tests == 0 then
			startPaths[#startPaths+1] = a
		else
			break
		end
		i = i + 1
	end
	if #startPaths == 0 then startPaths[1] = "." end

	-- Parse tests/actions
	while i <= #argv do
		local a = argv[i]
		if a == "-name" then
			i = i + 1
			local pat = argv[i]
			-- convert glob to lua pattern
			local luapat = pat:gsub("([%(%)%.%%%+%-%*%?%[%^%$%]])", function(c)
				if c == "*" then return ".*"
				elseif c == "?" then return "."
				else return "%" .. c
				end
			end)
			-- actually * in glob should be [^/]* but we treat simply
			luapat = pat:gsub("%.", "%%."):gsub("%*", ".*"):gsub("%?", ".")
			tests[#tests+1] = {type="name", pat=luapat}
		elseif a == "-type" then
			i = i + 1; tests[#tests+1] = {type="type", val=argv[i]}
		elseif a == "-size" then
			i = i + 1
			local spec = argv[i]
			local sign = spec:sub(1,1)
			local num = tonumber(spec:gsub("[^%d]","")) or 0
			-- size in 512-byte blocks by default, c = bytes
			local bytes = spec:sub(-1) == "c" and num or num*512
			tests[#tests+1] = {type="size", sign=sign, bytes=bytes}
		elseif a == "-newer" then
			i = i + 1
			local refPath = absPath(argv[i])
			local refSt = sys.stat(refPath)
			local refTime = refSt and refSt.mtime or 0
			tests[#tests+1] = {type="newer", refTime=refTime}
		elseif a == "-maxdepth" then
			i = i + 1; maxdepth = tonumber(argv[i]) or 0
		elseif a == "-print" then
			tests[#tests+1] = {type="print"}
		elseif a == "-exec" then
			-- collect until \;
			local cmd = {}
			i = i + 1
			while i <= #argv and argv[i] ~= ";" do
				cmd[#cmd+1] = argv[i]; i = i + 1
			end
			tests[#tests+1] = {type="exec", cmd=cmd}
		end
		i = i + 1
	end

	local function matchTests(path, name, st)
		for _, t in ipairs(tests) do
			if t.type == "name" then
				if not name:match("^" .. t.pat .. "$") then return false end
			elseif t.type == "type" then
				if not st then return false end
				local ftype = st.mode - (st.mode % 0o10000)
				if t.val == "f" and ftype ~= 0o100000 then return false end
				if t.val == "d" and ftype ~= 0o040000 then return false end
				if t.val == "l" and ftype ~= 0o120000 then return false end
			elseif t.type == "size" then
				if not st then return false end
				local sz = st.size or 0
				if t.sign == "+" and sz <= t.bytes then return false end
				if t.sign == "-" and sz >= t.bytes then return false end
				if t.sign ~= "+" and t.sign ~= "-" and sz ~= t.bytes then return false end
			elseif t.type == "newer" then
				if not st then return false end
				if (st.mtime or 0) <= t.refTime then return false end
			end
		end
		return true
	end

	local function hasAction()
		for _, t in ipairs(tests) do
			if t.type == "print" or t.type == "exec" then return true end
		end
		return false
	end
	local defaultPrint = not hasAction()

	local function doActions(path)
		for _, t in ipairs(tests) do
			if t.type == "print" or defaultPrint then
				sys.write(STDOUT, path .. "\n")
				if not defaultPrint then break end
			end
			if t.type == "exec" then
				-- substitute {} with path
				-- In this environment we can't actually exec; just print the command
				local parts = {}
				for _, p in ipairs(t.cmd) do
					parts[#parts+1] = p == "{}" and path or p
				end
				sys.write(STDOUT, "[exec] " .. table.concat(parts, " ") .. "\n")
			end
		end
		if defaultPrint then sys.write(STDOUT, path .. "\n") end
	end

	local function walk(path, depth)
		if depth > maxdepth then return end
		local st = sys.stat(path)
		local name = path:match("([^/]+)$") or path
		if matchTests(path, name, st) then
			doActions(path)
		end
		if st then
			local ftype = st.mode - (st.mode % 0o10000)
			if ftype == 0o040000 then
				local names = sys.readdir(path)
				if names then
					for _, n in ipairs(names) do
						if n ~= "." and n ~= ".." then
							walk(path:gsub("/$","") .. "/" .. n, depth+1)
						end
					end
				end
			end
		end
	end

	for _, sp in ipairs(startPaths) do
		walk(absPath(sp), 0)
	end
	return 0
end
