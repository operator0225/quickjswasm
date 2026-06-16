local C        = require(script.Parent.Parent.Parent.shared.Constants)
local AST      = require(script.Parent.AST)
local Expander = require(script.Parent.Expander)
local Builtins = require(script.Parent.Builtins)
local FDT      = require(script.Parent.Parent.kernel.FDTable)

local Executor = {}

local BREAK_SIGNAL    = {}
local CONTINUE_SIGNAL = {}
local RETURN_SIGNAL   = {}

local function applyRedirects(proc, sys, redirs)
	local saved = {}
	for _, r in ipairs(redirs) do
		local target = Expander.expandOne(r.target, proc, sys)
		if r.op == ">" then
			local oldFd = proc.fdTable[C.STDOUT] and C.STDOUT
			if oldFd then saved[C.STDOUT] = proc.fdTable[C.STDOUT] end
			local fd = sys.open(target, { create=true })
			if fd then sys.dup2(fd, C.STDOUT); sys.close(fd) end
		elseif r.op == ">>" then
			if proc.fdTable[C.STDOUT] then saved[C.STDOUT] = proc.fdTable[C.STDOUT] end
			local fd = sys.open(target, { create=true, append=true })
			if fd then sys.dup2(fd, C.STDOUT); sys.close(fd) end
		elseif r.op == "<" then
			if proc.fdTable[C.STDIN] then saved[C.STDIN] = proc.fdTable[C.STDIN] end
			local fd = sys.open(target, { rdonly=true })
			if fd then sys.dup2(fd, C.STDIN); sys.close(fd) end
		elseif r.op == "2>" then
			if proc.fdTable[C.STDERR] then saved[C.STDERR] = proc.fdTable[C.STDERR] end
			local fd = sys.open(target, { create=true })
			if fd then sys.dup2(fd, C.STDERR); sys.close(fd) end
		elseif r.op == "2>>" then
			if proc.fdTable[C.STDERR] then saved[C.STDERR] = proc.fdTable[C.STDERR] end
			local fd = sys.open(target, { create=true, append=true })
			if fd then sys.dup2(fd, C.STDERR); sys.close(fd) end
		elseif r.op == "&>" then
			if proc.fdTable[C.STDOUT] then saved[C.STDOUT] = proc.fdTable[C.STDOUT] end
			if proc.fdTable[C.STDERR] then saved[C.STDERR] = proc.fdTable[C.STDERR] end
			local fd = sys.open(target, { create=true })
			if fd then sys.dup2(fd, C.STDOUT); sys.dup2(fd, C.STDERR); sys.close(fd) end
		end
	end
	return saved
end

local function restoreRedirects(proc, sys, saved)
	for fd, slot in pairs(saved) do
		proc.fdTable[fd] = slot
	end
end

local function loadProgram(sys, name)
	-- /usr/bin 또는 /bin 에서 로드
	for _, dir in ipairs({ "/usr/bin", "/bin" }) do
		local path = dir .. "/" .. name
		local fd = sys.open(path, { rdonly = true })
		if fd then
			local src = ""
			while true do
				local chunk = sys.read(fd, 65536)
				if not chunk or chunk == "" then break end
				src ..= chunk
			end
			sys.close(fd)
			local fn, err = loadstring("return " .. src)
			if not fn then fn, err = loadstring(src) end
			if fn then
				local ok, result = pcall(fn)
				if ok and type(result) == "function" then return result end
			end
			break
		end
	end
	return nil
end

local function execSimpleCmd(node, proc, sys, shell)
	if #node.words == 0 then
		-- 리다이렉션만 있는 경우
		local saved = applyRedirects(proc, sys, node.redirs)
		restoreRedirects(proc, sys, saved)
		return 0
	end

	local expanded = Expander.expand(node.words, proc, sys)
	if #expanded == 0 then return 0 end

	local cmdName = expanded[1]
	local argv    = expanded

	-- 앨리아스 확인
	if shell and shell.aliases[cmdName] then
		local aliased = shell.aliases[cmdName]
		-- 재귀 방지: 앨리아스 이름이 같으면 그냥 사용
		if aliased ~= cmdName then
			local Lexer  = require(script.Parent.Lexer)
			local Parser = require(script.Parent.Parser)
			local newInput = aliased .. " " .. table.concat(argv, " ", 2)
			local tokens = Lexer.tokenize(newInput)
			local ast    = Parser.parse(tokens)
			if ast then return Executor.execute(ast, proc, sys, shell) end
		end
	end

	-- 셸 함수 확인
	if shell and shell.functions and shell.functions[cmdName] then
		local saved = applyRedirects(proc, sys, node.redirs)
		local oldArgv = proc.argv
		proc.argv = argv
		local code = Executor.execute(shell.functions[cmdName], proc, sys, shell)
		proc.argv = oldArgv
		restoreRedirects(proc, sys, saved)
		return code
	end

	-- 빌트인 확인
	if Builtins[cmdName] then
		local saved = applyRedirects(proc, sys, node.redirs)
		local code = Builtins[cmdName](proc, sys, argv, shell)
		restoreRedirects(proc, sys, saved)
		return code or 0
	end

	-- 외부 명령어 로드
	local progFn = loadProgram(sys, cmdName)
		or loadProgram(sys, cmdName:match("[^/]+$") or cmdName)

	if not progFn then
		sys.write(C.STDERR, cmdName .. ": command not found\n")
		return 127
	end

	-- fork + exec
	local Syscall = require(script.Parent.Parent.kernel.Syscall)
	local Sched   = require(script.Parent.Parent.kernel.Scheduler)
	local PT      = require(script.Parent.Parent.kernel.ProcessTable)

	local exitCode = 0
	local saved = applyRedirects(proc, sys, node.redirs)

	local childPid = sys.fork(function(child)
		child.argv = argv
		local sc = Syscall.bind(child)
		local ok, code = pcall(progFn, child, sc, argv)
		if not ok then
			sc.write(C.STDERR, tostring(code) .. "\n")
			sc.exit(1)
		else
			sc.exit(type(code) == "number" and code or 0)
		end
	end)

	if childPid then
		exitCode = sys.waitpid(childPid) or 0
	end

	restoreRedirects(proc, sys, saved)
	return exitCode
end

function Executor.execute(node, proc, sys, shell)
	if not node then return 0 end

	local t = node.type

	if t == AST.Error then
		sys.write(C.STDERR, "syntax error: " .. (node.msg or "unknown") .. "\n")
		return 2

	elseif t == AST.SimpleCmd then
		return execSimpleCmd(node, proc, sys, shell)

	elseif t == AST.Pipeline then
		local cmds = node.cmds
		if #cmds == 1 then
			return Executor.execute(cmds[1], proc, sys, shell)
		end

		-- 파이프 생성
		local Pipe = require(script.Parent.Parent.kernel.Pipe)
		local pipes = {}
		for i = 1, #cmds - 1 do
			table.insert(pipes, Pipe.new())
		end

		local Syscall = require(script.Parent.Parent.kernel.Syscall)
		local pids = {}

		for i, cmd in ipairs(cmds) do
			local childPid = sys.fork(function(child)
				local sc = Syscall.bind(child)
				-- stdin을 이전 파이프에서
				if i > 1 then
					local rVn = {
						read = function(n) return Pipe.read(pipes[i-1], n) end,
						write = function() end,
						close = function() Pipe.closeRead(pipes[i-1]) end,
						type = "pipe_r",
					}
					FDT.allocAt(child, C.STDIN, rVn)
				end
				-- stdout을 다음 파이프로
				if i < #cmds then
					local wVn = {
						read = function() end,
						write = function(data)
							Pipe.write(pipes[i], data)
							return #data
						end,
						close = function() Pipe.closeWrite(pipes[i]) end,
						type = "pipe_w",
					}
					FDT.allocAt(child, C.STDOUT, wVn)
				end
				local code = Executor.execute(cmd, child, sc, shell)
				sc.exit(code or 0)
			end)
			table.insert(pids, childPid)
		end

		-- 파이프 write 끝 닫기
		for _, p in ipairs(pipes) do Pipe.closeWrite(p) end

		local lastCode = 0
		for _, pid in ipairs(pids) do
			lastCode = sys.waitpid(pid) or 0
		end

		if node.negate then lastCode = lastCode == 0 and 1 or 0 end
		return lastCode

	elseif t == AST.List then
		local leftCode = Executor.execute(node.left, proc, sys, shell)
		proc.env["?"] = tostring(leftCode)
		if node.op == ";" then
			return Executor.execute(node.right, proc, sys, shell)
		elseif node.op == "&&" then
			if leftCode == 0 then return Executor.execute(node.right, proc, sys, shell) end
			return leftCode
		elseif node.op == "||" then
			if leftCode ~= 0 then return Executor.execute(node.right, proc, sys, shell) end
			return leftCode
		end

	elseif t == AST.Background then
		local Syscall = require(script.Parent.Parent.kernel.Syscall)
		local pid = sys.fork(function(child)
			local sc = Syscall.bind(child)
			local code = Executor.execute(node.cmd, child, sc, shell)
			sc.exit(code or 0)
		end)
		if shell and pid then
			local jobId = (shell._nextJob or 0) + 1
			shell._nextJob = jobId
			shell.jobs = shell.jobs or {}
			shell.jobs[jobId] = { pid = pid, state = "Running", cmd = node.cmd.words and table.concat(node.cmd.words, " ") or "?" }
			sys.write(C.STDOUT, "[" .. jobId .. "] " .. pid .. "\n")
		end
		return 0

	elseif t == AST.If then
		local condCode = Executor.execute(node.cond, proc, sys, shell)
		if condCode == 0 then
			return Executor.execute(node.then_body, proc, sys, shell)
		end
		for _, clause in ipairs(node.elseif_clauses or {}) do
			local cc = Executor.execute(clause.cond, proc, sys, shell)
			if cc == 0 then return Executor.execute(clause.body, proc, sys, shell) end
		end
		if node.else_body then
			return Executor.execute(node.else_body, proc, sys, shell)
		end
		return 0

	elseif t == AST.While then
		while true do
			local condCode = Executor.execute(node.cond, proc, sys, shell)
			if condCode ~= 0 then break end
			local ok, sig = pcall(Executor.execute, node.body, proc, sys, shell)
			if not ok then
				if sig == BREAK_SIGNAL then break
				elseif sig == CONTINUE_SIGNAL then -- continue
				else error(sig) end
			end
		end
		return 0

	elseif t == AST.Until then
		while true do
			local condCode = Executor.execute(node.cond, proc, sys, shell)
			if condCode == 0 then break end
			local ok, sig = pcall(Executor.execute, node.body, proc, sys, shell)
			if not ok then
				if sig == BREAK_SIGNAL then break
				elseif sig == CONTINUE_SIGNAL then
				else error(sig) end
			end
		end
		return 0

	elseif t == AST.For then
		local words = Expander.expand(node.words, proc, sys)
		for _, val in ipairs(words) do
			proc.env[node.var] = val
			local ok, sig = pcall(Executor.execute, node.body, proc, sys, shell)
			if not ok then
				if sig == BREAK_SIGNAL then break
				elseif sig == CONTINUE_SIGNAL then
				else error(sig) end
			end
		end
		return 0

	elseif t == AST.Case then
		local word = Expander.expandOne(node.word, proc, sys)
		for _, item in ipairs(node.items) do
			for _, pat in ipairs(item.patterns) do
				local luaPat = pat:gsub("[%(%)%.%%%+%-%^%$]","%%%1"):gsub("%*",".*"):gsub("%?",".")
				if word:match("^" .. luaPat .. "$") or pat == "*" then
					if item.body then return Executor.execute(item.body, proc, sys, shell) end
					return 0
				end
			end
		end
		return 0

	elseif t == AST.FuncDef then
		if shell then
			shell.functions = shell.functions or {}
			shell.functions[node.name] = node.body
		end
		return 0

	elseif t == AST.Subshell then
		local Syscall = require(script.Parent.Parent.kernel.Syscall)
		local exitCode = 0
		local childPid = sys.fork(function(child)
			local sc = Syscall.bind(child)
			local code = Executor.execute(node.list, child, sc, shell)
			sc.exit(code or 0)
		end)
		if childPid then exitCode = sys.waitpid(childPid) or 0 end
		return exitCode

	elseif t == AST.Group then
		return Executor.execute(node.list, proc, sys, shell)
	end

	return 0
end

Executor.BREAK    = BREAK_SIGNAL
Executor.CONTINUE = CONTINUE_SIGNAL
Executor.RETURN   = RETURN_SIGNAL

return Executor
