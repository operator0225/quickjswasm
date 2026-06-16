-- nano: 간단한 줄 단위 텍스트 에디터
-- 입력: 일반 문자 → 현재 줄에 추가
-- Ctrl+S (^S = \19) → 저장
-- Ctrl+X (^X = \24) → 종료
-- Ctrl+K (^K = \11) → 현재 줄 삭제
-- 위/아래 화살표: ANSI \27[A / \27[B

return function(proc, sys, argv)
	local path = argv[2]
	if not path then
		sys.write(2, "nano: filename required\n")
		return 1
	end

	-- 절대 경로
	if path:sub(1,1) ~= "/" then path = proc.cwd .. "/" .. path end

	-- 파일 로드
	local lines = {}
	local fd = sys.open(path, { rdonly = true })
	if fd then
		local content = ""
		while true do
			local chunk = sys.read(fd, 65536)
			if not chunk or chunk == "" then break end
			content ..= chunk
		end
		sys.close(fd)
		for line in (content .. "\n"):gmatch("([^\n]*)\n") do
			table.insert(lines, line)
		end
		if #lines == 0 then lines = {""} end
	else
		lines = {""}
	end

	local row = 1
	local modified = false

	local function redraw()
		sys.write(1, "\27[2J\27[H")
		sys.write(1, "\27[1;37m  GNU nano — " .. path .. (modified and " *" or "") .. "\27[0m\n")
		sys.write(1, string.rep("─", 60) .. "\n")
		for i, line in ipairs(lines) do
			if i == row then
				sys.write(1, "\27[7m" .. string.format("%3d ", i) .. line .. "\27[0m\n")
			else
				sys.write(1, string.format("%3d ", i) .. line .. "\n")
			end
		end
		sys.write(1, string.rep("─", 60) .. "\n")
		sys.write(1, "\27[1m^S\27[0m Save  \27[1m^X\27[0m Exit  \27[1m^K\27[0m Cut Line  \27[1m^G\27[0m Help\n")
	end

	redraw()

	while true do
		local ch = sys.read(0, 4)
		if not ch or ch == "" then break end

		-- Ctrl+X = 종료
		if ch == "\24" then
			if modified then
				sys.write(1, "\nSave modified buffer? (y/n) ")
				local ans = sys.read(0, 1)
				if ans == "y" or ans == "Y" then
					local content = table.concat(lines, "\n")
					local wfd = sys.open(path, { create = true })
					if wfd then sys.write(wfd, content); sys.close(wfd) end
				end
			end
			break

		-- Ctrl+S = 저장
		elseif ch == "\19" then
			local content = table.concat(lines, "\n")
			local wfd = sys.open(path, { create = true })
			if wfd then sys.write(wfd, content); sys.close(wfd) end
			modified = false
			redraw()

		-- Ctrl+K = 현재 줄 삭제
		elseif ch == "\11" then
			if #lines > 1 then
				table.remove(lines, row)
				if row > #lines then row = #lines end
			else
				lines[1] = ""
			end
			modified = true
			redraw()

		-- 화살표 위 \27[A
		elseif ch == "\27[A" or ch:sub(1,3) == "\27[A" then
			if row > 1 then row -= 1 end
			redraw()

		-- 화살표 아래 \27[B
		elseif ch == "\27[B" or ch:sub(1,3) == "\27[B" then
			if row < #lines then row += 1 end
			redraw()

		-- Enter
		elseif ch == "\r" or ch == "\n" then
			table.insert(lines, row + 1, "")
			row += 1
			modified = true
			redraw()

		-- Backspace
		elseif ch == "\8" or ch == "\127" then
			if #lines[row] > 0 then
				lines[row] = lines[row]:sub(1,-2)
			elseif row > 1 then
				local prev = lines[row - 1]
				table.remove(lines, row)
				row -= 1
				lines[row] = prev
			end
			modified = true
			redraw()

		-- 일반 문자
		elseif ch:byte(1) >= 32 then
			lines[row] = (lines[row] or "") .. ch
			modified = true
			redraw()
		end
	end

	-- 화면 복원
	sys.write(1, "\27[2J\27[H")
	return 0
end
