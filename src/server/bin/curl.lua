-- curl: HttpService 래퍼 (서버 사이드에서만 동작)
return function(proc, sys, argv)
	local url     = nil
	local method  = "GET"
	local headers = {}
	local body    = nil
	local silent  = false
	local output  = nil

	local i = 2
	while i <= #argv do
		local a = argv[i]
		if a == "-s" or a == "--silent" then silent = true
		elseif a == "-X" then i += 1; method = argv[i] or "GET"
		elseif a == "-H" then
			i += 1
			local h = argv[i] or ""
			local k, v = h:match("^([^:]+):%s*(.+)$")
			if k then headers[k] = v end
		elseif a == "-d" then i += 1; body = argv[i]
		elseif a == "-o" then i += 1; output = argv[i]
		elseif a:sub(1,1) ~= "-" then url = a
		end
		i += 1
	end

	if not url then
		sys.write(2, "curl: no URL specified\n")
		return 1
	end

	local ok, result = pcall(function()
		local HS = game:GetService("HttpService")
		return HS:RequestAsync({
			Url     = url,
			Method  = method,
			Headers = headers,
			Body    = body,
		})
	end)

	if not ok then
		sys.write(2, "curl: " .. tostring(result) .. "\n")
		return 1
	end

	if not silent then
		local responseBody = result.Body or ""
		if output then
			sys.write(sys.open(output, {create=true}) or 1, responseBody)
		else
			sys.write(1, responseBody)
		end
	end

	return (result.StatusCode and result.StatusCode >= 200 and result.StatusCode < 300) and 0 or 1
end
