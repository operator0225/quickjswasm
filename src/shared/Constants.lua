local Constants = {
	-- DataStore / 스토리지
	SECTOR_SIZE       = 4 * 1024 * 1024,
	TOTAL_SECTORS     = 256,
	AUTOSAVE_INTERVAL = 300,
	DATASTORE_NAME    = "LUAOS_v1",
	META_KEY_PREFIX   = "meta_",
	SECTOR_KEY_PREFIX = "sector_",

	-- FD
	STDIN  = 0,
	STDOUT = 1,
	STDERR = 2,
	MAX_FD = 64,

	-- 프로세스
	MAX_PROCS = 64,
	PROC_RUNNING  = "running",
	PROC_SLEEPING = "sleeping",
	PROC_ZOMBIE   = "zombie",
	PROC_STOPPED  = "stopped",

	-- 시그널
	SIGHUP  = 1,
	SIGINT  = 2,
	SIGQUIT = 3,
	SIGKILL = 9,
	SIGPIPE = 13,
	SIGTERM = 15,
	SIGCHLD = 17,
	SIGCONT = 18,
	SIGSTOP = 19,
	SIGUSR1 = 10,
	SIGUSR2 = 12,

	-- 파일 모드
	S_IFREG = 0x8000,
	S_IFDIR = 0x4000,
	S_IFLNK = 0xA000,
	S_IRWXU = 0x01C0,
	S_IRWXG = 0x0038,
	S_IRWXO = 0x0007,

	-- VFS
	MAX_SYMLINK_DEPTH = 8,
	PATH_MAX          = 4096,
	MAX_PIPE_BUF      = 65536,
}

return Constants
