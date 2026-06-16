return function(proc, sys, argv)
    local lineNumbers = false
    local showSpecial = false
    local showDollar = false
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
        elseif string.sub(arg, 1, 1) == "-" and #arg > 1 then
            for j = 2, #arg do
                local c = string.sub(arg, j, j)
                if c == "n" then lineNumbers = true
                elseif c == "A" then showSpecial = true; showDollar = true
                elseif c == "e" then showDollar = true
                end
            end
        else
            table.insert(files, arg)
        end
        i = i + 1
    end

    local function resolvePath(path)
        if string.sub(path, 1, 1) == "/" then
            return path
        else
            return proc.cwd .. "/" .. path
        end
    end

    local function processLine(line, lineNum)
        local out = ""
        if showSpecial then
            local result = ""
            for ci = 1, #line do
                local b = string.byte(line, ci)
                if b == 9 then
                    result = result .. "^I"
                elseif b < 32 and b ~= 9 then
                    result = result .. "^" .. string.char(b + 64)
                elseif b == 127 then
                    result = result .. "^?"
                else
                    result = result .. string.char(b)
                end
            end
            line = result
        end
        if lineNumbers then
            out = string.format("%6d\t", lineNum)
        end
        out = out .. line
        if showDollar then
            out = out .. "$"
        end
        return out .. "\n"
    end

    local function processData(data)
        local lineNum = 1
        local pos = 1
        local output = ""
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
            output = output .. processLine(line, lineNum)
            lineNum = lineNum + 1
        end
        -- If data ends with newline, we added an extra empty line above
        -- Remove it if data ends with \n
        if #data > 0 and string.sub(data, #data, #data) == "\n" then
            -- The last "line" after final \n is empty string, which we processed
            -- That's correct behavior for cat
        end
        return output
    end

    local function catFd(fd)
        local allData = ""
        while true do
            local data, err = sys.read(fd, 4096)
            if data == nil or #data == 0 then break end
            allData = allData .. data
        end
        -- Process line by line only if we need line numbers or special chars
        if lineNumbers or showSpecial or showDollar then
            local processed = processData(allData)
            sys.write(STDOUT, processed)
        else
            sys.write(STDOUT, allData)
        end
    end

    local exitCode = 0

    if #files == 0 then
        catFd(STDIN)
    else
        for _, fname in ipairs(files) do
            if fname == "-" then
                catFd(STDIN)
            else
                local path = resolvePath(fname)
                local fd, err = sys.open(path, {rdonly=true})
                if fd == nil then
                    sys.write(STDERR, "cat: " .. fname .. ": " .. tostring(err) .. "\n")
                    exitCode = 1
                else
                    catFd(fd)
                    sys.close(fd)
                end
            end
        end
    end

    return exitCode
end
