return function(proc, sys, argv)
    local n_lines = nil
    local n_bytes = nil
    local files = {}
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "-n" then
            i = i + 1
            if not argv[i] then
                sys.write(STDERR, "head: option requires an argument -- n\n")
                return 2
            end
            n_lines = tonumber(argv[i])
            if not n_lines then
                sys.write(STDERR, "head: invalid number of lines: '"..argv[i].."'\n")
                return 1
            end
        elseif a == "-c" then
            i = i + 1
            if not argv[i] then
                sys.write(STDERR, "head: option requires an argument -- c\n")
                return 2
            end
            n_bytes = tonumber(argv[i])
            if not n_bytes then
                sys.write(STDERR, "head: invalid number of bytes: '"..argv[i].."'\n")
                return 1
            end
        elseif string.sub(a, 1, 2) == "-n" and #a > 2 then
            n_lines = tonumber(string.sub(a, 3))
            if not n_lines then
                sys.write(STDERR, "head: invalid number of lines: '"..string.sub(a,3).."'\n")
                return 1
            end
        elseif string.sub(a, 1, 2) == "-c" and #a > 2 then
            n_bytes = tonumber(string.sub(a, 3))
            if not n_bytes then
                sys.write(STDERR, "head: invalid number of bytes: '"..string.sub(a,3).."'\n")
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
            sys.write(STDERR, "head: invalid option -- '"..string.sub(a,2).."'\n")
            return 2
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

    local function process(content, label, show_label)
        if show_label then
            sys.write(STDOUT, "==> "..label.." <==\n")
        end
        if n_bytes then
            local out = string.sub(content, 1, n_bytes)
            sys.write(STDOUT, out)
        else
            local count = 0
            local pos = 1
            local len = #content
            while pos <= len and count < n_lines do
                local nl = string.find(content, "\n", pos, true)
                if nl then
                    sys.write(STDOUT, string.sub(content, pos, nl))
                    pos = nl + 1
                    count = count + 1
                else
                    sys.write(STDOUT, string.sub(content, pos))
                    break
                end
            end
        end
    end

    local exit_code = 0
    local show_label = #files > 1

    if #files == 0 then
        local content = read_all(STDIN)
        process(content, "stdin", false)
    else
        for idx, f in ipairs(files) do
            local path = resolve(f)
            local fd, err = sys.open(path, {rdonly=true})
            if not fd then
                sys.write(STDERR, "head: cannot open '"..f.."' for reading: No such file or directory\n")
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
    end

    return exit_code
end
