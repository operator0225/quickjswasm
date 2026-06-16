return function(proc, sys, argv)
    local files = {}
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "--" then
            i = i + 1
            while i <= #argv do
                table.insert(files, argv[i])
                i = i + 1
            end
            break
        elseif string.sub(a, 1, 1) == "-" then
            -- ignore flags like -u (unified is default), -i, etc.
        else
            table.insert(files, a)
        end
        i = i + 1
    end

    if #files < 2 then
        sys.write(STDERR, "diff: missing operand\nUsage: diff FILE1 FILE2\n")
        return 2
    end

    local file1 = files[1]
    local file2 = files[2]

    local function resolve(path)
        if string.sub(path, 1, 1) == "/" then return path end
        return proc.cwd.."/"..path
    end

    local function read_all(fd)
        local chunks = {}
        while true do
            local data = sys.read(fd, 4096)
            if not data or #data == 0 then break end
            table.insert(chunks, data)
        end
        return table.concat(chunks)
    end

    local function split_lines(content)
        local lines = {}
        local pos = 1
        local len = #content
        while pos <= len do
            local nl = string.find(content, "\n", pos, true)
            if nl then
                table.insert(lines, string.sub(content, pos, nl - 1))
                pos = nl + 1
            else
                local rest = string.sub(content, pos)
                if #rest > 0 then
                    table.insert(lines, rest)
                end
                break
            end
        end
        return lines
    end

    local path1 = resolve(file1)
    local path2 = resolve(file2)

    local fd1, err1 = sys.open(path1, {rdonly=true})
    if not fd1 then
        sys.write(STDERR, "diff: '"..file1.."': No such file or directory\n")
        return 2
    end
    local content1 = read_all(fd1)
    sys.close(fd1)

    local fd2, err2 = sys.open(path2, {rdonly=true})
    if not fd2 then
        sys.write(STDERR, "diff: '"..file2.."': No such file or directory\n")
        return 2
    end
    local content2 = read_all(fd2)
    sys.close(fd2)

    local lines1 = split_lines(content1)
    local lines2 = split_lines(content2)

    -- LCS using DP table
    local m = #lines1
    local n = #lines2

    -- Build LCS length table
    -- dp[i][j] = LCS length of lines1[1..i] and lines2[1..j]
    local dp = {}
    for r = 0, m do
        dp[r] = {}
        for c = 0, n do
            dp[r][c] = 0
        end
    end

    for r = 1, m do
        for c = 1, n do
            if lines1[r] == lines2[c] then
                dp[r][c] = dp[r-1][c-1] + 1
            else
                local a = dp[r-1][c]
                local b = dp[r][c-1]
                dp[r][c] = a > b and a or b
            end
        end
    end

    -- Backtrack to get edit script as list of operations
    -- op: "=" (common), "-" (only in file1), "+" (only in file2)
    local edits = {}
    local r = m
    local c = n
    while r > 0 or c > 0 do
        if r > 0 and c > 0 and lines1[r] == lines2[c] then
            table.insert(edits, 1, {"=", lines1[r]})
            r = r - 1
            c = c - 1
        elseif c > 0 and (r == 0 or dp[r][c-1] >= dp[r-1][c]) then
            table.insert(edits, 1, {"+", lines2[c]})
            c = c - 1
        else
            table.insert(edits, 1, {"-", lines1[r]})
            r = r - 1
        end
    end

    -- Check if files are identical
    local has_diff = false
    for _, e in ipairs(edits) do
        if e[1] ~= "=" then
            has_diff = true
            break
        end
    end

    if not has_diff then
        return 0
    end

    -- Print unified diff header
    sys.write(STDOUT, "--- a/"..file1.."\t\n")
    sys.write(STDOUT, "+++ b/"..file2.."\t\n")

    local CONTEXT = 3

    -- Convert edits to hunks
    -- First, assign line numbers in each file to each edit
    local edit_info = {}
    local l1 = 0
    local l2 = 0
    for _, e in ipairs(edits) do
        local op = e[1]
        local line = e[2]
        if op == "=" then
            l1 = l1 + 1
            l2 = l2 + 1
            table.insert(edit_info, {op=op, line=line, l1=l1, l2=l2})
        elseif op == "-" then
            l1 = l1 + 1
            table.insert(edit_info, {op=op, line=line, l1=l1, l2=nil})
        elseif op == "+" then
            l2 = l2 + 1
            table.insert(edit_info, {op=op, line=line, l1=nil, l2=l2})
        end
    end

    -- Find change positions
    local change_indices = {}
    for idx, e in ipairs(edit_info) do
        if e.op ~= "=" then
            table.insert(change_indices, idx)
        end
    end

    -- Group changes into hunks by context window
    local hunks = {}
    local ci = 1
    while ci <= #change_indices do
        local start_idx = change_indices[ci]
        local end_idx = change_indices[ci]
        -- Expand to include nearby changes within 2*CONTEXT
        while ci + 1 <= #change_indices and change_indices[ci+1] <= end_idx + 2 * CONTEXT do
            ci = ci + 1
            end_idx = change_indices[ci]
        end
        -- Add context
        local hunk_start = start_idx - CONTEXT
        if hunk_start < 1 then hunk_start = 1 end
        local hunk_end = end_idx + CONTEXT
        if hunk_end > #edit_info then hunk_end = #edit_info end
        table.insert(hunks, {hunk_start, hunk_end})
        ci = ci + 1
    end

    -- Print hunks
    for _, hunk in ipairs(hunks) do
        local hs = hunk[1]
        local he = hunk[2]

        -- Compute line ranges
        local old_start, old_count, new_start, new_count
        old_count = 0
        new_count = 0
        old_start = nil
        new_start = nil

        for idx = hs, he do
            local e = edit_info[idx]
            if e.op == "=" or e.op == "-" then
                old_count = old_count + 1
                if not old_start then old_start = e.l1 end
            end
            if e.op == "=" or e.op == "+" then
                new_count = new_count + 1
                if not new_start then new_start = e.l2 end
            end
        end

        if not old_start then old_start = 0 end
        if not new_start then new_start = 0 end

        sys.write(STDOUT, string.format("@@ -%d,%d +%d,%d @@\n",
            old_start, old_count, new_start, new_count))

        for idx = hs, he do
            local e = edit_info[idx]
            if e.op == "=" then
                sys.write(STDOUT, " "..e.line.."\n")
            elseif e.op == "-" then
                sys.write(STDOUT, "-"..e.line.."\n")
            elseif e.op == "+" then
                sys.write(STDOUT, "+"..e.line.."\n")
            end
        end
    end

    return 1  -- files differ
end
