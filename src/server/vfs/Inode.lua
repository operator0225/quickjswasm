local C = require(script.Parent.Parent.Parent.shared.Constants)

local Inode = {}
local nextIno = 1

function Inode.new(opts)
	local ino = nextIno
	nextIno += 1
	return {
		ino     = ino,
		mode    = opts.mode or (C.S_IFREG + 0x1B6),  -- 0644
		uid     = opts.uid  or 0,
		gid     = opts.gid  or 0,
		size    = opts.size or 0,
		nlinks  = opts.nlinks or 1,
		atime   = os.time(),
		mtime   = os.time(),
		ctime   = os.time(),
		sectors = opts.sectors or {},  -- { sectorIndex, ... }
		target  = opts.target,         -- symlink 대상 경로
		xattr   = {},
	}
end

function Inode.isDir(mode)
	return bit32.band(mode, 0xF000) == C.S_IFDIR
end

function Inode.isFile(mode)
	return bit32.band(mode, 0xF000) == C.S_IFREG
end

function Inode.isLink(mode)
	return bit32.band(mode, 0xF000) == C.S_IFLNK
end

function Inode.modeStr(mode)
	local t = Inode.isDir(mode) and "d" or (Inode.isLink(mode) and "l" or "-")
	local perms = ""
	local bits = { 0x100,0x080,0x040, 0x020,0x010,0x008, 0x004,0x002,0x001 }
	local chars = { "r","w","x","r","w","x","r","w","x" }
	for i, bit in ipairs(bits) do
		perms ..= bit32.band(mode, bit) ~= 0 and chars[i] or "-"
	end
	return t .. perms
end

return Inode
