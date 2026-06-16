-- RISC-V 64 에뮬레이터 메인 진입점
local CPU     = require(script.Parent.CPU)
local Memory  = require(script.Parent.Memory)
local ELF     = require(script.Parent.ELF)
local Execute = require(script.Parent.Execute)

local Emulator = {}

-- 스택에 argv, envp, auxv 설정 (Linux ABI)
local function setupStack(cpu, mem, stackTop, argv, envp)
	local sp = stackTop

	-- 문자열들을 스택에 push
	local function pushStr(s)
		sp = sp - #s - 1
		mem:writeString(sp, s)
		return sp
	end

	-- envp 문자열
	local envAddrs = {}
	envp = envp or {}
	for i = #envp, 1, -1 do
		table.insert(envAddrs, 1, pushStr(envp[i]))
	end

	-- argv 문자열
	local argAddrs = {}
	for i = #argv, 1, -1 do
		table.insert(argAddrs, 1, pushStr(argv[i]))
	end

	-- 16바이트 정렬
	sp = sp - (sp % 16)

	-- auxv (보조 벡터) — AT_NULL로 종료
	local function push64(v)
		sp -= 8
		mem:write64(sp, v % 0x10000000000000000)
	end

	-- AT_NULL
	push64(0); push64(0)
	-- AT_PAGESZ = 6
	push64(4096); push64(6)
	-- AT_RANDOM (16바이트 랜덤 - 주소만 지정)
	push64(sp + 32); push64(25)

	-- null terminator for envp
	push64(0)
	for i = #envAddrs, 1, -1 do push64(envAddrs[i]) end

	-- null terminator for argv
	push64(0)
	for i = #argAddrs, 1, -1 do push64(argAddrs[i]) end

	-- argc
	push64(#argv)

	return sp
end

-- ELF 바이너리(base64)를 실행
-- kernelProc: 커널 프로세스 디스크립터
-- kernelSys:  syscall 바인딩
-- elfBase64:  ELF 바이너리의 base64 인코딩
-- argv:       프로그램 인수
function Emulator.exec(kernelProc, kernelSys, elfBase64, argv)
	-- base64 디코드
	local elfData, err = ELF.decodeBase64(elfBase64), nil
	if #elfData < 4 then
		kernelSys.write(2, "emulator: base64 decode failed\n")
		return 1
	end

	-- ELF 파싱
	local elf, perr = ELF.parse(elfData)
	if not elf then
		kernelSys.write(2, "emulator: ELF parse error: " .. tostring(perr) .. "\n")
		return 1
	end

	-- 메모리 생성
	local mem = Memory.new()

	-- ELF 로드
	local layout = ELF.load(elf, elfData, mem)

	-- CPU 생성
	local cpu  = CPU.new(mem)
	cpu.pc     = layout.entry
	cpu.uid    = kernelProc.uid
	cpu.gid    = kernelProc.gid
	cpu.cwd    = kernelProc.cwd
	cpu.heapBreak = layout.heapStart
	cpu.mmapTop   = 0x40000000

	-- fd 테이블 공유 (스택 설정은 kernelSys 통해)
	-- syscall 에서 kernelSys.write/read 사용

	-- argv 기본값
	argv = argv or { "program" }

	-- 스택 설정
	local envp = {}
	for k, v in pairs(kernelProc.env or {}) do
		table.insert(envp, k .. "=" .. tostring(v))
	end

	local sp = setupStack(cpu, mem, layout.stackTop, argv, envp)
	cpu:setReg(2, sp)  -- sp = x2

	-- 실행 (코루틴으로 감싸서 스케줄러와 협력)
	local exitCode = Execute.run(cpu, mem, kernelSys, 50000000)

	return exitCode or cpu.exitCode or 0
end

-- /usr/bin/emu 명령어로 등록될 함수
-- 사용법: emu <elf파일경로> [args...]
local function emuMain(proc, sys, argv)
	local path = argv[2]
	if not path then
		sys.write(2, "Usage: emu <elf-binary> [args...]\n")
		sys.write(2, "  ELF binary must be stored as base64 in the filesystem\n")
		return 1
	end

	-- 파일 읽기
	if path:sub(1,1) ~= "/" then path = proc.cwd .. "/" .. path end
	local fd = sys.open(path, { rdonly = true })
	if not fd then
		sys.write(2, "emu: " .. path .. ": not found\n")
		return 1
	end

	local data = ""
	while true do
		local chunk = sys.read(fd, 65536)
		if not chunk or chunk == "" then break end
		data ..= chunk
	end
	sys.close(fd)

	-- 실행 argv
	local execArgv = {}
	for i = 2, #argv do table.insert(execArgv, argv[i]) end

	return Emulator.exec(proc, sys, data, execArgv)
end

Emulator.main = emuMain
return Emulator
