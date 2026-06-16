local E    = require(script.Parent.Parent.Parent.shared.Errno)
local C    = require(script.Parent.Parent.Parent.shared.Constants)
local PT   = require(script.Parent.ProcessTable)
local FDT  = require(script.Parent.FDTable)
local Sig  = require(script.Parent.Signal)
local Pipe = require(script.Parent.Pipe)
local VFS  = require(script.Parent.Parent.vfs.VFS)

-- lazy require로 순환 방지
local function Sched() return require(script.Parent.Scheduler) end

local Syscall = {}

-- 파이프 vnode 생성
local function makePipeVnode(pipe, isRead)
	if isRead then
		return {
			read = function(n)
				local data = Pipe.read(pipe, n)
				if data == nil then
					-- 블록: 스케줄러에 yield
					coroutine.yield({ op = "pipe_wait", pipe = pipe })
					return Pipe.read(pipe, n) or ""
				end
				return data
			end,
			write = function() return nil, E.EBADF end,
			close = function() Pipe.closeRead(pipe) end,
			type  = "pipe_r",
			pipe  = pipe,
		}
	else
		return {
			read  = function() return nil, E.EBADF end,
			write = function(data)
				local ok = Pipe.write(pipe, data)
				if ok then
					Sched().wakeOnPipe(pipe)
					return #data
				end
				return nil, E.EPIPE
			end,
			close = function()
				Pipe.closeWrite(pipe)
				Sched().wakeOnPipe(pipe)
			end,
			type  = "pipe_w",
			pipe  = pipe,
		}
	end
end

-- VFS 파일 vnode 생성
local function makeFileVnode(proc, path, flags)
	local buf    = nil
	local offset = 0

	return {
		read = function(n)
			if buf == nil then
				local content, err = VFS.read(proc, path)
				if not content then return nil, err end
				buf = content
			end
			if offset >= #buf then return "" end
			local chunk = buf:sub(offset + 1, offset + n)
			offset += #chunk
			return chunk
		end,
		write = function(data)
			if flags and flags.append then
				local existing = VFS.read(proc, path) or ""
				return VFS.write(proc, path, existing .. data)
			end
			-- 덮어쓰기
			buf = (buf or ""):sub(1, offset) .. data
			offset += #data
			return VFS.write(proc, path, buf)
		end,
		close = function() buf = nil end,
		type  = "file",
		path  = path,
	}
end

----------------------------------------------------------------------
-- 시스템 콜 핸들러
----------------------------------------------------------------------
local handlers = {}

handlers.write = function(proc, fd, data)
	local slot, err = FDT.get(proc, fd)
	if not slot then return nil, err end
	local n = slot.vnode.write(data)
	return n, nil
end

handlers.read = function(proc, fd, n)
	local slot, err = FDT.get(proc, fd)
	if not slot then return nil, err end
	local data = slot.vnode.read(n or 4096)
	return data, nil
end

handlers.open = function(proc, path, flags)
	path = VFS.absPath(proc, path)
	flags = flags or {}

	if flags.create then
		local ok, err = VFS.write(proc, path, "")
		if not ok and err ~= E.EEXIST then return nil, err end
	end

	local inode, err = VFS.stat(proc, path)
	if not inode and not flags.create then return nil, err or E.ENOENT end

	local vnode = makeFileVnode(proc, path, flags)
	local fd, ferr = FDT.alloc(proc, vnode, flags)
	if not fd then return nil, ferr end
	return fd
end

handlers.close = function(proc, fd)
	return FDT.close(proc, fd)
end

handlers.pipe = function(proc)
	local pipe     = Pipe.new()
	local readVn   = makePipeVnode(pipe, true)
	local writeVn  = makePipeVnode(pipe, false)
	local readFd   = FDT.alloc(proc, readVn)
	local writeFd  = FDT.alloc(proc, writeVn)
	return readFd, writeFd
end

handlers.dup2 = function(proc, oldFd, newFd)
	return FDT.dup2(proc, oldFd, newFd)
end

handlers.getpid = function(proc)
	return proc.pid
end

handlers.getppid = function(proc)
	return proc.ppid
end

handlers.exit = function(proc, code)
	FDT.closeAll(proc)
	proc.state    = C.PROC_ZOMBIE
	proc.exitCode = code or 0
	-- 부모 깨우기
	Sched().wakeParent(proc.pid)
	coroutine.yield({ op = "exit" })
end

handlers.fork = function(proc, childFn)
	local child = PT.create({
		ppid = proc.pid,
		uid  = proc.uid,
		gid  = proc.gid,
		name = proc.name,
		cwd  = proc.cwd,
		env  = {},
		argv = proc.argv,
	})
	if not child then return nil, E.ENOMEM end

	-- env 복사
	for k, v in pairs(proc.env) do child.env[k] = v end

	-- fd 테이블 복사
	FDT.copy(proc, child)

	-- 자식 관계
	PT.addChild(proc.pid, child.pid)

	-- 자식 코루틴 등록
	Sched().spawn(child, function()
		childFn(child)
	end)

	return child.pid
end

handlers.exec = function(proc, mainFn, argv)
	proc.argv = argv or {}
	proc.name = argv and argv[1] or proc.name

	-- 새 코루틴으로 교체
	local newCo = coroutine.create(function()
		local code = mainFn(proc, argv)
		handlers.exit(proc, code or 0)
	end)
	proc.coroutine = newCo
	Sched().spawn(proc, function() end)  -- 더미 — 실제로는 아래에서 교체
	-- 현재 코루틴에서 yield → 스케줄러가 새 코루틴으로 전환
	coroutine.yield({ op = "exec_replaced" })
end

handlers.waitpid = function(proc, pid)
	local target = PT.get(pid)
	if not target then return nil, E.ESRCH end
	if target.state ~= C.PROC_ZOMBIE then
		coroutine.yield({ op = "waitpid", pid = pid })
	end
	local code = target.exitCode
	PT.remove(pid)
	return code
end

handlers.kill = function(proc, pid, sig)
	if not Sig.send(pid, sig) then return nil, E.ESRCH end
	return 0
end

handlers.signal = function(proc, sig, handler)
	proc.signal_handlers[sig] = handler
	return 0
end

handlers.sleep = function(proc, seconds)
	coroutine.yield({ op = "sleep", t = seconds })
	return 0
end

-- stat
handlers.stat = function(proc, path)
	path = VFS.absPath(proc, path)
	return VFS.stat(proc, path)
end

-- 디렉토리 읽기
handlers.readdir = function(proc, path)
	path = VFS.absPath(proc, path)
	return VFS.readdir(proc, path)
end

handlers.mkdir = function(proc, path)
	path = VFS.absPath(proc, path)
	return VFS.mkdir(proc, path)
end

handlers.unlink = function(proc, path)
	path = VFS.absPath(proc, path)
	return VFS.unlink(proc, path)
end

handlers.rename = function(proc, oldPath, newPath)
	oldPath = VFS.absPath(proc, oldPath)
	newPath = VFS.absPath(proc, newPath)
	return VFS.rename(proc, oldPath, newPath)
end

handlers.symlink = function(proc, target, path)
	path = VFS.absPath(proc, path)
	return VFS.symlink(proc, target, path)
end

handlers.chdir = function(proc, path)
	path = VFS.absPath(proc, path)
	local inode, err = VFS.stat(proc, path)
	if not inode then return nil, err end
	proc.cwd = path
	return 0
end

----------------------------------------------------------------------
-- 디스패처
----------------------------------------------------------------------
function Syscall.call(name, proc, ...)
	local h = handlers[name]
	if not h then return nil, E.ENOSYS end
	return h(proc, ...)
end

-- 유저스페이스에서 편하게 쓸 수 있도록 proc 바인딩된 래퍼 반환
function Syscall.bind(proc)
	return setmetatable({}, {
		__index = function(_, name)
			return function(...)
				return Syscall.call(name, proc, ...)
			end
		end
	})
end

return Syscall
