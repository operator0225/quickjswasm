local E  = require(script.Parent.Parent.Parent.shared.Errno)
local C  = require(script.Parent.Parent.Parent.shared.Constants)

-- ProcessTable은 순환 참조 방지를 위해 lazy require
local function PT() return require(script.Parent.Parent.kernel.ProcessTable) end

local bootTime = os.time()
local ProcFS = {}

local function pidEntries()
	local list = {}
	for pid in pairs(PT().all()) do
		table.insert(list, tostring(pid))
	end
	return list
end

local function procStatus(pid)
	local proc = PT().get(tonumber(pid))
	if not proc then return nil end
	return table.concat({
		"Name:\t"  .. proc.name,
		"Pid:\t"   .. proc.pid,
		"PPid:\t"  .. proc.ppid,
		"Uid:\t"   .. proc.uid,
		"Gid:\t"   .. proc.gid,
		"State:\t" .. proc.state,
	}, "\n") .. "\n"
end

local function procCmdline(pid)
	local proc = PT().get(tonumber(pid))
	if not proc then return nil end
	return table.concat(proc.argv or {}, "\0") .. "\0"
end

-- /proc/uptime
local function uptime()
	local up = os.time() - bootTime
	return string.format("%.2f %.2f\n", up, up * 0.9)
end

-- /proc/version
local function version()
	return "Linux version 5.15.0-luaos (luau@roblox) #1 SMP\n"
end

-- /proc/meminfo (가짜)
local function meminfo()
	return "MemTotal:       1048576 kB\nMemFree:        524288 kB\nMemAvailable:   786432 kB\n"
end

-- /proc/cpuinfo (가짜)
local function cpuinfo()
	return "processor\t: 0\nmodel name\t: LuaOS Virtual CPU\ncpu MHz\t\t: 3000.000\n"
end

function ProcFS.stat(path)
	-- 모든 경로를 디렉토리 또는 파일로 가짜 처리
	local mode
	if path == "/" or path:match("^/%d+$") then
		mode = C.S_IFDIR + 0x555
	else
		mode = C.S_IFREG + 0x444
	end
	return { ino=0, mode=mode, uid=0, gid=0, size=0, nlinks=1, atime=os.time(), mtime=os.time(), ctime=os.time() }
end

function ProcFS.readdir(path)
	if path == "/" then
		local entries = { "uptime", "version", "meminfo", "cpuinfo", "self" }
		for _, e in ipairs(pidEntries()) do table.insert(entries, e) end
		return entries
	end
	local pid = path:match("^/(%d+)$")
	if pid then
		return { "status", "cmdline", "fd" }
	end
	return nil, E.ENOENT
end

function ProcFS.read(path)
	if path == "/uptime"  then return uptime()  end
	if path == "/version" then return version() end
	if path == "/meminfo" then return meminfo() end
	if path == "/cpuinfo" then return cpuinfo() end

	local pid, file = path:match("^/(%d+)/(.+)$")
	if pid then
		if file == "status"  then return procStatus(pid)  or ("" ) end
		if file == "cmdline" then return procCmdline(pid) or ("" ) end
		return nil, E.ENOENT
	end
	return nil, E.ENOENT
end

function ProcFS.write()   return nil, E.EACCES end
function ProcFS.mkdir()   return nil, E.EACCES end
function ProcFS.unlink()  return nil, E.EACCES end
function ProcFS.rename()  return nil, E.EACCES end

return ProcFS
