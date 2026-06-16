local E = require(script.Parent.Parent.Parent.shared.Errno)
local C = require(script.Parent.Parent.Parent.shared.Constants)

local DevFS = {}

local devices = {
	null   = true,
	zero   = true,
	random = true,
	tty    = true,
	full   = true,
}

function DevFS.stat(path)
	local name = path:match("^/(.+)$") or path
	if path == "/" then
		return { ino=0, mode=C.S_IFDIR+0x555, uid=0, gid=0, size=0, nlinks=1, atime=os.time(), mtime=os.time(), ctime=os.time() }
	end
	if devices[name] then
		return { ino=0, mode=C.S_IFREG+0x666, uid=0, gid=0, size=0, nlinks=1, atime=os.time(), mtime=os.time(), ctime=os.time() }
	end
	return nil, E.ENOENT
end

function DevFS.readdir(path)
	if path == "/" then
		local list = {}
		for k in pairs(devices) do table.insert(list, k) end
		return list
	end
	return nil, E.ENOENT
end

function DevFS.read(path, n)
	local name = path:match("^/(.+)$") or path
	if name == "null"   then return "" end
	if name == "full"   then return "" end
	if name == "zero"   then return string.rep("\0", n or 512) end
	if name == "random" then
		local buf = ""
		for _ = 1, (n or 512) do
			buf ..= string.char(math.random(0, 255))
		end
		return buf
	end
	if name == "tty" then return nil end  -- 블록 (스케줄러가 처리)
	return nil, E.ENODEV
end

function DevFS.write(path, data)
	local name = path:match("^/(.+)$") or path
	if name == "null" then return 0 end  -- 버림
	if name == "full" then return nil, E.ENOSPC end
	if name == "tty"  then return #data end  -- 터미널 출력 (상위에서 처리)
	return nil, E.ENODEV
end

function DevFS.mkdir()  return nil, E.EACCES end
function DevFS.unlink() return nil, E.EACCES end
function DevFS.rename() return nil, E.EACCES end

return DevFS
