local C  = require(script.Parent.Parent.Parent.shared.Constants)
local PT = require(script.Parent.ProcessTable)

local Signal = {}

function Signal.send(pid, sig)
	local proc = PT.get(pid)
	if not proc then return false end
	proc.signals_pending = bit32.bor(proc.signals_pending, bit32.lshift(1, sig))
	return true
end

-- 스케줄러가 resume 전에 호출
-- 처리할 시그널이 있으면 true 반환 (프로세스를 종료/중지시킴)
function Signal.check(proc)
	if proc.signals_pending == 0 then return false end

	for sig = 1, 31 do
		local mask = bit32.lshift(1, sig)
		if bit32.band(proc.signals_pending, mask) ~= 0 then
			proc.signals_pending = bit32.band(proc.signals_pending, bit32.bnot(mask))

			-- 블록된 시그널 무시 (SIGKILL/SIGSTOP 제외)
			if sig ~= C.SIGKILL and sig ~= C.SIGSTOP then
				if bit32.band(proc.signals_blocked, mask) ~= 0 then
					goto continue
				end
			end

			-- 커스텀 핸들러
			local handler = proc.signal_handlers[sig]
			if handler == "SIG_IGN" then
				goto continue
			elseif type(handler) == "function" then
				handler(sig)
				goto continue
			end

			-- 기본 동작
			if sig == C.SIGKILL or sig == C.SIGTERM or sig == C.SIGHUP then
				proc.state    = C.PROC_ZOMBIE
				proc.exitCode = 128 + sig
				return true
			elseif sig == C.SIGSTOP then
				proc.state = C.PROC_STOPPED
				return true
			elseif sig == C.SIGCONT then
				if proc.state == C.PROC_STOPPED then
					proc.state = C.PROC_RUNNING
				end
			elseif sig == C.SIGPIPE then
				proc.state    = C.PROC_ZOMBIE
				proc.exitCode = 128 + sig
				return true
			end
			-- SIGCHLD, SIGUSR1/2 기본: 무시
		end
		::continue::
	end
	return false
end

return Signal
