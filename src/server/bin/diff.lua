return function(proc, sys, argv)
	local function absPath(p)
		if p:sub(1,1) == "/" then return p end
		return proc.cwd .. "/" .. p
	end

	local files = {}
	local context = 3
	local i = 2
	while i <= #argv do
		local a = argv[i]
		if a == "-u" then context = 3
		elseif a == "-U" then i = i + 1; context = tonumber(argv[i]) or 3
		elseif a:sub(1,2) == "-U" then context = tonumber(a:sub(3)) or 3
		elseif a:sub(1,1) ~= "-" then files[#files+1] = a
		end
		i = i + 1
	end

	if #files < 2 then
		sys.write(STDERR, "diff: need two files\nUsage: diff [-u] [-U N] FILE1 FILE2\n")
		return 2
	end

	local function readLines(path)
		local fd, err = sys.open(path, {rdonly=true})
		if not fd then return nil, err end
		local chunks = {}
		while true do
			local d = sys.read(fd, 4096); if not d or #d == 0 then break end
			chunks[#chunks+1] = d
		end
		sys.close(fd)
		local data = table.concat(chunks)
		local lines = {}
		local pos = 1
		while pos <= #data do
			local nl = data:find("\n", pos, true)
			if nl then lines[#lines+1] = data:sub(pos, nl-1); pos = nl+1
			else
				if pos <= #data then lines[#lines+1] = data:sub(pos) end
				pos = #data+1
			end
		end
		return lines
	end

	-- LCS using dynamic programming
	local function lcs(a, b)
		local m, n = #a, #b
		-- Use memory-efficient approach for large files
		if m * n > 100000 then
			-- Fallback: simple line-by-line diff without LCS
			return nil
		end
		local dp = {}
		for ii = 0, m do
			dp[ii] = {}
			for j = 0, n do dp[ii][j] = 0 end
		end
		for ii = 1, m do
			for j = 1, n do
				if a[ii] == b[j] then
					dp[ii][j] = dp[ii-1][j-1] + 1
				else
					dp[ii][j] = math.max(dp[ii-1][j], dp[ii][j-1])
				end
			end
		end
		-- Traceback
		local seq = {}
		local ii, j = m, n
		while ii > 0 and j > 0 do
			if a[ii] == b[j] then
				table.insert(seq, 1, {ai=ii, bi=j})
				ii = ii - 1; j = j - 1
			elseif dp[ii-1][j] > dp[ii][j-1] then
				ii = ii - 1
			else
				j = j - 1
			end
		end
		return seq
	end

	-- Build edit script from LCS
	local function buildEdits(a, b, lcsSeq)
		local edits = {}  -- {op="+"/"-"/" ", aline, bline, text}
		local ai, bi = 1, 1
		local si = 1
		while ai <= #a or bi <= #b do
			local nextMatch = lcsSeq and lcsSeq[si]
			if nextMatch and ai == nextMatch.ai and bi == nextMatch.bi then
				edits[#edits+1] = {op=" ", ai=ai, bi=bi, text=a[ai]}
				ai = ai + 1; bi = bi + 1; si = si + 1
			elseif not nextMatch or (ai <= #a and (not nextMatch or ai < nextMatch.ai)) then
				if bi <= #b and (not nextMatch or bi < nextMatch.bi) then
					-- both have lines to add
					edits[#edits+1] = {op="-", ai=ai, text=a[ai]}
					ai = ai + 1
				elseif ai <= #a then
					edits[#edits+1] = {op="-", ai=ai, text=a[ai]}
					ai = ai + 1
				else
					edits[#edits+1] = {op="+", bi=bi, text=b[bi]}
					bi = bi + 1
				end
			else
				edits[#edits+1] = {op="+", bi=bi, text=b[bi]}
				bi = bi + 1
			end
		end
		return edits
	end

	-- Simpler Myers-like diff
	local function simpleDiff(a, b)
		local edits = {}
		local ai, bi = 1, 1
		while ai <= #a or bi <= #b do
			if ai <= #a and bi <= #b and a[ai] == b[bi] then
				edits[#edits+1] = {op=" ", ai=ai, bi=bi, text=a[ai]}
				ai = ai + 1; bi = bi + 1
			elseif ai <= #a then
				-- check if b[bi] appears in a ahead
				local found = false
				for la = ai+1, math.min(ai+8, #a) do
					if a[la] == b[bi] then found = true; break end
				end
				if bi <= #b and not found then
					edits[#edits+1] = {op="+", bi=bi, text=b[bi]}
					bi = bi + 1
				else
					edits[#edits+1] = {op="-", ai=ai, text=a[ai]}
					ai = ai + 1
				end
			else
				edits[#edits+1] = {op="+", bi=bi, text=b[bi]}
				bi = bi + 1
			end
		end
		return edits
	end

	local path1 = absPath(files[1])
	local path2 = absPath(files[2])
	local lines1, e1 = readLines(path1)
	local lines2, e2 = readLines(path2)

	if not lines1 then
		sys.write(STDERR, "diff: " .. files[1] .. ": " .. tostring(e1) .. "\n")
		return 2
	end
	if not lines2 then
		sys.write(STDERR, "diff: " .. files[2] .. ": " .. tostring(e2) .. "\n")
		return 2
	end

	local lcsSeq = lcs(lines1, lines2)
	local edits
	if lcsSeq then
		edits = buildEdits(lines1, lines2, lcsSeq)
	else
		edits = simpleDiff(lines1, lines2)
	end

	-- Check if any differences
	local hasDiff = false
	for _, e in ipairs(edits) do
		if e.op ~= " " then hasDiff = true; break end
	end

	if not hasDiff then return 0 end

	-- Output unified diff
	sys.write(STDOUT, "--- a/" .. files[1] .. "\n")
	sys.write(STDOUT, "+++ b/" .. files[2] .. "\n")

	-- Group into hunks
	local hunks = {}
	local hunk = nil
	for idx, e in ipairs(edits) do
		if e.op ~= " " then
			if not hunk then
				-- start new hunk: include context before
				local ctxStart = math.max(1, idx - context)
				hunk = {start=idx, ctxStart=ctxStart, lines={}}
				for ci = ctxStart, idx-1 do
					if edits[ci] and edits[ci].op == " " then
						hunk.lines[#hunk.lines+1] = edits[ci]
					end
				end
			end
			hunk.lines[#hunk.lines+1] = e
			hunk.lastChange = idx
		elseif hunk then
			hunk.lines[#hunk.lines+1] = e
			-- Check if we should close hunk
			local nextChange = nil
			for ni = idx+1, math.min(idx+context*2+1, #edits) do
				if edits[ni] and edits[ni].op ~= " " then nextChange = ni; break end
			end
			if not nextChange or nextChange - idx > context*2 then
				-- trim trailing context to `context` lines
				while #hunk.lines > 0 do
					local last = hunk.lines[#hunk.lines]
					if last.op == " " and (idx - (last.bi or last.ai or 0)) > context then
						table.remove(hunk.lines)
					else break
					end
				end
				hunks[#hunks+1] = hunk
				hunk = nil
			end
		end
	end
	if hunk then hunks[#hunks+1] = hunk end

	for _, h in ipairs(hunks) do
		local a1, a2, b1, b2 = math.huge, 0, math.huge, 0
		for _, e in ipairs(h.lines) do
			if e.ai then a1 = math.min(a1, e.ai); a2 = math.max(a2, e.ai) end
			if e.bi then b1 = math.min(b1, e.bi); b2 = math.max(b2, e.bi) end
		end
		if a1 == math.huge then a1 = 0 end
		if b1 == math.huge then b1 = 0 end
		sys.write(STDOUT, string.format("@@ -%d,%d +%d,%d @@\n", a1, a2-a1+1, b1, b2-b1+1))
		for _, e in ipairs(h.lines) do
			sys.write(STDOUT, e.op .. (e.text or "") .. "\n")
		end
	end

	return 1  -- 1 = differences found (standard diff behavior)
end
