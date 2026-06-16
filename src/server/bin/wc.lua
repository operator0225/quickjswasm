return function(proc, sys, argv)
    local countLines = false
    local countWords = false
    local countBytes = false
    local countChars = false
    local files = {}
    local flagsSet = false

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
        elseif string.sub(arg, 1, 1) == "-" and #arg > 1 then
            for j = 2, #arg do
                local c = string.sub(arg, j, j)
                if c == "l" then countLines = true; flagsSet = true
                elseif c == "w" then countWords = true; flagsSet = true
                elseif c == "c" then countBytes = true; flagsSet = true
                elseif c == "m" then countChars = true; flagsSet = true
                end
            end
        else
            table.insert(files, arg)
        end
        i = i + 1
    end

    -- Default: all three
    if not flagsSet then
        countLines = true
        countWords = true
        countBytes = true
    end

    -- -m and -c are the same in our impl
    if countChars then countBytes = true end

    local function resolvePath(path)
        if string.sub(path, 1, 1) == "/" then
            return path
        else
            return proc.cwd .. "/" .. path
        end
    end

    local function countData(data)
        local lines = 0
        local words = 0
        local bytes = #data

        -- Count lines
        local pos = 1
        while pos <= #data do
            local nl = string.find(data, "\n", pos, true)
            if nl then
                lines = lines + 1
                pos = nl + 1
            else
                -- Last line without newline: don't count as line (POSIX behavior)
                -- Actually POSIX counts it if non-empty
                if pos <= #data then
                    -- partial last line - still count words on it
                end
                break
            end
        end

        -- Count words (sequences of non-whitespace)
        local inWord = false
        for ci = 1, #data do
            local b = string.byte(data, ci)
            local isSpace = (b == 32 or b == 9 or b == 10 or b == 13)
            if isSpace then
                if inWord then
                    words = words + 1
                    inWord = false
                end
            else
                inWord = true
            end
        end
        if inWord then words = words + 1 end

        return lines, words, bytes
    end

    local function formatCounts(lines, words, bytes, filename)
        local parts = {}
        if countLines then table.insert(parts, string.format("%7d", lines)) end
        if countWords then table.insert(parts, string.format("%7d", words)) end
        if countBytes then table.insert(parts, string.format("%7d", bytes)) end
        local out = table.concat(parts, "")
        if filename then
            out = out .. " " .. filename
        end
        sys.write(STDOUT, out .. "\n")
    end

    local totalLines = 0
    local totalWords = 0
    local totalBytes = 0
    local exitCode = 0
    local multipleFiles = #files > 1

    local function processData(data, filename)
        local lines, words, bytes = countData(data)
        totalLines = totalLines + lines
        totalWords = totalWords + words
        totalBytes = totalBytes + bytes
        formatCounts(lines, words, bytes, filename)
    end

    if #files == 0 then
        local allData = ""
        while true do
            local data = sys.read(STDIN, 65536)
            if data == nil or #data == 0 then break end
            allData = allData .. data
        end
        processData(allData, nil)
    else
        for _, fname in ipairs(files) do
            local fullPath = resolvePath(fname)
            local fd, err = sys.open(fullPath, {rdonly=true})
            if fd == nil then
                sys.write(STDERR, "wc: " .. fname .. ": " .. tostring(err) .. "\n")
                exitCode = 1
            else
                local allData = ""
                while true do
                    local data = sys.read(fd, 65536)
                    if data == nil or #data == 0 then break end
                    allData = allData .. data
                end
                sys.close(fd)
                processData(allData, fname)
            end
        end

        if multipleFiles then
            formatCounts(totalLines, totalWords, totalBytes, "total")
        end
    end

    return exitCode
end
