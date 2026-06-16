return function(proc, sys, argv)
    local delim = "\t"
    local fields_spec = nil
    local chars_spec = nil
    local files = {}
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "-d" then
            i = i + 1
            if not argv[i] then
                sys.write(STDERR, "cut: option requires an argument -- d\n")
                return 2
            end
            delim = argv[i]
        elseif a == "-f" then
            i = i + 1
            if not argv[i] then
                sys.write(STDERR, "cut: option requires an argument -- f\n")
                return 2
            end
            fields_spec = argv[i]
        elseif a == "-c" then
            i = i + 1
            if not argv[i] then
                sys.write(STDERR, "cut: option requires an argument -- c\n")
                return 2
            end
            chars_spec = argv[i]
        elseif string.sub(a, 1, 2) == "-d" and #a > 2 then
            delim = string.sub(a, 3)
        elseif string.sub(a, 1, 2) == "-f" and #a > 2 then
            fields_spec = string.sub(a, 3)
        elseif string.sub(a, 1, 2) == "-c" and #a > 2 then
            chars_spec = string.sub(a, 3)
        elseif a == "--" then
            i = i + 1
            while i <= #argv do
                table.insert(files, argv[i])
                i = i + 1
            end
            break
        elseif string.sub(a, 1, 1) == "-" then
            sys.write(STDERR, "cut: invalid option -- '"..string.sub(a,2).."'\n")
            return 2
        else
            table.insert(files, a)
        end
        i = i + 1
    end

    if not fields_spec and not chars_spec then
        sys.write(STDERR, "cut: you must specify a list of bytes, characters, or fields\n")
        return 2
    end

    -- Parse a range spec like "1,3-5,7" into a set of positions
    local function parse_ranges(spec)
        local positions = {}
        for part in string.gmatch(spec, "[^,]+") do
            local s, e = string.match(part, "^(%d+)-(%d+)$")
            if s and e then
                for p = tonumber(s), tonumber(e) do
                    positions[p] = true
                end
            else
                local n = string.match(part, "^(%d+)$")
                if n then
                    positions[tonumber(n)] = true
                else
                    -- open-ended like "3-"
                    local from = string.match(part, "^(%d+)-$")
                    if from then
                        -- store as open range marker
                        positions["open_from"] = tonumber(from)
                    else
                        local to = string.match(part, "^-(%d+)$")
                        if to then
                            for p = 1, tonumber(to) do
                                positions[p] = true
                            end
                        end
                    end
                end
            end
        end
        return positions
    end

    local function pos_selected(positions, p)
        if positions[p] then return true end
        if positions["open_from"] and p >= positions["open_from"] then return true end
        return false
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

    local function process_line(line)
        if chars_spec then
            local positions = parse_ranges(chars_spec)
            local out = {}
            for p = 1, #line do
                if pos_selected(positions, p) then
                    table.insert(out, string.sub(line, p, p))
                end
            end
            sys.write(STDOUT, table.concat(out).."\n")
        elseif fields_spec then
            local positions = parse_ranges(fields_spec)
            -- Split by delim
            local field_list = {}
            local p = 1
            while true do
                local s, e = string.find(line, delim, p, true)
                if s then
                    table.insert(field_list, string.sub(line, p, s - 1))
                    p = e + 1
                else
                    table.insert(field_list, string.sub(line, p))
                    break
                end
            end
            if #field_list == 1 and not string.find(line, delim, 1, true) then
                -- No delimiter found: print whole line
                sys.write(STDOUT, line.."\n")
                return
            end
            local out = {}
            for fi = 1, #field_list do
                if pos_selected(positions, fi) then
                    table.insert(out, field_list[fi])
                end
            end
            sys.write(STDOUT, table.concat(out, delim).."\n")
        end
    end

    local function process_content(content)
        local pos = 1
        local len = #content
        while pos <= len do
            local nl = string.find(content, "\n", pos, true)
            if nl then
                process_line(string.sub(content, pos, nl - 1))
                pos = nl + 1
            else
                local rest = string.sub(content, pos)
                if #rest > 0 then
                    process_line(rest)
                end
                break
            end
        end
    end

    local exit_code = 0

    if #files == 0 then
        local content = read_all(STDIN)
        process_content(content)
    else
        for _, f in ipairs(files) do
            local path = resolve(f)
            local fd, err = sys.open(path, {rdonly=true})
            if not fd then
                sys.write(STDERR, "cut: '"..f.."': No such file or directory\n")
                exit_code = 1
            else
                local content = read_all(fd)
                sys.close(fd)
                process_content(content)
            end
        end
    end

    return exit_code
end
