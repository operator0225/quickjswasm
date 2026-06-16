return function(proc, sys, argv)
    local lineNumbers = false
    local caseInsensitive = false
    local recursive = false
    local filesOnly = false
    local countOnly = false
    local invertMatch = false
    local fixedString = false
    local colorHighlight = false
    local pattern = nil
    local files = {}

    local i = 1
    while i <= #argv do
        local arg = argv[i]
        if arg == "--" then
            i = i + 1
            while i <= #argv do
                table.insert(files, argv[i])
                i = i + 1
            end
            break
        elseif arg == "--color" or arg == "--colour" or arg == "--color=always" then
            colorHighlight = true
        elseif string.sub(arg, 1, 1) == "-" and #arg > 1 then
            local j = 2
            while j <= #arg do
                local c = string.sub(arg, j, j)
                if c == "n" then lineNumbers = true
                elseif c == "i" then caseInsensitive = true
                elseif c == "r" or c == "R" then recursive = true
                elseif c == "l" then filesOnly = true
                elseif c == "c" then countOnly = true
                elseif c == "v" then invertMatch = true
                elseif c == "F" then fixedString = true
                elseif c == "E" then -- Lua patterns used anyway
                elseif c == "e" then
                    j = j + 1
                    if j <= #arg then
                        pattern = string.sub(arg, j)
                        j = #arg + 1
                    else
                        i = i + 1
                        pattern = argv[i]
                    end
                end
                j = j + 1
            end
        else
            if pattern == nil then
                pattern = arg
            else
                table.insert(files, arg)
            end
        end
        i = i + 1
    end

    if pattern == nil then
        sys.write(STDERR, "grep: missing pattern\nUsage: grep [-nircvlcF] [--color] pattern [file...]\n")
        return 2
    end

    local function resolvePath(path)
        if string.sub(path, 1, 1) == "/" then
            return path
        else
            return proc.cwd .. "/" .. path
        end
    end

    local function escapePattern(s)
        return string.gsub(s, "([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
    end

    local luaPattern
    if fixedString then
        luaPattern = escapePattern(pattern)
    else
        luaPattern = pattern
    end

    local matchPattern = luaPattern
    if caseInsensitive then
        -- Build case-insensitive version by replacing alpha chars
        local ciPat = ""
        local k = 1
        while k <= #matchPattern do
            local c = string.sub(matchPattern, k, k)
            local b = string.byte(c)
            if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then
                local lo = string.lower(c)
                local hi = string.upper(c)
                ciPat = ciPat .. "[" .. lo .. hi .. "]"
            else
                ciPat = ciPat .. c
            end
            k = k + 1
        end
        matchPattern = ciPat
    end

    local function matchLine(line)
        local testLine = line
        local s, e = string.find(testLine, matchPattern)
        return s ~= nil, s, e
    end

    local exitCode = 1  -- 1 = no match found
    local multipleFiles = false

    local function grepData(data, filename)
        local lineNum = 0
        local matchCount = 0
        local pos = 1
        local fileMatched = false

        while pos <= #data do
            local nl = string.find(data, "\n", pos, true)
            local line
            if nl then
                line = string.sub(data, pos, nl - 1)
                pos = nl + 1
            else
                line = string.sub(data, pos)
                pos = #data + 1
            end
            lineNum = lineNum + 1

            local matched, ms, me = matchLine(line)
            if invertMatch then matched = not matched; ms = nil; me = nil end

            if matched then
                exitCode = 0
                fileMatched = true
                matchCount = matchCount + 1

                if not filesOnly and not countOnly then
                    local out = ""
                    if multipleFiles and filename then
                        out = "\27[35m" .. filename .. "\27[0m:"
                    end
                    if lineNumbers then
                        out = out .. "\27[32m" .. tostring(lineNum) .. "\27[0m:"
                    end
                    if colorHighlight and ms ~= nil and not invertMatch then
                        out = out .. string.sub(line, 1, ms - 1) ..
                              "\27[31m" .. string.sub(line, ms, me) .. "\27[0m" ..
                              string.sub(line, me + 1)
                    else
                        out = out .. line
                    end
                    sys.write(STDOUT, out .. "\n")
                end
            end
        end

        if filesOnly and fileMatched then
            sys.write(STDOUT, (filename or "(standard input)") .. "\n")
        end
        if countOnly then
            local prefix = ""
            if multipleFiles and filename then
                prefix = filename .. ":"
            end
            sys.write(STDOUT, prefix .. tostring(matchCount) .. "\n")
        end
    end

    local function grepFile(path, filename)
        local fd, err = sys.open(path, {rdonly=true})
        if fd == nil then
            sys.write(STDERR, "grep: " .. filename .. ": " .. tostring(err) .. "\n")
            return
        end
        local allData = ""
        while true do
            local data = sys.read(fd, 65536)
            if data == nil or #data == 0 then break end
            allData = allData .. data
        end
        sys.close(fd)
        grepData(allData, filename)
    end

    local function isDir(path)
        local inode = sys.stat(path)
        if inode == nil then return false end
        return math.floor(inode.mode / 4096) % 16 == 4
    end

    local function grepDir(dirPath, prefix)
        local names, err = sys.readdir(dirPath)
        if names == nil then
            sys.write(STDERR, "grep: " .. dirPath .. ": " .. tostring(err) .. "\n")
            return
        end
        table.sort(names)
        for _, name in ipairs(names) do
            if name ~= "." and name ~= ".." then
                local fullPath = dirPath .. "/" .. name
                local displayName = prefix .. "/" .. name
                if isDir(fullPath) then
                    grepDir(fullPath, displayName)
                else
                    grepFile(fullPath, displayName)
                end
            end
        end
    end

    if #files == 0 then
        multipleFiles = false
        local allData = ""
        while true do
            local data = sys.read(STDIN, 65536)
            if data == nil or #data == 0 then break end
            allData = allData .. data
        end
        grepData(allData, nil)
    else
        multipleFiles = #files > 1
        for _, fname in ipairs(files) do
            local fullPath = resolvePath(fname)
            if isDir(fullPath) then
                if recursive then
                    grepDir(fullPath, fname)
                else
                    sys.write(STDERR, "grep: " .. fname .. ": Is a directory\n")
                end
            else
                grepFile(fullPath, fname)
            end
        end
    end

    return exitCode
end
