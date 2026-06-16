return function(proc, sys, argv)
	local function absPath(p)
		if p:sub(1,1) == "/" then return p end
		return proc.cwd .. "/" .. p
	end

	local symbolic, force = false, false
	local args = {}
	local i = 2
	while i <= #argv do
		local a = argv[i]
		if a:sub(1,1) == "-" and #a > 1 then
			for j = 2, #a do
				local c = a:sub(j,j)
				if c == "s" then symbolic = true
				elseif c == "f" then force = true
				end
			end
		else
			args[#args+1] = a
		end
		i = i + 1
	end

	if #args < 2 then
		sys.write(STDERR, "ln: missing file operand\nUsage: ln [-sf] TARGET LINK_NAME\n")
		return 2
	end

	local target = args[1]
	local linkPath = absPath(args[2])

	-- If linkPath is an existing directory, put link inside it
	local linkSt = sys.stat(linkPath)
	if linkSt then
		local ftype = linkSt.mode - (linkSt.mode % 0o10000)
		if ftype == 0o040000 then
			local base = target:match("([^/]+)$") or target
			linkPath = linkPath:gsub("/$","") .. "/" .. base
			linkSt = sys.stat(linkPath)
		end
	end

	if linkSt then
		if not force then
			sys.write(STDERR, "ln: failed to create link '" .. args[2] .. "': File exists\n")
			return 1
		end
		local _, err = sys.unlink(linkPath)
		if err then
			sys.write(STDERR, "ln: cannot remove '" .. args[2] .. "': " .. tostring(err) .. "\n")
			return 1
		end
	end

	if symbolic then
		-- target is used as-is (relative or absolute) for symlink
		local _, err = sys.symlink(target, linkPath)
		if err then
			sys.write(STDERR, "ln: failed to create symbolic link '" .. args[2] .. "': " .. tostring(err) .. "\n")
			return 1
		end
	else
		-- Hard link: copy file content (FS doesn't support true hard links)
		local srcPath = absPath(target)
		local srcSt, err = sys.stat(srcPath)
		if not srcSt then
			sys.write(STDERR, "ln: cannot stat '" .. target .. "': " .. tostring(err) .. "\n")
			return 1
		end
		local srcFd, e1 = sys.open(srcPath, {rdonly=true})
		if not srcFd then
			sys.write(STDERR, "ln: cannot open '" .. target .. "': " .. tostring(e1) .. "\n")
			return 1
		end
		local dstFd, e2 = sys.open(linkPath, {create=true})
		if not dstFd then
			sys.close(srcFd)
			sys.write(STDERR, "ln: cannot create '" .. args[2] .. "': " .. tostring(e2) .. "\n")
			return 1
		end
		while true do
			local data = sys.read(srcFd, 4096)
			if not data or #data == 0 then break end
			sys.write(dstFd, data)
		end
		sys.close(srcFd)
		sys.close(dstFd)
		sys.write(STDERR, "ln: warning: hard links not supported; copied file instead\n")
	end
	return 0
end
