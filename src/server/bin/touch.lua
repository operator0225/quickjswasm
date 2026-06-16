return function(proc, sys, argv)
    local atimeOnly = false
    local mtimeOnly = false
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
        elseif arg == "-t" then
            -- Consume the timestamp argument (ignored in our VFS)
            i = i + 1
        elseif string.sub(arg, 1, 1) == "-" and #arg > 1 then
            for j = 2, #arg do
                local c = string.sub(arg, j, j)
                if c == "a" then atimeOnly = true
                elseif c == "m" then mtimeOnly = true
                end
            end
        else
            table.insert(files, arg)
        end
        i = i + 1
    end

    if #files == 0 then
        sys.write(STDERR, "touch: missing file operand\nUsage: touch [-am] [-t timestamp] file...\n")
        return 2
    end

    local function resolvePath(path)
        if string.sub(path, 1, 1) == "/" then
            return path
        else
            return proc.cwd .. "/" .. path
        end
    end

    local exitCode = 0
    for _, fname in ipairs(files) do
        local fullPath = resolvePath(fname)
        local inode = sys.stat(fullPath)
        if inode == nil then
            -- Create the file
            local fd, err = sys.open(fullPath, {create=true})
            if fd == nil then
                sys.write(STDERR, "touch: cannot touch '" .. fname .. "': " .. tostring(err) .. "\n")
                exitCode = 1
            else
                sys.close(fd)
            end
        else
            -- File exists: open and close to update mtime
            local fd, err = sys.open(fullPath, {create=false})
            if fd == nil then
                -- Try read-only open
                fd, err = sys.open(fullPath, {rdonly=true})
                if fd == nil then
                    sys.write(STDERR, "touch: cannot touch '" .. fname .. "': " .. tostring(err) .. "\n")
                    exitCode = 1
                else
                    sys.close(fd)
                end
            else
                sys.close(fd)
            end
        end
    end

    return exitCode
end
