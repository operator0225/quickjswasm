local E      = require(script.Parent.Parent.Parent.shared.Errno)
local C      = require(script.Parent.Parent.Parent.shared.Constants)
local Inode  = require(script.Parent.Inode)
local RealFS = require(script.Parent.RealFS)
local TmpFS  = require(script.Parent.TmpFS)
local ProcFS = require(script.Parent.ProcFS)
local DevFS  = require(script.Parent.DevFS)

local VFS = {}

-- 마운트 테이블: { mountpoint, backend, needsUserId }
local mounts = {
	{ point = "/proc", backend = ProcFS, userId = false },
	{ point = "/dev",  backend = DevFS,  userId = false },
	{ point = "/tmp",  backend = TmpFS,  userId = false },
	{ point = "/",     backend = RealFS, userId = true  },
}

-- 경로에 맞는 마운트 찾기 (가장 긴 prefix 우선)
local function resolveMount(path)
	local best, bestLen = nil, -1
	for _, m in ipairs(mounts) do
		local pt = m.point
		local ptLen = #pt
		if path == pt or path:sub(1, ptLen) == pt and (ptLen == 1 or path:sub(ptLen+1,ptLen+1) == "/" or path:sub(ptLen+1,ptLen+1) == "") then
			if ptLen > bestLen then
				best = m
				bestLen = ptLen
			end
		end
	end
	return best
end

-- 마운트 포인트 기준 상대 경로 계산
local function relativePath(mountPoint, absPath)
	if mountPoint == "/" then return absPath end
	local rel = absPath:sub(#mountPoint + 1)
	if rel == "" then rel = "/" end
	return rel
end

local function normPath(p)
	p = p:gsub("//+", "/")
	if p ~= "/" then p = p:gsub("/$", "") end
	return p
end

-- 심링크 해석 포함 경로 정규화
local function resolvePath(proc, path, depth)
	depth = depth or 0
	if depth > C.MAX_SYMLINK_DEPTH then return nil, E.ELOOP end
	path = normPath(path)

	local mount = resolveMount(path)
	if not mount then return nil, E.ENOENT end
	local rel = relativePath(mount.point, path)

	local inode, err
	if mount.userId then
		inode, err = mount.backend.stat(proc.uid >= 1000 and (proc.uid - 1000) or proc.uid, rel)
	else
		inode, err = mount.backend.stat(rel)
	end

	if inode and Inode.isLink(inode.mode) then
		local target = inode.target
		if target:sub(1,1) ~= "/" then
			local parent = path:match("^(.*)/[^/]+$") or "/"
			target = parent .. "/" .. target
		end
		return resolvePath(proc, target, depth + 1)
	end

	return path, nil, mount, rel
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

function VFS.stat(proc, path)
	local resolved, err, mount, rel = resolvePath(proc, path)
	if not resolved then return nil, err end
	if mount.userId then
		return mount.backend.stat(proc.uid >= 1000 and (proc.uid - 1000) or proc.uid, rel)
	else
		return mount.backend.stat(rel)
	end
end

function VFS.readdir(proc, path)
	local resolved, err, mount, rel = resolvePath(proc, path)
	if not resolved then return nil, err end
	if mount.userId then
		return mount.backend.readdir(proc.uid >= 1000 and (proc.uid - 1000) or proc.uid, rel)
	else
		return mount.backend.readdir(rel)
	end
end

function VFS.read(proc, path)
	local resolved, err, mount, rel = resolvePath(proc, path)
	if not resolved then return nil, err end
	if mount.userId then
		return mount.backend.read(proc.uid >= 1000 and (proc.uid - 1000) or proc.uid, rel)
	else
		return mount.backend.read(rel)
	end
end

function VFS.write(proc, path, content)
	path = normPath(path)
	local mount = resolveMount(path)
	if not mount then return nil, E.ENOENT end
	local rel = relativePath(mount.point, path)
	if mount.userId then
		return mount.backend.write(proc.uid >= 1000 and (proc.uid - 1000) or proc.uid, rel, content, proc)
	else
		return mount.backend.write(rel, content)
	end
end

function VFS.mkdir(proc, path)
	path = normPath(path)
	local mount = resolveMount(path)
	if not mount then return nil, E.ENOENT end
	local rel = relativePath(mount.point, path)
	if mount.userId then
		return mount.backend.mkdir(proc.uid >= 1000 and (proc.uid - 1000) or proc.uid, rel, proc)
	else
		return mount.backend.mkdir(rel)
	end
end

function VFS.unlink(proc, path)
	path = normPath(path)
	local mount = resolveMount(path)
	if not mount then return nil, E.ENOENT end
	local rel = relativePath(mount.point, path)
	if mount.userId then
		return mount.backend.unlink(proc.uid >= 1000 and (proc.uid - 1000) or proc.uid, rel, proc)
	else
		return mount.backend.unlink(rel)
	end
end

function VFS.rename(proc, oldPath, newPath)
	oldPath = normPath(oldPath)
	newPath = normPath(newPath)
	local mount = resolveMount(oldPath)
	if not mount then return nil, E.ENOENT end
	local relOld = relativePath(mount.point, oldPath)
	local relNew = relativePath(mount.point, newPath)
	if mount.userId then
		local uid = proc.uid >= 1000 and (proc.uid - 1000) or proc.uid
		return mount.backend.rename(uid, relOld, relNew, proc)
	else
		return mount.backend.rename(relOld, relNew)
	end
end

function VFS.symlink(proc, target, path)
	path = normPath(path)
	local mount = resolveMount(path)
	if not mount then return nil, E.ENOENT end
	local rel = relativePath(mount.point, path)
	if mount.backend.symlink and mount.userId then
		return mount.backend.symlink(proc.uid >= 1000 and (proc.uid - 1000) or proc.uid, target, rel)
	end
	return nil, E.ENOSYS
end

-- 경로를 proc.cwd 기준으로 절대경로로 변환
function VFS.absPath(proc, path)
	if path:sub(1,1) == "/" then return normPath(path) end
	if path == "~" or path:sub(1,2) == "~/" then
		local home = "/home/user"
		path = home .. path:sub(2)
	end
	return normPath(proc.cwd .. "/" .. path)
end

return VFS
