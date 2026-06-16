-- 실제 파일을 StorageManager 섹터에 저장하는 VFS 백엔드
local E    = require(script.Parent.Parent.Parent.shared.Errno)
local C    = require(script.Parent.Parent.Parent.shared.Constants)
local Inode = require(script.Parent.Inode)
local Perm  = require(script.Parent.Permissions)
local SM    = require(script.Parent.Parent.StorageManager)

local RealFS = {}

-- userId별 메타 확장 구조:
-- meta.inodeTable = { [ino] = inodeStruct }
-- meta.pathTable  = { [path] = ino }
-- meta.dirTable   = { [path] = { childName, ... } }

local function getMeta(userId)
	return SM.getMeta(userId)
end

local function initMeta(meta)
	if not meta.inodeTable then meta.inodeTable = {} end
	if not meta.pathTable  then meta.pathTable  = {} end
	if not meta.dirTable   then
		meta.dirTable = {
			["/"]          = {},
			["/home"]      = {},
			["/home/user"] = {},
			["/etc"]       = {},
			["/usr"]       = {},
			["/usr/bin"]   = {},
			["/var"]       = {},
			["/bin"]       = {},
		}
		-- 기본 디렉토리 inode 생성
		for path in pairs(meta.dirTable) do
			local ino = Inode.new({ mode = C.S_IFDIR + 0x1ED })
			meta.inodeTable[ino.ino] = ino
			meta.pathTable[path]     = ino.ino
		end
	end
end

local function normPath(p)
	p = p:gsub("//+", "/")
	if p ~= "/" then p = p:gsub("/$", "") end
	return p
end

local function parentAndName(path)
	local parent, name = path:match("^(.*)/([^/]+)$")
	if parent == "" then parent = "/" end
	return parent, name
end

-- 섹터에서 파일 내용 읽기 (다중 섹터 지원)
local function readContent(userId, inode)
	local parts = {}
	for _, idx in ipairs(inode.sectors) do
		local sector = SM.readSector(userId, idx)
		if sector and sector.content then
			table.insert(parts, sector.content)
		end
	end
	return table.concat(parts)
end

-- 파일 내용을 섹터에 쓰기
local function writeContent(userId, inode, content)
	-- 기존 섹터 해제
	for _, idx in ipairs(inode.sectors) do
		SM.freeSector(userId, idx)
	end
	inode.sectors = {}

	-- 4MB 청크로 분할 저장
	local pos = 1
	while pos <= #content do
		local chunk = content:sub(pos, pos + C.SECTOR_SIZE - 1)
		local idx = SM.allocSector(userId)
		if not idx then return nil, E.ENOSPC end
		SM.writeSector(userId, idx, { content = chunk })
		table.insert(inode.sectors, idx)
		pos += C.SECTOR_SIZE
	end

	inode.size  = #content
	inode.mtime = os.time()
	return 0
end

----------------------------------------------------------------------
-- VFS 인터페이스
----------------------------------------------------------------------

function RealFS.stat(userId, path)
	path = normPath(path)
	local meta = getMeta(userId)
	if not meta then return nil, E.EIO end
	initMeta(meta)

	local ino = meta.pathTable[path]
	if not ino then return nil, E.ENOENT end
	return meta.inodeTable[ino]
end

function RealFS.readdir(userId, path)
	path = normPath(path)
	local meta = getMeta(userId)
	if not meta then return nil, E.EIO end
	initMeta(meta)

	local ino = meta.pathTable[path]
	if not ino then return nil, E.ENOENT end
	local inode = meta.inodeTable[ino]
	if not Inode.isDir(inode.mode) then return nil, E.ENOTDIR end

	return meta.dirTable[path] or {}
end

function RealFS.read(userId, path)
	path = normPath(path)
	local meta = getMeta(userId)
	if not meta then return nil, E.EIO end
	initMeta(meta)

	local ino = meta.pathTable[path]
	if not ino then return nil, E.ENOENT end
	local inode = meta.inodeTable[ino]

	if Inode.isDir(inode.mode) then return nil, E.EISDIR end
	if Inode.isLink(inode.mode) then return inode.target end

	return readContent(userId, inode)
end

function RealFS.write(userId, path, content, proc)
	path = normPath(path)
	local meta = getMeta(userId)
	if not meta then return nil, E.EIO end
	initMeta(meta)

	local ino = meta.pathTable[path]
	local inode

	if ino then
		inode = meta.inodeTable[ino]
		if Inode.isDir(inode.mode) then return nil, E.EISDIR end
		if proc and not Perm.check(inode, proc.uid, proc.gid, "w") then
			return nil, E.EACCES
		end
	else
		-- 새 파일 생성
		local parent, name = parentAndName(path)
		local parentIno = meta.pathTable[parent]
		if not parentIno then return nil, E.ENOENT end

		inode = Inode.new({ uid = proc and proc.uid or 0, gid = proc and proc.gid or 0 })
		meta.inodeTable[inode.ino] = inode
		meta.pathTable[path]       = inode.ino
		meta.dirTable[parent]      = meta.dirTable[parent] or {}
		table.insert(meta.dirTable[parent], name)
	end

	local ok, err = writeContent(userId, inode, content)
	if not ok then return nil, err end
	SM.setMetaDirty(userId)
	return 0
end

function RealFS.mkdir(userId, path, proc)
	path = normPath(path)
	local meta = getMeta(userId)
	if not meta then return nil, E.EIO end
	initMeta(meta)

	if meta.pathTable[path] then return nil, E.EEXIST end
	local parent, name = parentAndName(path)
	if not meta.pathTable[parent] then return nil, E.ENOENT end

	local inode = Inode.new({
		mode = C.S_IFDIR + 0x1ED,
		uid  = proc and proc.uid or 0,
		gid  = proc and proc.gid or 0,
	})
	meta.inodeTable[inode.ino] = inode
	meta.pathTable[path]       = inode.ino
	meta.dirTable[parent] = meta.dirTable[parent] or {}
	table.insert(meta.dirTable[parent], name)
	meta.dirTable[path] = {}
	SM.setMetaDirty(userId)
	return 0
end

function RealFS.unlink(userId, path, proc)
	path = normPath(path)
	local meta = getMeta(userId)
	if not meta then return nil, E.EIO end

	local ino = meta.pathTable[path]
	if not ino then return nil, E.ENOENT end
	local inode = meta.inodeTable[ino]

	if Inode.isDir(inode.mode) then
		if meta.dirTable[path] and #meta.dirTable[path] > 0 then
			return nil, E.ENOTEMPTY
		end
		meta.dirTable[path] = nil
	else
		for _, idx in ipairs(inode.sectors) do
			SM.freeSector(userId, idx)
		end
	end

	local parent, name = parentAndName(path)
	local siblings = meta.dirTable[parent]
	if siblings then
		for i, n in ipairs(siblings) do
			if n == name then table.remove(siblings, i) break end
		end
	end

	meta.inodeTable[ino] = nil
	meta.pathTable[path] = nil
	SM.setMetaDirty(userId)
	return 0
end

function RealFS.rename(userId, oldPath, newPath, proc)
	local content, err = RealFS.read(userId, oldPath)
	if not content and err then return nil, err end
	local ok, werr = RealFS.write(userId, newPath, content, proc)
	if not ok then return nil, werr end
	RealFS.unlink(userId, oldPath, proc)
	return 0
end

function RealFS.symlink(userId, target, path)
	local meta = getMeta(userId)
	if not meta then return nil, E.EIO end
	initMeta(meta)

	if meta.pathTable[path] then return nil, E.EEXIST end
	local parent, name = parentAndName(path)
	if not meta.pathTable[parent] then return nil, E.ENOENT end

	local inode = Inode.new({ mode = C.S_IFLNK + 0x1FF, target = target })
	meta.inodeTable[inode.ino] = inode
	meta.pathTable[path]       = inode.ino
	meta.dirTable[parent] = meta.dirTable[parent] or {}
	table.insert(meta.dirTable[parent], name)
	SM.setMetaDirty(userId)
	return 0
end

return RealFS
