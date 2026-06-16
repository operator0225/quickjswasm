local C      = require(script.Parent.Parent.Parent.shared.Constants)
local PT     = require(script.Parent.ProcessTable)
local Signal = require(script.Parent.Signal)

local Scheduler = {}

local runQueue = {}   -- { pid, ... }
local parkedPipe = {} -- { [pipe] = {pid, ...} }
local parkedWait = {} -- { [parentPid] = true }

local function enqueue(pid)
	table.insert(runQueue, pid)
end

local function dequeue()
	return table.remove(runQueue, 1)
end

function Scheduler.spawn(proc, fn)
	proc.coroutine = coroutine.create(fn)
	enqueue(proc.pid)
end

function Scheduler.wake(pid)
	local proc = PT.get(pid)
	if proc and proc.state == C.PROC_SLEEPING then
		proc.state     = C.PROC_RUNNING
		proc.sleepUntil = nil
		enqueue(pid)
	end
end

-- pipe에 데이터 쓰여졌을 때 대기 중인 reader 깨우기
function Scheduler.wakeOnPipe(pipe)
	local waiters = parkedPipe[pipe]
	if not waiters then return end
	for _, pid in ipairs(waiters) do
		Scheduler.wake(pid)
	end
	parkedPipe[pipe] = nil
end

-- 자식 종료 시 wait 중인 부모 깨우기
function Scheduler.wakeParent(childPid)
	local proc = PT.get(childPid)
	if not proc then return end
	local parent = PT.get(proc.ppid)
	if parent and parkedWait[proc.ppid] then
		parkedWait[proc.ppid] = nil
		Scheduler.wake(proc.ppid)
	end
end

function Scheduler.tick()
	local now = tick()

	-- 수면 중인 프로세스 깨우기
	for pid, proc in pairs(PT.all()) do
		if proc.state == C.PROC_SLEEPING and proc.sleepUntil and now >= proc.sleepUntil then
			proc.state      = C.PROC_RUNNING
			proc.sleepUntil = nil
			enqueue(pid)
		end
	end

	-- 실행 큐에서 하나 꺼내 실행
	local pid = dequeue()
	if not pid then return end

	local proc = PT.get(pid)
	if not proc then return end
	if proc.state ~= C.PROC_RUNNING then return end

	-- 시그널 처리
	if Signal.check(proc) then
		if proc.state == C.PROC_ZOMBIE then
			Scheduler.wakeParent(pid)
		end
		return
	end

	-- 코루틴 실행
	local ok, yieldVal = coroutine.resume(proc.coroutine)

	if not ok then
		-- 오류로 종료
		warn("[Scheduler] PID " .. pid .. " 오류: " .. tostring(yieldVal))
		proc.state    = C.PROC_ZOMBIE
		proc.exitCode = 1
		Scheduler.wakeParent(pid)
		return
	end

	if coroutine.status(proc.coroutine) == "dead" then
		-- 정상 종료
		proc.state = C.PROC_ZOMBIE
		Scheduler.wakeParent(pid)
		return
	end

	-- yield 유형 처리
	if type(yieldVal) == "table" then
		local op = yieldVal.op
		if op == "sleep" then
			proc.state      = C.PROC_SLEEPING
			proc.sleepUntil = now + (yieldVal.t or 0)

		elseif op == "pipe_wait" then
			proc.state = C.PROC_SLEEPING
			local pipe = yieldVal.pipe
			parkedPipe[pipe] = parkedPipe[pipe] or {}
			table.insert(parkedPipe[pipe], pid)

		elseif op == "waitpid" then
			local target = PT.get(yieldVal.pid)
			if target and target.state == C.PROC_ZOMBIE then
				-- 이미 끝난 경우 바로 재개
				enqueue(pid)
			else
				proc.state = C.PROC_SLEEPING
				parkedWait[pid] = true
			end

		elseif op == "exec_replaced" then
			-- exec 후 구 코루틴 폐기, 아무것도 안 함
			return
		else
			enqueue(pid)
		end
	else
		-- 단순 yield → 다시 큐에
		enqueue(pid)
	end
end

-- 메인 루프 시작
function Scheduler.start()
	task.spawn(function()
		while true do
			Scheduler.tick()
			task.wait()
		end
	end)
end

return Scheduler
