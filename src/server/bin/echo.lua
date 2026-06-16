return function(proc, sys, argv)
	local noNewline = false
	local interpEscapes = false
	local args = {}
	local i = 2
	-- Parse flags (only at start, like real echo)
	local parsing = true
	while i <= #argv do
		local a = argv[i]
		if parsing and a:sub(1,1) == "-" and #a > 1 then
			local allFlags = true
			for j = 2, #a do
				local c = a:sub(j,j)
				if c ~= "n" and c ~= "e" and c ~= "E" then allFlags = false; break end
			end
			if allFlags then
				for j = 2, #a do
					local c = a:sub(j,j)
					if c == "n" then noNewline = true
					elseif c == "e" then interpEscapes = true
					elseif c == "E" then interpEscapes = false
					end
				end
			else
				parsing = false
				args[#args+1] = a
			end
		else
			parsing = false
			args[#args+1] = a
		end
		i = i + 1
	end

	local out = table.concat(args, " ")

	if interpEscapes then
		out = out:gsub("\\(.)", function(c)
			if c == "n" then return "\n"
			elseif c == "t" then return "\t"
			elseif c == "r" then return "\r"
			elseif c == "a" then return "\a"
			elseif c == "b" then return "\b"
			elseif c == "f" then return "\f"
			elseif c == "v" then return "\v"
			elseif c == "\\" then return "\\"
			elseif c == "0" then return "\0"
			elseif c == "e" then return "\27"
			else return "\\" .. c
			end
		end)
	end

	sys.write(STDOUT, out)
	if not noNewline then sys.write(STDOUT, "\n") end
	return 0
end
