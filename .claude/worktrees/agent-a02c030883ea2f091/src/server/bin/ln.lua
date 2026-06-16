return function(proc, sys, argv)
    local symbolic = false
    local force = false
    local files = {}
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "-s" then
            symbolic = true
        elseif a == "-f" then
            force = true
        elseif a == "-sf" or a == "-fs" then
            symbolic = true
            force = true
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
                if ch == "s" then symbolic = true
                elseif ch == "f" then force = true
                else ok = false end
            end
            if not ok then
                sys.write(STDERR, "ln: invalid option -- '"..string.sub(a,2).."'\n")
                return 2
            end
        else
            table.insert(files, a)
        end
        i = i + 1
    end

    if #files < 2 then
        sys.write(STDERR, "ln: missing file operand\nUsage: ln [-sf] TARGET LINK_NAME\n")
        return 2
    end

    local target = files[1]
    local link_name = files[2]

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

    local link_path = resolve(link_name)

    -- If force, unlink target if it exists
    if force then
        local stat = sys.stat(link_path)
        if stat then
            local ok, err = sys.unlink(link_path)
            if not ok then
                sys.write(STDERR, "ln: cannot remove '"..link_name.."': "..tostring(err).."\n")
                return 1
            end
        end
    end

    if symbolic then
        -- sys.symlink(target, path)
        local ok, err = sys.symlink(target, link_path)
        if not ok then
            sys.write(STDERR, "ln: failed to create symbolic link '"..link_name.."': "..tostring(err).."\n")
            return 1
        end
    else
        -- Hard link: copy file content
        local src_path = resolve(target)
        local src_fd, err = sys.open(src_path, {rdonly=true})
        if not src_fd then
            sys.write(STDERR, "ln: '"..target.."': No such file or directory\n")
            return 1
        end
        local content = read_all(src_fd)
        sys.close(src_fd)

        local dst_fd, derr = sys.open(link_path, {create=true})
        if not dst_fd then
            sys.write(STDERR, "ln: cannot create '"..link_name.."': "..tostring(derr).."\n")
            return 1
        end
        local written, werr = sys.write(dst_fd, content)
        sys.close(dst_fd)
        if not written then
            sys.write(STDERR, "ln: write error: "..tostring(werr).."\n")
            return 1
        end
    end

    return 0
end
