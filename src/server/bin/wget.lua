-- wget: curl의 별칭
return function(proc, sys, argv)
	local url    = nil
	local output = nil

	for i = 2, #argv do
		if argv[i] == "-O" then
			output = argv[i+1]
		elseif argv[i]:sub(1,1) ~= "-" then
			url = argv[i]
		end
	end

	if not url then sys.write(2, "wget: missing URL\n"); return 1 end

	sys.write(1, "--" .. os.date("%Y-%m-%dT%H:%M:%S") .. "--  " .. url .. "\n")
	sys.write(1, "Resolving host...\n")

	local ok, result = pcall(function()
		return game:GetService("HttpService"):RequestAsync({ Url = url, Method = "GET" })
	end)

	if not ok then
		sys.write(2, "wget: " .. tostring(result) .. "\n")
		return 1
	end

	local body = result.Body or ""
	local fname = output or url:match("[^/]+$") or "index.html"
	sys.write(1, "Saving to: '" .. fname .. "'\n")
	sys.write(1, string.format("'%s' saved [%d]\n", fname, #body))

	local fd = sys.open(fname, { create = true })
	if fd then sys.write(fd, body); sys.close(fd) end

	return 0
end
