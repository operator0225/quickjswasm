local C = require(script.Parent.Parent.Parent.shared.Constants)
local E = require(script.Parent.Parent.Parent.shared.Errno)

local FDTable = {}

-- fd 슬롯: { vnode, offset, flags }
-- vnode: { read(n), write(data), close(), type }

function FDTable.alloc(proc, vnode, flags)
	for fd = 0, C.MAX_FD - 1 do
		if not proc.fdTable[fd] then
			proc.fdTable[fd] = { vnode = vnode, offset = 0, flags = flags or 0 }
			return fd
		end
	end
	return nil, E.EMFILE
end

function FDTable.allocAt(proc, fd, vnode, flags)
	proc.fdTable[fd] = { vnode = vnode, offset = 0, flags = flags or 0 }
	return fd
end

function FDTable.get(proc, fd)
	local slot = proc.fdTable[fd]
	if not slot then return nil, E.EBADF end
	return slot
end

function FDTable.close(proc, fd)
	local slot = proc.fdTable[fd]
	if not slot then return nil, E.EBADF end
	if slot.vnode.close then slot.vnode.close() end
	proc.fdTable[fd] = nil
	return 0
end

function FDTable.dup2(proc, oldFd, newFd)
	local slot = proc.fdTable[oldFd]
	if not slot then return nil, E.EBADF end
	if proc.fdTable[newFd] then
		FDTable.close(proc, newFd)
	end
	proc.fdTable[newFd] = { vnode = slot.vnode, offset = slot.offset, flags = slot.flags }
	return newFd
end

-- fork 시 fd 테이블 복사
function FDTable.copy(srcProc, dstProc)
	for fd, slot in pairs(srcProc.fdTable) do
		dstProc.fdTable[fd] = { vnode = slot.vnode, offset = slot.offset, flags = slot.flags }
	end
end

-- 프로세스 종료 시 전체 닫기
function FDTable.closeAll(proc)
	for fd in pairs(proc.fdTable) do
		FDTable.close(proc, fd)
	end
end

return FDTable
