-- 커널 부팅 및 공개 API
local C      = require(script.Parent.Parent.Parent.shared.Constants)
local PT     = require(script.Parent.ProcessTable)
local Sched  = require(script.Parent.Scheduler)
local Syscall = require(script.Parent.Syscall)
local FDT    = require(script.Parent.FDTable)
local Pipe   = require(script.Parent.Pipe)

local Kernel = {}

-- 터미널 콜백 등록: { [pid] = function(line) }
local termCallbacks = {}

-- 터미널용 stdin pipe 저장: { [pid] = pipe }
local stdinPipes = {}

local function makeTerminalVnodes(pid)
	local stdinPipe  = Pipe.new()
	local outputBuf  = ""

	stdinPipes[pid] = stdinPipe

	local stdinVnode = {
		read = function(n)
			local data = Pipe.read(stdinPipe, n or 4096)
			if data == nil then
				coroutine.yield({ op = "pipe_wait", pipe = stdinPipe })
				return Pipe.read(stdinPipe, n or 4096) or ""
			end
			return data
		end,
		write = function() return nil end,
		close = function() Pipe.closeRead(stdinPipe) end,
		type  = "tty_in",
	}

	local stdoutVnode = {
		read  = function() return "" end,
		write = function(data)
			if termCallbacks[pid] then
				termCallbacks[pid](data)
			end
			return #data
		end,
		close = function() end,
		type  = "tty_out",
	}

	return stdinVnode, stdoutVnode
end

-- 유저 셸 프로세스 시작
function Kernel.spawnShell(userId, outputCallback)
	local Shell = require(script.Parent.Parent.shell.Shell)

	local uid = 1000 + userId

	local proc = PT.create({
		ppid = 0,
		uid  = uid,
		gid  = uid,
		name = "bash",
		cwd  = "/home/user",
		env  = {
			HOME   = "/home/user",
			PATH   = "/usr/bin:/bin",
			SHELL  = "/bin/bash",
			TERM   = "luaos-256color",
			USER   = "user",
			LOGNAME = "user",
			PWD    = "/home/user",
		},
		argv = { "/bin/bash" },
	})

	if not proc then
		warn("[Kernel] 프로세스 생성 실패: PID 부족")
		return nil
	end

	-- stdin/stdout/stderr 연결
	local stdinVn, stdoutVn = makeTerminalVnodes(proc.pid)
	termCallbacks[proc.pid] = outputCallback

	FDT.allocAt(proc, C.STDIN,  stdinVn)
	FDT.allocAt(proc, C.STDOUT, stdoutVn)
	FDT.allocAt(proc, C.STDERR, stdoutVn)

	-- 셸 코루틴 시작
	Sched.spawn(proc, function()
		Shell.main(proc, Syscall.bind(proc))
	end)

	print("[Kernel] 셸 시작 PID=" .. proc.pid .. " UID=" .. uid)
	return proc.pid
end

-- 클라이언트 입력을 셸 stdin으로 전달
function Kernel.sendInput(pid, text)
	local pipe = stdinPipes[pid]
	if pipe then
		Pipe.write(pipe, text .. "\n")
		Sched.wakeOnPipe(pipe)
	end
end

-- 셸 프로세스 종료 시 정리
function Kernel.cleanup(pid)
	termCallbacks[pid] = nil
	stdinPipes[pid]    = nil
end

-- 부팅
function Kernel.boot()
	print("[Kernel] LuaOS booting...")
	Sched.start()
	print("[Kernel] 스케줄러 시작됨")
	print("[Kernel] 부팅 완료")
end

return Kernel
