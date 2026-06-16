return function(proc, sys, argv)
    local numeric = false
    local reverse = false
    local field_k = nil
    local separator = nil
    local unique = false
    local fold_case = false
    local files = {}
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "-n" then
            numeric = true
        elseif a == "-r" then
            reverse = true
        elseif a == "-u" then
            unique = true
        elseif a == "-f" then
            fold_case = true
        elseif a == "-k" then
            i = i + 1
            if not argv[i] then
                sys.write(STDERR, "sort: option requires an argument -- k\n")
                return 2
            end
            field_k = tonumber(argv[i])
            if not field_k then
                sys.write(STDERR, "sort: invalid field number: '"..argv[i].."'\n")
                return 1
            end
        elseif a == "-t" then
            i = i + 1
            if not argv[i] then
                sys.write(STDERR, "sort: option requires an argument -- t\n")
                return 2
            end
            separator = argv[i]
        elseif string.sub(a, 1, 2) == "-k" and #a > 2 then
            field_k = tonumber(string.sub(a, 3))
            if not field_k then
                sys.write(STDERR, "sort: invalid field number: '"..string.sub(a,3).."'\n")
                return 1
            end
        elseif string.sub(a, 1, 2) == "-t" and #a > 2 then
            separator = string.sub(a, 3)
        elseif a == "--" then
            i = i + 1
            while i <= #argv do
                table.insert(files, argv[i])
                i = i + 1
            end
            break
        elseif string.sub(a, 1, 1) == "-" then
            -- try combined single-char flags
            local flags = string.sub(a, 2)
            local ok = true
            for ci = 1, #flags do
                local ch = string.sub(flags, ci, ci)
                if ch == "n" then numeric = true
                elseif ch == "r" then reverse = true
                elseif ch == "u" then unique = true
                elseif ch == "f" then fold_case = true
                else ok = false end
            end
            if not ok then
                sys.write(STDERR, "sort: invalid option -- '"..string.sub(a,2).."'\n")
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

    local content_parts = {}
    local exit_code = 0

    if #files == 0 then
        table.insert(content_parts, read_all(STDIN))
    else
        for _, f in ipairs(files) do
            local path = resolve(f)
            local fd, err = sys.open(path, {rdonly=true})
            if not fd then
                sys.write(STDERR, "sort: cannot read: '"..f.."': No such file or directory\n")
                exit_code = 1
            else
                table.insert(content_parts, read_all(fd))
                sys.close(fd)
            end
        end
    end

    local content = table.concat(content_parts)

    -- Split into lines (strip trailing newline if present)
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

    local function get_key(line)
        if field_k then
            local fields = {}
            if separator then
                local p = 1
                while true do
                    local s, e = string.find(line, separator, p, true)
                    if s then
                        table.insert(fields, string.sub(line, p, s-1))
                        p = e + 1
                    else
                        table.insert(fields, string.sub(line, p))
                        break
                    end
                end
            else
                for w in string.gmatch(line, "%S+") do
                    table.insert(fields, w)
                end
            end
            local key = fields[field_k] or ""
            return key
        end
        return line
    end

    table.sort(lines, function(a, b)
        local ka = get_key(a)
        local kb = get_key(b)
        if fold_case then
            ka = string.lower(ka)
            kb = string.lower(kb)
        end
        local result
        if numeric then
            local na = tonumber(ka) or 0
            local nb = tonumber(kb) or 0
            result = na < nb
        else
            result = ka < kb
        end
        if reverse then
            return not result and (ka ~= kb)
        end
        return result
    end)

    if unique then
        local seen = {}
        local deduped = {}
        for _, line in ipairs(lines) do
            local key = fold_case and string.lower(line) or line
            if not seen[key] then
                seen[key] = true
                table.insert(deduped, line)
            end
        end
        lines = deduped
    end

    for _, line in ipairs(lines) do
        sys.write(STDOUT, line.."\n")
    end

    return exit_code
end
