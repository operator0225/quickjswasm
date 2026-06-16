return function(proc, sys, argv)
    local count_flag = false
    local dup_only = false
    local unique_only = false
    local ignore_case = false
    local files = {}
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "-c" then
            count_flag = true
        elseif a == "-d" then
            dup_only = true
        elseif a == "-u" then
            unique_only = true
        elseif a == "-i" then
            ignore_case = true
        elseif a == "--" then
            i = i + 1
            while i <= #argv do
                table.insert(files, argv[i])
                i = i + 1
            end
            break
        elseif string.sub(a, 1, 1) == "-" then
            -- combined flags
            local flags = string.sub(a, 2)
            local ok = true
            for ci = 1, #flags do
                local ch = string.sub(flags, ci, ci)
                if ch == "c" then count_flag = true
                elseif ch == "d" then dup_only = true
                elseif ch == "u" then unique_only = true
                elseif ch == "i" then ignore_case = true
                else ok = false end
            end
            if not ok then
                sys.write(STDERR, "uniq: invalid option -- '"..string.sub(a,2).."'\n")
                return 2
            end
        else
            table.insert(files, a)
        end
        i = i + 1
    end

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

    local content
    local exit_code = 0

    if #files == 0 then
        content = read_all(STDIN)
    elseif #files == 1 then
        local path = resolve(files[1])
        local fd, err = sys.open(path, {rdonly=true})
        if not fd then
            sys.write(STDERR, "uniq: '"..files[1].."': No such file or directory\n")
            return 1
        end
        content = read_all(fd)
        sys.close(fd)
    else
        -- uniq takes at most 2 args (input and output), but we'll just read first
        local path = resolve(files[1])
        local fd, err = sys.open(path, {rdonly=true})
        if not fd then
            sys.write(STDERR, "uniq: '"..files[1].."': No such file or directory\n")
            return 1
        end
        content = read_all(fd)
        sys.close(fd)
    end

    -- Split into lines
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

    -- Process adjacent duplicates
    local groups = {}
    local gi = 1
    while gi <= #lines do
        local orig = lines[gi]
        local cmp = ignore_case and string.lower(orig) or orig
        local cnt = 1
        while gi + cnt <= #lines do
            local next_cmp = ignore_case and string.lower(lines[gi + cnt]) or lines[gi + cnt]
            if next_cmp == cmp then
                cnt = cnt + 1
            else
                break
            end
        end
        table.insert(groups, {line=orig, count=cnt})
        gi = gi + cnt
    end

    for _, g in ipairs(groups) do
        local should_print = true
        if dup_only and g.count == 1 then should_print = false end
        if unique_only and g.count > 1 then should_print = false end
        if should_print then
            if count_flag then
                sys.write(STDOUT, string.format("%7d %s\n", g.count, g.line))
            else
                sys.write(STDOUT, g.line.."\n")
            end
        end
    end

    return exit_code
end
