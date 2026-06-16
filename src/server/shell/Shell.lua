local C        = require(script.Parent.Parent.Parent.shared.Constants)
local Lexer    = require(script.Parent.Lexer)
local Parser   = require(script.Parent.Parser)
local Executor = require(script.Parent.Executor)
local Builtins = require(script.Parent.Builtins)

local Shell = {}

local function makePS1(proc)
	local user  = proc.uid == 0 and "root" or (proc.env["USER"] or "user")
	local host  = proc.env["HOSTNAME"] or "luaos"
	local cwd   = proc.cwd
	local home  = proc.env["HOME"] or "/home/user"
	if cwd:sub(1, #home) == home then
		cwd = "~" .. cwd:sub(#home + 1)
	end
	local sym = proc.uid == 0 and "#" or "$"
	return "\27[32m" .. user .. "@" .. host .. "\27[0m:\27[34m" .. cwd .. "\27[0m" .. sym .. " "
end

local function readLine(sys)
	local line = ""
	while true do
		local ch = sys.read(C.STDIN, 1)
		if not ch or ch == "" then return nil end  -- EOF
		if ch == "\n" then return line end
		line ..= ch
	end
end

function Shell.capture(cmdStr, proc, sys)
	-- 커맨드 치환: stdout을 string으로 캡처
	local Pipe = require(script.Parent.Parent.kernel.Pipe)
	local pipe = Pipe.new()
	local captured = ""

	local Syscall = require(script.Parent.Parent.kernel.Syscall)
	local FDT     = require(script.Parent.Parent.kernel.FDTable)
	local C2      = require(script.Parent.Parent.Parent.shared.Constants)

	local childPid = sys.fork(function(child)
		local sc = Syscall.bind(child)
		local wVn = {
			read  = function() return "" end,
			write = function(data)
				Pipe.write(pipe, data)
				return #data
			end,
			close = function() Pipe.closeWrite(pipe) end,
			type  = "pipe_w",
		}
		FDT.allocAt(child, C2.STDOUT, wVn)

		local tokens = Lexer.tokenize(cmdStr)
		local ast    = Parser.parse(tokens)
		if ast then
			local innerShell = { aliases = {}, functions = {}, history = {}, jobs = {} }
			Executor.execute(ast, child, sc, innerShell)
		end
		sc.exit(0)
	end)

	-- 파이프에서 읽기
	Pipe.closeWrite(pipe)
	while true do
		local data = Pipe.read(pipe, 65536)
		if data == nil then
			coroutine.yield({ op = "pipe_wait", pipe = pipe })
		elseif data == "" then
			break
		else
			captured ..= data
		end
	end

	if childPid then sys.waitpid(childPid) end
	return captured
end

function Shell.main(proc, sys)
	local shell = {
		aliases   = {},
		functions = {},
		history   = {},
		jobs      = {},
		_nextJob  = 0,
	}

	-- 기본 앨리아스
	shell.aliases["ll"] = "ls -la"
	shell.aliases["la"] = "ls -a"
	shell.aliases["l"]  = "ls -CF"

	-- /etc/profile 소싱 (없으면 무시)
	Builtins["source"](proc, sys, {"source", "/etc/profile"}, shell)
	Builtins["source"](proc, sys, {"source", proc.env["HOME"] .. "/.bashrc"}, shell)

	-- 부팅 메시지
	sys.write(C.STDOUT, "\27[1;36mLuaOS\27[0m bash 5.1.0\n")
	sys.write(C.STDOUT, "Type 'help' for a list of builtins.\n\n")

	-- 메인 루프
	while true do
		-- 완료된 백그라운드 잡 정리
		for id, job in pairs(shell.jobs) do
			local PT = require(script.Parent.Parent.kernel.ProcessTable)
			local p = PT.get(job.pid)
			if p and p.state == "zombie" then
				sys.write(C.STDOUT, "\n[" .. id .. "]+  Done  " .. job.cmd .. "\n")
				shell.jobs[id] = nil
			end
		end

		sys.write(C.STDOUT, makePS1(proc))

		local line = readLine(sys)
		if line == nil then
			sys.write(C.STDOUT, "exit\n")
			break
		end

		line = line:match("^%s*(.-)%s*$")
		if line == "" then goto continue end

		-- 히스토리
		if shell.history[#shell.history] ~= line then
			table.insert(shell.history, line)
		end

		-- 히스토리 확장 !!
		if line == "!!" and #shell.history >= 2 then
			line = shell.history[#shell.history - 1]
			sys.write(C.STDOUT, line .. "\n")
		end

		-- 파싱 & 실행
		local tokens = Lexer.tokenize(line)
		local ok_parse, ast = pcall(Parser.parse, tokens)
		if not ok_parse then
			sys.write(C.STDERR, "bash: parse error: " .. tostring(ast) .. "\n")
			proc.env["?"] = "2"
			goto continue
		end

		if ast then
			local ok_exec, result = pcall(Executor.execute, ast, proc, sys, shell)
			if not ok_exec then
				sys.write(C.STDERR, "bash: " .. tostring(result) .. "\n")
				proc.env["?"] = "1"
			else
				proc.env["?"] = tostring(result or 0)
			end
		end

		::continue::
	end

	sys.exit(tonumber(proc.env["?"]) or 0)
end

-- 문자열로 직접 실행 (source 용)
function Shell.runString(cmdStr, proc, sys, shell)
	local tokens = Lexer.tokenize(cmdStr)
	local lines  = {}
	-- 줄 단위로 분리해서 실행
	local ast = Parser.parse(tokens)
	if ast then Executor.execute(ast, proc, sys, shell) end
end

return Shell
