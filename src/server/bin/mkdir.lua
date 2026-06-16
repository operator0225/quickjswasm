return function(proc, sys, argv)
    local parents = false
    local verbose = false
    local dirs = {}

    local i = 1
    while i <= #argv do
        local arg = argv[i]
        if arg == "--" then
            i = i + 1
            while i <= #argv do
                table.insert(dirs, argv[i])
                i = i + 1
            end
            break
        elseif string.sub(arg, 1, 1) == "-" and #arg > 1 then
            for j = 2, #arg do
                local c = string.sub(arg, j, j)
                if c == "p" then parents = true
                elseif c == "v" then verbose = true
                end
            end
        else
            table.insert(dirs, arg)
        end
        i = i + 1
    end

    if #dirs == 0 then
        sys.write(STDERR, "mkdir: missing operand\nUsage: mkdir [-pv] directory...\n")
        return 2
    end

    local function resolvePath(path)
        if string.sub(path, 1, 1) == "/" then
            return path
        else
            return proc.cwd .. "/" .. path
        end
    end

    local function mkdirOne(path)
        local _, err = sys.mkdir(path)
        if err ~= nil then
            sys.write(STDERR, "mkdir: cannot create directory '" .. path .. "': " .. tostring(err) .. "\n")
            return false
        end
        if verbose then
            sys.write(STDOUT, "mkdir: created directory '" .. path .. "'\n")
        end
        return true
    end

    local function mkdirParents(path)
        -- Build list of components to create
        local parts = {}
        local p = path
        -- Normalize trailing slashes
        while string.sub(p, #p, #p) == "/" and #p > 1 do
            p = string.sub(p, 1, #p - 1)
        end

        local isAbs = string.sub(p, 1, 1) == "/"
        local prefix = isAbs and "/" or ""
        if isAbs then p = string.sub(p, 2) end

        local components = {}
        for part in string.gmatch(p, "[^/]+") do
            table.insert(components, part)
        end

        local current = prefix
        for ci, part in ipairs(components) do
            if ci == 1 and not isAbs then
                current = part
            else
                if current == "" then
                    current = part
                else
                    current = current .. "/" .. part
                end
            end
            local inode = sys.stat(current)
            if inode == nil then
                if not mkdirOne(current) then
                    return false
                end
            end
        end
        return true
    end

    local exitCode = 0
    for _, dir in ipairs(dirs) do
        local fullPath = resolvePath(dir)
        if parents then
            if not mkdirParents(fullPath) then
                exitCode = 1
            end
        else
            if not mkdirOne(fullPath) then
                exitCode = 1
            end
        end
    end

    return exitCode
end
