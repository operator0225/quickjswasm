return function(proc, sys, argv)
    local recursive = false
    local force = false
    local verbose = false
    local interactive = false
    local targets = {}

    local i = 1
    while i <= #argv do
        local arg = argv[i]
        if arg == "--" then
            i = i + 1
            while i <= #argv do
                table.insert(targets, argv[i])
                i = i + 1
            end
            break
        elseif string.sub(arg, 1, 1) == "-" and #arg > 1 then
            for j = 2, #arg do
                local c = string.sub(arg, j, j)
                if c == "r" or c == "R" then recursive = true
                elseif c == "f" then force = true
                elseif c == "v" then verbose = true
                elseif c == "i" then interactive = true
                end
            end
        else
            table.insert(targets, arg)
        end
        i = i + 1
    end

    if #targets == 0 and not force then
        sys.write(STDERR, "rm: missing operand\nUsage: rm [-rfvi] file...\n")
        return 2
    end

    local function resolvePath(path)
        if string.sub(path, 1, 1) == "/" then
            return path
        else
            return proc.cwd .. "/" .. path
        end
    end

    local function isDir(path)
        local inode = sys.stat(path)
        if inode == nil then return false end
        return math.floor(inode.mode / 4096) % 16 == 4
    end

    local function promptYN(question)
        sys.write(STDOUT, question)
        local answer = sys.read(STDIN, 256)
        if answer == nil then return false end
        answer = string.lower(string.sub(answer, 1, 1))
        return answer == "y"
    end

    local exitCode = 0

    local function removeAll(path)
        if isDir(path) then
            if not recursive then
                sys.write(STDERR, "rm: cannot remove '" .. path .. "': Is a directory\n")
                exitCode = 1
                return
            end

            local names, rerr = sys.readdir(path)
            if names == nil then
                sys.write(STDERR, "rm: cannot read '" .. path .. "': " .. tostring(rerr) .. "\n")
                exitCode = 1
                return
            end

            for _, name in ipairs(names) do
                if name ~= "." and name ~= ".." then
                    removeAll(path .. "/" .. name)
                end
            end
        end

        if interactive then
            if not promptYN("rm: remove '" .. path .. "'? ") then
                return
            end
        end

        local _, err = sys.unlink(path)
        if err ~= nil then
            if not force then
                sys.write(STDERR, "rm: cannot remove '" .. path .. "': " .. tostring(err) .. "\n")
                exitCode = 1
            end
        else
            if verbose then
                sys.write(STDOUT, "removed '" .. path .. "'\n")
            end
        end
    end

    for _, target in ipairs(targets) do
        local fullPath = resolvePath(target)

        -- Safety check
        if fullPath == "/" then
            sys.write(STDERR, "rm: refusing to remove '/': use '--no-preserve-root' if you really mean it\n")
            exitCode = 1
        else
            local inode = sys.stat(fullPath)
            if inode == nil then
                if not force then
                    sys.write(STDERR, "rm: cannot remove '" .. target .. "': No such file or directory\n")
                    exitCode = 1
                end
            else
                removeAll(fullPath)
            end
        end
    end

    return exitCode
end
