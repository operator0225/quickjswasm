return function(proc, sys, argv)
    local showHidden = false
    local longFormat = false
    local humanSizes = false
    local reverseSort = false
    local sortByTime = false
    local recursive = false
    local targets = {}

    local i = 1
    while i <= #argv do
        local arg = argv[i]
        if arg == "--" then
            i = i + 1
            while i <= #argv do
                table.insert(targets, argv[i])
                i = i + 1
            end
            break
        elseif string.sub(arg, 1, 1) == "-" and #arg > 1 then
            for j = 2, #arg do
                local c = string.sub(arg, j, j)
                if c == "a" then showHidden = true
                elseif c == "l" then longFormat = true
                elseif c == "h" then humanSizes = true
                elseif c == "r" then reverseSort = true
                elseif c == "t" then sortByTime = true
                elseif c == "R" then recursive = true
                end
            end
        else
            table.insert(targets, arg)
        end
        i = i + 1
    end

    if #targets == 0 then
        table.insert(targets, proc.cwd)
    end

    local function resolvePath(path)
        if string.sub(path, 1, 1) == "/" then
            return path
        else
            return proc.cwd .. "/" .. path
        end
    end

    local function humanSize(n)
        if n < 1024 then return tostring(n) end
        local units = {"K", "M", "G", "T"}
        local val = n
        for _, u in ipairs(units) do
            val = val / 1024
            if val < 1024 then
                return string.format("%.1f%s", val, u)
            end
        end
        return string.format("%.1fT", val)
    end

    local function modeStr(mode)
        local s = ""
        local perms = {"r","w","x","r","w","x","r","w","x"}
        local bits = {}
        local m = mode % 512
        for bi = 8, 0, -1 do
            local bit = math.floor(m / (2 ^ bi)) % 2
            table.insert(bits, bit)
        end
        for idx, p in ipairs(perms) do
            if bits[idx] == 1 then
                s = s .. p
            else
                s = s .. "-"
            end
        end
        return s
    end

    local function typeChar(mode)
        local fmt = math.floor(mode / 4096) % 16
        if fmt == 4 then return "d"
        elseif fmt == 10 then return "l"
        elseif fmt == 8 then return "-"
        else return "?"
        end
    end

    local function isDir(mode)
        return math.floor(mode / 4096) % 16 == 4
    end

    local function isExec(mode)
        return mode % 8 >= 1
    end

    local function isLink(mode)
        return math.floor(mode / 4096) % 16 == 10
    end

    local function colorName(name, inode)
        if inode == nil then return name end
        if isDir(inode.mode) then
            return "\27[36m" .. name .. "\27[0m"
        elseif isLink(inode.mode) then
            return "\27[35m" .. name .. "\27[0m"
        elseif isExec(inode.mode) then
            return "\27[32m" .. name .. "\27[0m"
        end
        return name
    end

    local function formatMtime(mtime)
        if mtime == nil then return "Jan 01 00:00" end
        local months = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
        local t = mtime
        local min = math.floor(t / 60) % 60
        local hour = math.floor(t / 3600) % 24
        local days = math.floor(t / 86400)
        local year = 1970
        while true do
            local diy = 365
            if (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0) then diy = 366 end
            if days < diy then break end
            days = days - diy
            year = year + 1
        end
        local leapYear = (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
        local mdays = {31,28,31,30,31,30,31,31,30,31,30,31}
        if leapYear then mdays[2] = 29 end
        local month = 1
        for mi, md in ipairs(mdays) do
            if days < md then month = mi; break end
            days = days - md
        end
        local day = days + 1
        return string.format("%s %02d %02d:%02d", months[month], day, hour, min)
    end

    local function writeOut(s)
        sys.write(STDOUT, s)
    end

    local function writeErr(s)
        sys.write(STDERR, s)
    end

    local function listDir(dirPath, printHeader)
        local names, err = sys.readdir(dirPath)
        if names == nil then
            writeErr("ls: cannot access '" .. dirPath .. "': " .. tostring(err) .. "\n")
            return 1
        end

        local filtered = {}
        for _, name in ipairs(names) do
            if showHidden or string.sub(name, 1, 1) ~= "." then
                table.insert(filtered, name)
            end
        end

        local entries = {}
        for _, name in ipairs(filtered) do
            local fullPath = dirPath .. "/" .. name
            local inode = sys.stat(fullPath)
            table.insert(entries, {name=name, inode=inode, path=fullPath})
        end

        if sortByTime then
            table.sort(entries, function(a, b)
                local at = (a.inode and a.inode.mtime) or 0
                local bt = (b.inode and b.inode.mtime) or 0
                if reverseSort then return at < bt else return at > bt end
            end)
        else
            table.sort(entries, function(a, b)
                if reverseSort then return a.name > b.name else return a.name < b.name end
            end)
        end

        if printHeader then
            writeOut(dirPath .. ":\n")
        end

        if longFormat then
            for _, e in ipairs(entries) do
                local inode = e.inode
                if inode then
                    local tc = typeChar(inode.mode)
                    local ms = modeStr(inode.mode)
                    local sizeStr = humanSizes and humanSize(inode.size or 0) or tostring(inode.size or 0)
                    local mt = formatMtime(inode.mtime)
                    local nl = inode.nlinks or 1
                    local displayName = colorName(e.name, inode)
                    writeOut(string.format("%s%s %3d %-8s %-8s %8s %s %s\n",
                        tc, ms, nl,
                        tostring(inode.uid or 0), tostring(inode.gid or 0),
                        sizeStr, mt, displayName))
                else
                    writeOut(e.name .. "\n")
                end
            end
        else
            local line = ""
            for idx, e in ipairs(entries) do
                local displayName = colorName(e.name, e.inode)
                if idx > 1 then line = line .. "  " end
                line = line .. displayName
            end
            if #entries > 0 then writeOut(line .. "\n") end
        end

        if recursive then
            for _, e in ipairs(entries) do
                if e.inode and isDir(e.inode.mode) and e.name ~= "." and e.name ~= ".." then
                    writeOut("\n")
                    listDir(e.path, true)
                end
            end
        end

        return 0
    end

    local exitCode = 0
    local multipleTargets = #targets > 1

    for _, target in ipairs(targets) do
        local fullPath = resolvePath(target)
        local inode, err = sys.stat(fullPath)
        if inode == nil then
            writeErr("ls: cannot access '" .. target .. "': " .. tostring(err) .. "\n")
            exitCode = 1
        elseif isDir(inode.mode) then
            local ret = listDir(fullPath, multipleTargets or recursive)
            if ret ~= 0 then exitCode = ret end
        else
            if longFormat then
                local tc = typeChar(inode.mode)
                local ms = modeStr(inode.mode)
                local sizeStr = humanSizes and humanSize(inode.size or 0) or tostring(inode.size or 0)
                local mt = formatMtime(inode.mtime)
                local nl = inode.nlinks or 1
                local displayName = colorName(target, inode)
                writeOut(string.format("%s%s %3d %-8s %-8s %8s %s %s\n",
                    tc, ms, nl,
                    tostring(inode.uid or 0), tostring(inode.gid or 0),
                    sizeStr, mt, displayName))
            else
                writeOut(colorName(target, inode) .. "\n")
            end
        end
    end

    return exitCode
end
