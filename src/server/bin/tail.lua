return function(proc, sys, argv)
    local n_lines = nil
    local n_bytes = nil
    local follow = false
    local files = {}
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "-n" then
            i = i + 1
            if not argv[i] then
                sys.write(STDERR, "tail: option requires an argument -- n\n")
                return 2
            end
            n_lines = tonumber(argv[i])
            if not n_lines then
                sys.write(STDERR, "tail: invalid number of lines: '"..argv[i].."'\n")
                return 1
            end
        elseif a == "-c" then
            i = i + 1
            if not argv[i] then
                sys.write(STDERR, "tail: option requires an argument -- c\n")
                return 2
            end
            n_bytes = tonumber(argv[i])
            if not n_bytes then
                sys.write(STDERR, "tail: invalid number of bytes: '"..argv[i].."'\n")
                return 1
            end
        elseif a == "-f" then
            follow = true
        elseif string.sub(a, 1, 2) == "-n" and #a > 2 then
            n_lines = tonumber(string.sub(a, 3))
            if not n_lines then
                sys.write(STDERR, "tail: invalid number of lines: '"..string.sub(a,3).."'\n")
                return 1
            end
        elseif string.sub(a, 1, 2) == "-c" and #a > 2 then
            n_bytes = tonumber(string.sub(a, 3))
            if not n_bytes then
                sys.write(STDERR, "tail: invalid number of bytes: '"..string.sub(a,3).."'\n")
                return 1
            end
        elseif a == "--" then
            i = i + 1
            while i <= #argv do
                table.insert(files, argv[i])
                i = i + 1
            end
            break
        elseif string.sub(a, 1, 1) == "-" then
            -- handle combined flags like -fn
            local flags = string.sub(a, 2)
            local unknown = false
            for ci = 1, #flags do
                local ch = string.sub(flags, ci, ci)
                if ch == "f" then
                    follow = true
                else
                    unknown = true
                end
            end
            if unknown then
                sys.write(STDERR, "tail: invalid option -- '"..string.sub(a,2).."'\n")
                return 2
            end
        else
            table.insert(files, a)
        end
        i = i + 1
    end

    if n_bytes == nil and n_lines == nil then
        n_lines = 10
    end

    local function resolve(path)
        if string.sub(path, 1, 1) == "/" then return path end
        return proc.cwd.."/"..path
    end

    local function read_all(fd)
        local chunks = {}
        while true do
            local data, err = sys.read(fd, 4096)
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
                table.insert(lines, string.sub(content, pos, nl))
                pos = nl + 1
            else
                local tail_str = string.sub(content, pos)
                if #tail_str > 0 then
                    table.insert(lines, tail_str)
                end
                break
            end
        end
        return lines
    end

    local function process(content, label, show_label)
        if show_label then
            sys.write(STDOUT, "==> "..label.." <==\n")
        end
        if n_bytes then
            local start = #content - n_bytes + 1
            if start < 1 then start = 1 end
            sys.write(STDOUT, string.sub(content, start))
        else
            local lines = split_lines(content)
            local start = #lines - n_lines + 1
            if start < 1 then start = 1 end
            for li = start, #lines do
                sys.write(STDOUT, lines[li])
            end
        end
    end

    local exit_code = 0
    local show_label = #files > 1

    if #files == 0 then
        local content = read_all(STDIN)
        process(content, "stdin", false)
        if follow then
            while true do
                local data, err = sys.read(STDIN, 4096)
                if data and #data > 0 then
                    sys.write(STDOUT, data)
                end
            end
        end
    else
        for idx, f in ipairs(files) do
            local path = resolve(f)
            local fd, err = sys.open(path, {rdonly=true})
            if not fd then
                sys.write(STDERR, "tail: cannot open '"..f.."' for reading: No such file or directory\n")
                exit_code = 1
            else
                if idx > 1 and show_label then
                    sys.write(STDOUT, "\n")
                end
                local content = read_all(fd)
                sys.close(fd)
                process(content, f, show_label)
            end
        end
        if follow and exit_code == 0 then
            -- Follow the last file
            local last_file = files[#files]
            local path = resolve(last_file)
            local fd, err = sys.open(path, {rdonly=true})
            if fd then
                -- Seek to end by reading all first
                while true do
                    local data, rerr = sys.read(fd, 4096)
                    if not data or #data == 0 then break end
                end
                -- Now loop reading new data
                while true do
                    local data, rerr = sys.read(fd, 4096)
                    if data and #data > 0 then
                        sys.write(STDOUT, data)
                    end
                end
            end
        end
    end

    return exit_code
end
