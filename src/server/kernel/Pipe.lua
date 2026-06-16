local C = require(script.Parent.Parent.Parent.shared.Constants)

local Pipe = {}

function Pipe.new()
	return {
		buf         = "",
		readClosed  = false,
		writeClosed = false,
		waiters     = {},  -- PIDs 대기 중인 reader
	}
end

-- n 바이트 읽기. 데이터 없으면 nil 반환 (스케줄러가 yield 처리)
function Pipe.read(pipe, n)
	if #pipe.buf == 0 then
		if pipe.writeClosed then return "" end  -- EOF
		return nil  -- 블록 필요
	end
	n = math.min(n, #pipe.buf)
	local data = pipe.buf:sub(1, n)
	pipe.buf = pipe.buf:sub(n + 1)
	return data
end

-- 데이터 쓰기. 버퍼 초과 시 false 반환
function Pipe.write(pipe, data)
	if pipe.readClosed then return false end  -- SIGPIPE
	if #pipe.buf + #data > C.MAX_PIPE_BUF then return false end
	pipe.buf = pipe.buf .. data
	return true
end

function Pipe.closeWrite(pipe)
	pipe.writeClosed = true
end

function Pipe.closeRead(pipe)
	pipe.readClosed = true
end

return Pipe
