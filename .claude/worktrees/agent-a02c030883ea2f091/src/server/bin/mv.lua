return function(proc, sys, argv)
    local force = false
    local verbose = false
    local interactive = false
    local args = {}

    local i = 1
    while i <= #argv do
        local arg = argv[i]
        if arg == "--" then
            i = i + 1
            while i <= #argv do
                table.insert(args, argv[i])
                i = i + 1
            end
            break
        elseif string.sub(arg, 1, 1) == "-" and #arg > 1 then
            for j = 2, #arg do
                local c = string.sub(arg, j, j)
                if c == "f" then force = true
                elseif c == "v" then verbose = true
                elseif c == "i" then interactive = true
                end
            end
        else
            table.insert(args, arg)
        end
        i = i + 1
    end

    if #args < 2 then
        sys.write(STDERR, "mv: missing file operand\nUsage: mv [-fvi] source... dest\n")
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

    local function copyFile(src, dst)
        local fd_in, err = sys.open(src, {rdonly=true})
        if fd_in == nil then
            sys.write(STDERR, "mv: cannot open '" .. src .. "': " .. tostring(err) .. "\n")
            return false
        end
        local allData = ""
        while true do
            local data = sys.read(fd_in, 65536)
            if data == nil or #data == 0 then break end
            allData = allData .. data
        end
        sys.close(fd_in)

        local fd_out, werr = sys.open(dst, {create=true})
        if fd_out == nil then
            sys.write(STDERR, "mv: cannot create '" .. dst .. "': " .. tostring(werr) .. "\n")
            return false
        end
        sys.write(fd_out, allData)
        sys.close(fd_out)
        return true
    end

    local function copyDir(src, dst)
        local inode = sys.stat(dst)
        if inode == nil then
            local _, merr = sys.mkdir(dst)
            if merr ~= nil then
                sys.write(STDERR, "mv: cannot create directory '" .. dst .. "': " .. tostring(merr) .. "\n")
                return false
            end
        end

        local names, rerr = sys.readdir(src)
        if names == nil then
            sys.write(STDERR, "mv: cannot read directory '" .. src .. "': " .. tostring(rerr) .. "\n")
            return false
        end

        local ok = true
        for _, name in ipairs(names) do
            if name ~= "." and name ~= ".." then
                local srcChild = src .. "/" .. name
                local dstChild = dst .. "/" .. name
                if isDir(srcChild) then
                    if not copyDir(srcChild, dstChild) then ok = false end
                else
                    if not copyFile(srcChild, dstChild) then ok = false end
                end
            end
        end
        return ok
    end

    local function removeAll(path)
        if isDir(path) then
            local names = sys.readdir(path)
            if names then
                for _, name in ipairs(names) do
                    if name ~= "." and name ~= ".." then
                        removeAll(path .. "/" .. name)
                    end
                end
            end
        end
        sys.unlink(path)
    end

    local function moveOne(src, dst)
        -- Check if dest exists
        local dstStat = sys.stat(dst)
        if dstStat ~= nil and not force then
            if interactive then
                if not promptYN("mv: overwrite '" .. dst .. "'? ") then
                    return true
                end
            end
        end

        -- Try rename first
        local _, rerr = sys.rename(src, dst)
        if rerr == nil then
            if verbose then
                sys.write(STDOUT, "'" .. src .. "' -> '" .. dst .. "'\n")
            end
            return true
        end

        -- Fallback: copy + delete
        local srcStat = sys.stat(src)
        if srcStat == nil then
            sys.write(STDERR, "mv: cannot stat '" .. src .. "'\n")
            return false
        end

        local ok
        if math.floor(srcStat.mode / 4096) % 16 == 4 then
            ok = copyDir(src, dst)
        else
            ok = copyFile(src, dst)
        end

        if not ok then return false end
        removeAll(src)

        if verbose then
            sys.write(STDOUT, "'" .. src .. "' -> '" .. dst .. "'\n")
        end
        return true
    end

    local dest = resolvePath(args[#args])
    local sources = {}
    for si = 1, #args - 1 do
        table.insert(sources, resolvePath(args[si]))
    end

    local destIsDir = isDir(dest)

    if #sources > 1 and not destIsDir then
        sys.write(STDERR, "mv: target '" .. dest .. "' is not a directory\n")
        return 1
    end

    local exitCode = 0
    for _, src in ipairs(sources) do
        local srcStat = sys.stat(src)
        if srcStat == nil then
            sys.write(STDERR, "mv: cannot stat '" .. src .. "': No such file or directory\n")
            exitCode = 1
        else
            local dstPath = dest
            if destIsDir then
                local name = string.match(src, "([^/]+)$") or src
                dstPath = dest .. "/" .. name
            end
            if not moveOne(src, dstPath) then
                exitCode = 1
            end
        end
    end

    return exitCode
end
