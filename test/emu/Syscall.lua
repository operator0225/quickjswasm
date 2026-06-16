-- Linux RISC-V 64 syscall → LuaOS 커널 브리지
local Syscall = {}

-- RISC-V Linux syscall 번호 (ABI)
local SYS = {
	io_setup       = 0,
	read           = 63,
	write          = 64,
	readv          = 65,
	writev         = 66,
	pread64        = 67,
	pwrite64       = 68,
	openat         = 56,
	close          = 57,
	lseek          = 62,
	fstat          = 80,
	newfstatat     = 79,
	exit           = 93,
	exit_group     = 94,
	brk            = 214,
	mmap           = 222,
	munmap         = 215,
	mprotect       = 226,
	getpid         = 172,
	getuid         = 174,
	geteuid        = 175,
	getgid         = 176,
	getegid        = 177,
	uname          = 160,
	getcwd         = 17,
	chdir          = 49,
	mkdir          = 1030,
	mkdirat        = 34,
	unlinkat       = 35,
	renameat       = 38,
	getdents64     = 61,
	nanosleep      = 101,
	clock_gettime  = 113,
	ioctl          = 29,
	writev2        = 66,
	rt_sigaction   = 134,
	rt_sigprocmask = 135,
	set_tid_address= 96,
	set_robust_list= 99,
	madvise        = 233,
	futex          = 98,
}

-- errno 코드
local ENOENT  = 2
local EBADF   = 9
local ENOMEM  = 12
local EACCES  = 13
local EINVAL  = 22
local ENOSYS  = 38

-- AT_FDCWD
local AT_FDCWD = -100

local function errRet(errno)
	return -errno
end

function Syscall.handle(cpu, mem, kernelSys, nr, a0, a1, a2, a3, a4, a5)
	-- brk: 힙 확장
	if nr == SYS.brk then
		if a0 == 0 then
			return cpu.heapBreak or 0x10000000
		end
		local old = cpu.heapBreak or 0x10000000
		cpu.heapBreak = a0
		return a0

	-- mmap: 메모리 매핑
	elseif nr == SYS.mmap then
		local size = math.ceil(a1 / 4096) * 4096
		local addr = cpu.mmapTop or 0x40000000
		cpu.mmapTop = addr + size
		-- 0으로 초기화
		for i = 0, size - 1 do mem:write8(addr + i, 0) end
		return addr

	-- munmap: 무시 (메모리 해제 안 함)
	elseif nr == SYS.munmap then
		return 0

	-- mprotect: 무시
	elseif nr == SYS.mprotect then
		return 0

	-- madvise: 무시
	elseif nr == SYS.madvise then
		return 0

	-- write
	elseif nr == SYS.write or nr == SYS.writev then
		local fd   = a0
		local buf  = a1
		local size = a2
		local s = ""
		for i = 0, size - 1 do
			local b = mem:read8(buf + i)
			if b == 0 and nr ~= SYS.write then break end
			s ..= string.char(b)
		end
		local ok = kernelSys.write(fd, s)
		return ok and size or errRet(EBADF)

	-- read
	elseif nr == SYS.read then
		local fd   = a0
		local buf  = a1
		local size = a2
		local data = kernelSys.read(fd, size)
		if not data then return errRet(EBADF) end
		for i = 1, #data do
			mem:write8(buf + i - 1, data:byte(i))
		end
		return #data

	-- openat
	elseif nr == SYS.openat then
		local dirfd = a0
		local path  = mem:readString(a1)
		local flags = a2
		-- AT_FDCWD: 현재 디렉토리 기준
		local O_CREAT   = 0x40
		local O_WRONLY  = 0x1
		local O_RDWR    = 0x2
		local O_APPEND  = 0x400
		local O_TRUNC   = 0x200
		local fdFlags = {
			rdonly = bit32.band(flags, 3) == 0,
			create = bit32.band(flags, O_CREAT) ~= 0,
			append = bit32.band(flags, O_APPEND) ~= 0,
		}
		local fd, err = kernelSys.open(path, fdFlags)
		if not fd then return errRet(ENOENT) end
		return fd

	-- close
	elseif nr == SYS.close then
		kernelSys.close(a0)
		return 0

	-- lseek
	elseif nr == SYS.lseek then
		return 0  -- 기본 구현: 무시

	-- exit / exit_group
	elseif nr == SYS.exit or nr == SYS.exit_group then
		cpu.running  = false
		cpu.exitCode = a0
		-- kernelSys.exit는 선택적으로 호출 (에뮬레이터 단독 테스트 시 생략)
		if kernelSys.exit then
			pcall(kernelSys.exit, a0)
		end
		return 0

	-- getpid
	elseif nr == SYS.getpid then
		return kernelSys.getpid()

	-- getuid/geteuid/getgid/getegid
	elseif nr == SYS.getuid or nr == SYS.geteuid then
		return cpu.uid or 1000
	elseif nr == SYS.getgid or nr == SYS.getegid then
		return cpu.gid or 1000

	-- uname
	elseif nr == SYS.uname then
		local fields = {
			"Linux",                  -- sysname  [65]
			"luaos",                  -- nodename [65]
			"5.15.0-luaos",           -- release  [65]
			"#1 SMP RISC-V",          -- version  [65]
			"riscv64",                -- machine  [65]
			"",                       -- domainname[65]
		}
		local addr = a0
		for _, f in ipairs(fields) do
			mem:writeString(addr, f)
			addr += 65
		end
		return 0

	-- getcwd
	elseif nr == SYS.getcwd then
		local cwd = cpu.cwd or "/"
		mem:writeString(a0, cwd)
		return a0

	-- chdir
	elseif nr == SYS.chdir then
		local path = mem:readString(a0)
		local ok = kernelSys.chdir(path)
		return ok and 0 or errRet(ENOENT)

	-- mkdirat
	elseif nr == SYS.mkdirat then
		local path = mem:readString(a1)
		local ok = kernelSys.mkdir(path)
		return ok and 0 or errRet(EACCES)

	-- unlinkat
	elseif nr == SYS.unlinkat then
		local path = mem:readString(a1)
		local ok = kernelSys.unlink(path)
		return ok and 0 or errRet(ENOENT)

	-- newfstatat / fstat
	elseif nr == SYS.newfstatat or nr == SYS.fstat then
		local path
		if nr == SYS.newfstatat then
			path = mem:readString(a1)
		end
		local stat
		if path then
			stat = kernelSys.stat(path)
		end
		if not stat then return errRet(ENOENT) end
		-- struct stat 쓰기 (간소화)
		local addr = nr == SYS.newfstatat and a2 or a1
		mem:write64(addr,    1)            -- st_dev
		mem:write64(addr+8,  stat.ino or 1) -- st_ino
		mem:write32(addr+16, stat.mode or 0x81A4) -- st_mode
		mem:write32(addr+20, stat.nlinks or 1) -- st_nlink
		mem:write32(addr+24, stat.uid or 0)
		mem:write32(addr+28, stat.gid or 0)
		mem:write64(addr+48, stat.size or 0) -- st_size
		mem:write64(addr+72, stat.mtime or os.time()) -- st_mtime
		return 0

	-- getdents64: 디렉토리 엔트리 읽기
	elseif nr == SYS.getdents64 then
		local fd    = a0
		local buf   = a1
		local count = a2
		-- fd로 경로 알아내기 (간소화: cpu.openPaths 테이블)
		local path = cpu.openPaths and cpu.openPaths[fd]
		if not path then return errRet(EBADF) end
		local entries = kernelSys.readdir(path)
		if not entries then return errRet(ENOENT) end
		local pos = buf
		local total = 0
		for _, name in ipairs(entries) do
			local reclen = 19 + #name + 1
			reclen = math.ceil(reclen / 8) * 8
			if total + reclen > count then break end
			mem:write64(pos, 1)      -- d_ino
			mem:write64(pos+8, 0)    -- d_off
			mem:write16(pos+16, reclen) -- d_reclen
			mem:write8(pos+18, 8)    -- d_type (DT_REG=8, DT_DIR=4)
			mem:writeString(pos+19, name)
			pos   += reclen
			total += reclen
		end
		return total

	-- nanosleep
	elseif nr == SYS.nanosleep then
		local secs  = mem:read64(a0)
		local nsecs = mem:read64(a0 + 8)
		local t = secs + nsecs / 1e9
		if t > 0 then kernelSys.sleep(t) end
		return 0

	-- clock_gettime
	elseif nr == SYS.clock_gettime then
		local t = os.time()
		mem:write64(a1, t)       -- tv_sec
		mem:write64(a1+8, 0)     -- tv_nsec
		return 0

	-- ioctl: 터미널 관련 대부분 무시
	elseif nr == SYS.ioctl then
		return 0

	-- set_tid_address, set_robust_list, rt_sigprocmask, rt_sigaction: 무시
	elseif nr == SYS.set_tid_address or nr == SYS.set_robust_list
	    or nr == SYS.rt_sigprocmask  or nr == SYS.rt_sigaction
	    or nr == SYS.futex then
		return 0

	else
		-- 미구현 syscall
		warn("[EMU] 미구현 syscall:", nr, "a0=", a0)
		return errRet(ENOSYS)
	end
end

return Syscall
