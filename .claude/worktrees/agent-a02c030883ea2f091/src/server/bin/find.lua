return function(proc, sys, argv)
    local paths = {}
    local name_pat = nil
    local type_filter = nil
    local size_filter = nil
    local maxdepth = nil
    local exec_cmd = nil  -- table of args up to \;

    local i = 1
    -- Collect starting paths (non-option args before first option)
    while i <= #argv do
        local a = argv[i]
        if string.sub(a, 1, 1) == "-" then
            break
        else
            table.insert(paths, a)
            i = i + 1
        end
    end

    if #paths == 0 then
        table.insert(paths, ".")
    end

    -- Parse options
    while i <= #argv do
        local a = argv[i]
        if a == "-name" then
            i = i + 1
            if not argv[i] then
                sys.write(STDERR, "find: missing argument to '-name'\n")
                return 2
            end
            name_pat = argv[i]
        elseif a == "-type" then
            i = i + 1
            if not argv[i] then
                sys.write(STDERR, "find: missing argument to '-type'\n")
                return 2
            end
            type_filter = argv[i]
        elseif a == "-size" then
            i = i + 1
            if not argv[i] then
                sys.write(STDERR, "find: missing argument to '-size'\n")
                return 2
            end
            size_filter = argv[i]
        elseif a == "-maxdepth" then
            i = i + 1
            if not argv[i] then
                sys.write(STDERR, "find: missing argument to '-maxdepth'\n")
                return 2
            end
            maxdepth = tonumber(argv[i])
            if not maxdepth then
                sys.write(STDERR, "find: invalid argument to '-maxdepth'\n")
                return 1
            end
        elseif a == "-print" then
            -- default action, ignore
        elseif a == "-exec" then
            i = i + 1
            exec_cmd = {}
            while i <= #argv do
                if argv[i] == "\\;" or argv[i] == ";" then
                    break
                end
                table.insert(exec_cmd, argv[i])
                i = i + 1
            end
        else
            -- ignore unknown options
        end
        i = i + 1
    end

    -- Convert glob pattern to lua pattern
    local function glob_to_pattern(glob)
        local pat = ""
        for ci = 1, #glob do
            local ch = string.sub(glob, ci, ci)
            if ch == "*" then
                pat = pat..".*"
            elseif ch == "?" then
                pat = pat.."."
            elseif ch == "." or ch == "+" or ch == "^" or ch == "$"
                or ch == "(" or ch == ")" or ch == "[" or ch == "]"
                or ch == "{" or ch == "}" or ch == "%" then
                pat = pat.."%"..ch
            else
                pat = pat..ch
            end
        end
        return "^"..pat.."$"
    end

    local function resolve(path)
        if string.sub(path, 1, 1) == "/" then return path end
        return proc.cwd.."/"..path
    end

    -- Parse size filter: +N, -N, N (in 512-byte blocks)
    local size_cmp = nil
    local size_val = nil
    if size_filter then
        local prefix = string.sub(size_filter, 1, 1)
        if prefix == "+" then
            size_cmp = "gt"
            size_val = tonumber(string.sub(size_filter, 2))
        elseif prefix == "-" then
            size_cmp = "lt"
            size_val = tonumber(string.sub(size_filter, 2))
        else
            size_cmp = "eq"
            size_val = tonumber(size_filter)
        end
        if size_val then
            size_val = size_val * 512
        end
    end

    local name_lua_pat = nil
    if name_pat then
        name_lua_pat = glob_to_pattern(name_pat)
    end

    local exit_code = 0

    local function traverse(path, display_path, depth)
        local stat, err = sys.stat(path)
        if not stat then
            sys.write(STDERR, "find: '"..display_path.."': No such file or directory\n")
            exit_code = 1
            return
        end

        local is_dir = (stat.mode and (math.floor(stat.mode / 0x4000) % 2 == 1))
        -- mode bits: directory bit is 0o040000 = 16384
        -- A simpler check: directories have mode & 0xF000 == 0x4000
        local mode_type = math.floor(stat.mode / 4096) % 16
        is_dir = (mode_type == 4)

        -- Get basename
        local basename = display_path
        local slash = string.find(display_path, "/[^/]*$")
        if slash then
            basename = string.sub(display_path, slash + 1)
        end

        -- Check filters
        local match = true

        if name_lua_pat then
            if not string.match(basename, name_lua_pat) then
                match = false
            end
        end

        if type_filter then
            if type_filter == "f" and is_dir then match = false end
            if type_filter == "d" and not is_dir then match = false end
        end

        if size_cmp and size_val then
            local fsize = stat.size or 0
            local blocks = math.ceil(fsize / 512)
            if size_cmp == "gt" and not (blocks > size_val / 512) then match = false end
            if size_cmp == "lt" and not (blocks < size_val / 512) then match = false end
            if size_cmp == "eq" and not (blocks == size_val / 512) then match = false end
        end

        if match then
            if exec_cmd then
                -- Print what would run
                local cmd_parts = {}
                for _, part in ipairs(exec_cmd) do
                    if part == "{}" then
                        table.insert(cmd_parts, display_path)
                    else
                        table.insert(cmd_parts, part)
                    end
                end
                sys.write(STDOUT, table.concat(cmd_parts, " ").."\n")
            else
                sys.write(STDOUT, display_path.."\n")
            end
        end

        if is_dir then
            if maxdepth and depth >= maxdepth then return end
            local entries, derr = sys.readdir(path)
            if entries then
                table.sort(entries)
                for _, entry in ipairs(entries) do
                    if entry ~= "." and entry ~= ".." then
                        local child_path = path.."/"..entry
                        local child_display = display_path.."/"..entry
                        traverse(child_path, child_display, depth + 1)
                    end
                end
            end
        end
    end

    for _, p in ipairs(paths) do
        local abs = resolve(p)
        traverse(abs, p, 0)
    end

    return exit_code
end
