local C = require(script.Parent.Parent.Parent.shared.Constants)

local Builtins = {}

local function write(sys, s)
	sys.write(C.STDOUT, s)
end

local function err(sys, s)
	sys.write(C.STDERR, s)
end

Builtins["cd"] = function(proc, sys, argv)
	local path = argv[2] or proc.env["HOME"] or "/home/user"
	local ok, errno = sys.chdir(path)
	if not ok then
		err(sys, "cd: " .. path .. ": No such file or directory\n")
		return 1
	end
	proc.env["PWD"] = proc.cwd
	return 0
end

Builtins["pwd"] = function(proc, sys, argv)
	write(sys, proc.cwd .. "\n")
	return 0
end

Builtins["export"] = function(proc, sys, argv)
	for i = 2, #argv do
		local k, v = argv[i]:match("^([%w_]+)=(.*)$")
		if k then
			proc.env[k] = v
		else
			-- 이미 있는 변수 export 표시 (우리 구현에서는 모두 exported)
		end
	end
	return 0
end

Builtins["unset"] = function(proc, sys, argv)
	for i = 2, #argv do
		proc.env[argv[i]] = nil
	end
	return 0
end

Builtins["echo"] = function(proc, sys, argv)
	local noNewline = false
	local escapes = false
	local i = 2
	while i <= #argv do
		if argv[i] == "-n" then noNewline = true; i += 1
		elseif argv[i] == "-e" then escapes = true; i += 1
		elseif argv[i] == "-ne" or argv[i] == "-en" then noNewline = true; escapes = true; i += 1
		else break end
	end
	local parts = {}
	for j = i, #argv do table.insert(parts, argv[j]) end
	local out = table.concat(parts, " ")
	if escapes then
		out = out:gsub("\\n","\n"):gsub("\\t","\t"):gsub("\\r","\r")
			:gsub("\\a","\a"):gsub("\\b","\b"):gsub("\\\\","\\")
	end
	write(sys, out .. (noNewline and "" or "\n"))
	return 0
end

Builtins["printf"] = function(proc, sys, argv)
	if #argv < 2 then err(sys, "printf: missing format\n"); return 1 end
	local fmt = argv[2]:gsub("\\n","\n"):gsub("\\t","\t"):gsub("\\\\","\\")
	local args = {}
	for i = 3, #argv do table.insert(args, argv[i]) end
	local ai = 0
	local out = fmt:gsub("%%(.)", function(spec)
		ai += 1
		local arg = args[ai] or ""
		if spec == "s" then return tostring(arg)
		elseif spec == "d" or spec == "i" then return tostring(math.floor(tonumber(arg) or 0))
		elseif spec == "f" then return string.format("%.6f", tonumber(arg) or 0)
		elseif spec == "%" then return "%"
		else return "%" .. spec end
	end)
	write(sys, out)
	return 0
end

Builtins["true"]  = function() return 0 end
Builtins[":"]     = function() return 0 end
Builtins["false"] = function() return 1 end

Builtins["exit"] = function(proc, sys, argv)
	local code = tonumber(argv[2]) or 0
	sys.exit(code)
	return code
end

Builtins["source"] = function(proc, sys, argv, shell)
	local path = argv[2]
	if not path then err(sys, "source: filename required\n"); return 1 end
	local content, errno = sys.open(path, {rdonly=true})
	if not content then err(sys, "source: " .. path .. ": not found\n"); return 1 end
	local data = ""
	while true do
		local chunk = sys.read(content, 4096)
		if not chunk or chunk == "" then break end
		data ..= chunk
	end
	sys.close(content)
	if shell then shell:runString(data) end
	return 0
end

Builtins["."] = Builtins["source"]

Builtins["alias"] = function(proc, sys, argv, shell)
	if not shell then return 0 end
	if #argv == 1 then
		for k, v in pairs(shell.aliases) do
			write(sys, "alias " .. k .. "='" .. v .. "'\n")
		end
		return 0
	end
	for i = 2, #argv do
		local k, v = argv[i]:match("^([%w_%-]+)=(.+)$")
		if k then shell.aliases[k] = v end
	end
	return 0
end

Builtins["unalias"] = function(proc, sys, argv, shell)
	if not shell then return 0 end
	for i = 2, #argv do
		shell.aliases[argv[i]] = nil
	end
	return 0
end

Builtins["type"] = function(proc, sys, argv, shell)
	for i = 2, #argv do
		local name = argv[i]
		if Builtins[name] then
			write(sys, name .. " is a shell builtin\n")
		elseif shell and shell.functions and shell.functions[name] then
			write(sys, name .. " is a function\n")
		else
			local found = false
			for _, dir in ipairs({"/usr/bin", "/bin"}) do
				local st = sys.stat(dir .. "/" .. name)
				if st then write(sys, name .. " is " .. dir .. "/" .. name .. "\n"); found = true; break end
			end
			if not found then err(sys, "type: " .. name .. ": not found\n") end
		end
	end
	return 0
end

Builtins["which"] = function(proc, sys, argv)
	for i = 2, #argv do
		local name = argv[i]
		for _, dir in ipairs({"/usr/bin", "/bin"}) do
			local path = dir .. "/" .. name
			local st = sys.stat(path)
			if st then write(sys, path .. "\n"); break end
		end
	end
	return 0
end

Builtins["read"] = function(proc, sys, argv)
	local varName = argv[2] or "REPLY"
	local data = sys.read(C.STDIN, 4096) or ""
	data = data:gsub("\n$", "")
	proc.env[varName] = data
	return #data > 0 and 0 or 1
end

Builtins["shift"] = function(proc, sys, argv)
	local n = tonumber(argv[2]) or 1
	for _ = 1, n do
		if #proc.argv > 1 then table.remove(proc.argv, 2) end
	end
	return 0
end

Builtins["set"] = function(proc, sys, argv)
	if #argv == 1 then
		for k, v in pairs(proc.env) do
			write(sys, k .. "=" .. tostring(v) .. "\n")
		end
	end
	return 0
end

Builtins["env"] = function(proc, sys, argv)
	for k, v in pairs(proc.env) do
		write(sys, k .. "=" .. tostring(v) .. "\n")
	end
	return 0
end

Builtins["uname"] = function(proc, sys, argv)
	local all = argv[2] == "-a"
	if all then
		write(sys, "Linux luaos 5.15.0-luaos #1 SMP Luau x86_64 GNU/Linux\n")
	else
		write(sys, "Linux\n")
	end
	return 0
end

-- test / [ / [[
local function testExpr(args)
	local n = #args
	if n == 0 then return false end
	if n == 1 then return args[1] ~= "" and args[1] ~= "0" end
	if n == 2 then
		if args[1] == "!" then return not testExpr({args[2]}) end
		if args[1] == "-n" then return #args[2] > 0 end
		if args[1] == "-z" then return #args[2] == 0 end
		if args[1] == "-e" or args[1] == "-f" or args[1] == "-d" then return true end
	end
	if n == 3 then
		local a, op, b = args[1], args[2], args[3]
		local na, nb = tonumber(a), tonumber(b)
		if op == "=" or op == "==" then return a == b
		elseif op == "!=" then return a ~= b
		elseif op == "-eq" then return na == nb
		elseif op == "-ne" then return na ~= nb
		elseif op == "-lt" then return na <  nb
		elseif op == "-le" then return na <= nb
		elseif op == "-gt" then return na >  nb
		elseif op == "-ge" then return na >= nb
		end
	end
	return false
end

Builtins["test"] = function(proc, sys, argv)
	local args = {}
	for i = 2, #argv do table.insert(args, argv[i]) end
	return testExpr(args) and 0 or 1
end
Builtins["["]  = Builtins["test"]
Builtins["[["] = Builtins["test"]

Builtins["sleep"] = function(proc, sys, argv)
	local n = tonumber(argv[2]) or 1
	sys.sleep(n)
	return 0
end

Builtins["history"] = function(proc, sys, argv, shell)
	if not shell then return 0 end
	for i, line in ipairs(shell.history or {}) do
		write(sys, string.format("%5d  %s\n", i, line))
	end
	return 0
end

Builtins["jobs"] = function(proc, sys, argv, shell)
	if not shell then return 0 end
	for id, job in pairs(shell.jobs or {}) do
		write(sys, string.format("[%d]  %s  %s\n", id, job.state, job.cmd))
	end
	return 0
end

Builtins["kill"] = function(proc, sys, argv)
	local sig = 15  -- SIGTERM
	local i = 2
	if argv[i] and argv[i]:sub(1,1) == "-" then
		sig = tonumber(argv[i]:sub(2)) or 15
		i += 1
	end
	for j = i, #argv do
		local pid = tonumber(argv[j])
		if pid then sys.kill(pid, sig) end
	end
	return 0
end

function Builtins.isBuiltin(name)
	return Builtins[name] ~= nil
end

return Builtins
