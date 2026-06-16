return function(proc, sys, argv)
	local human = false
	local paths = {}
	for i = 2, #argv do
		if argv[i] == "-h" then human = true
		elseif argv[i]:sub(1,1) ~= "-" then table.insert(paths, argv[i])
		end
	end
	if #paths == 0 then table.insert(paths, proc.cwd) end

	local function fmt(n)
		if human then
			if n > 1024*1024 then return string.format("%.1fG", n/1024/1024/1024)
			elseif n > 1024 then return string.format("%.1fM", n/1024/1024)
			elseif n > 0 then return string.format("%.1fK", n/1024)
			else return "0" end
		end
		return tostring(math.ceil(n/1024))
	end

	local function duDir(path)
		local total = 0
		local entries = sys.readdir(path)
		if entries then
			for _, e in ipairs(entries) do
				local fp = path == "/" and ("/"..e) or (path.."/"..e)
				local st = sys.stat(fp)
				if st then total += st.size or 0 end
			end
		end
		sys.write(1, fmt(total) .. "\t" .. path .. "\n")
		return total
	end

	for _, p in ipairs(paths) do duDir(p) end
	return 0
end
