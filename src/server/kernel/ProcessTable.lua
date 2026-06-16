local C = require(script.Parent.Parent.Parent.shared.Constants)

local ProcessTable = {}

local procs = {}     -- { [pid] = procDesc }
local nextPid = 1

local function allocPid()
	for _ = 1, C.MAX_PROCS do
		if not procs[nextPid] then
			local pid = nextPid
			nextPid = (nextPid % C.MAX_PROCS) + 1
			return pid
		end
		nextPid = (nextPid % C.MAX_PROCS) + 1
	end
	return nil
end

-- 새 프로세스 디스크립터 생성
function ProcessTable.create(opts)
	local pid = allocPid()
	if not pid then return nil end

	local proc = {
		pid      = pid,
		ppid     = opts.ppid or 0,
		uid      = opts.uid  or 0,
		gid      = opts.gid  or 0,
		name     = opts.name or "unknown",
		state    = C.PROC_RUNNING,
		cwd      = opts.cwd  or "/home",
		env      = opts.env  or {},
		argv     = opts.argv or {},

		coroutine      = nil,
		fdTable        = {},

		signals_pending = 0,
		signals_blocked = 0,
		signal_handlers = {},

		exitCode = 0,
		children = {},

		-- 스케줄러용
		sleepUntil  = nil,
		waitingPipe = nil,
		waitingPid  = nil,
	}

	procs[pid] = proc
	return proc
end

function ProcessTable.get(pid)
	return procs[pid]
end

function ProcessTable.remove(pid)
	procs[pid] = nil
end

function ProcessTable.all()
	return procs
end

function ProcessTable.addChild(parentPid, childPid)
	local parent = procs[parentPid]
	if parent then
		table.insert(parent.children, childPid)
	end
end

return ProcessTable
