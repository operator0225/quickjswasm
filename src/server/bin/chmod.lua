return function(proc, sys, argv)
	local function absPath(p)
		if p:sub(1,1) == "/" then return p end
		return proc.cwd .. "/" .. p
	end

	local recursive = false
	local modeSpec = nil
	local files = {}
	local i = 2
	while i <= #argv do
		local a = argv[i]
		if a == "-R" or a == "-r" then
			recursive = true
		elseif a:sub(1,1) == "-" and a:sub(2):match("^%d") then
			-- skip
		elseif not modeSpec then
			modeSpec = a
		else
			files[#files+1] = a
		end
		i = i + 1
	end

	if not modeSpec or #files == 0 then
		sys.write(STDERR, "chmod: missing operand\nUsage: chmod [-R] MODE FILE...\n")
		return 2
	end

	-- Parse octal mode
	local function parseOctal(s)
		local n = tonumber(s, 8)
		return n
	end

	-- Parse symbolic mode like u+x, go-w, a=rw
	local function parseSymbolic(spec, currentMode)
		local newMode = currentMode
		for part in spec:gmatch("[^,]+") do
			local who, op, perms = part:match("^([ugoa]*)([%+%-%=])([rwxst]*)$")
			if not who then
				return nil, "invalid mode: " .. spec
			end
			local bits = 0
			for p in perms:gmatch(".") do
				if p == "r" then bits = bits + 0o444
				elseif p == "w" then bits = bits + 0o222
				elseif p == "x" then bits = bits + 0o111
				elseif p == "s" then bits = bits + 0o6000
				elseif p == "t" then bits = bits + 0o1000
				end
			end
			-- filter by who
			if who == "" or who == "a" then who = "ugo" end
			local mask = 0
			if who:find("u") then mask = mask + (bits % 0o1000 - bits % 0o100) + math.floor(bits / 0o1000) * 0o1000 end
			if who:find("g") then mask = mask + (math.floor(bits / 0o10) % 0o10) * 0o10 end
			if who:find("o") then mask = mask + bits % 0o10 end

			if op == "+" then newMode = newMode + (mask - (newMode % (mask*2+1) >= mask and mask or 0))
			elseif op == "-" then newMode = newMode % (0o10000) -- simplified
			elseif op == "=" then
				-- clear bits for 'who' and set new
				newMode = newMode -- simplified
			end
		end
		return newMode
	end

	local function applyChmod(path)
		local st, err = sys.stat(path)
		if not st then
			sys.write(STDERR, "chmod: cannot access '" .. path .. "': " .. tostring(err) .. "\n")
			return 1
		end

		local newMode
		local octal = parseOctal(modeSpec)
		if octal then
			newMode = (st.mode - (st.mode % 0o10000)) + octal
		else
			local m, merr = parseSymbolic(modeSpec, st.mode)
			if not m then
				sys.write(STDERR, "chmod: invalid mode '" .. modeSpec .. "': " .. tostring(merr) .. "\n")
				return 1
			end
			newMode = m
		end

		-- VFS limitation: we can't directly set mode on an inode from userspace here.
		-- In a real implementation, there would be a sys.chmod(path, mode) call.
		-- For now, acknowledge the intent:
		sys.write(STDERR, "chmod: note: mode change to " .. string.format("%o", newMode % 0o10000) .. " on '" .. path .. "' (VFS chmod not fully implemented)\n")

		if recursive then
			local ftype = st.mode - (st.mode % 0o10000)
			if ftype == 0o040000 then
				local names = sys.readdir(path)
				if names then
					for _, name in ipairs(names) do
						if name ~= "." and name ~= ".." then
							applyChmod(path:gsub("/$","") .. "/" .. name)
						end
					end
				end
			end
		end
		return 0
	end

	local rc = 0
	for _, f in ipairs(files) do
		local r = applyChmod(absPath(f))
		if r ~= 0 then rc = r end
	end
	return rc
end
