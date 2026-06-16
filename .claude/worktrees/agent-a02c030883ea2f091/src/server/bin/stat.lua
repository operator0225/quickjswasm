return function(proc, sys, argv)
    local files = {}

    local i = 1
    while i <= #argv do
        local arg = argv[i]
        if arg == "--" then
            i = i + 1
            while i <= #argv do
                table.insert(files, argv[i])
                i = i + 1
            end
            break
        elseif string.sub(arg, 1, 1) == "-" and #arg > 1 then
            -- No meaningful flags for our impl
        else
            table.insert(files, arg)
        end
        i = i + 1
    end

    if #files == 0 then
        sys.write(STDERR, "stat: missing operand\nUsage: stat file...\n")
        return 2
    end

    local function resolvePath(path)
        if string.sub(path, 1, 1) == "/" then
            return path
        else
            return proc.cwd .. "/" .. path
        end
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

    local function fileType(mode)
        local fmt = math.floor(mode / 4096) % 16
        if fmt == 4 then return "directory"
        elseif fmt == 10 then return "symbolic link"
        elseif fmt == 8 then return "regular file"
        else return "special file"
        end
    end

    local function modeOctal(mode)
        local m = mode % 512
        local o1 = math.floor(m / 64) % 8
        local o2 = math.floor(m / 8) % 8
        local o3 = m % 8
        return string.format("%d%d%d", o1, o2, o3)
    end

    local function formatTime(mtime)
        if mtime == nil then return "1970-01-01 00:00:00 +0000" end
        local months = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
        local t = mtime
        local sec = t % 60
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
        return string.format("%04d-%02d-%02d %02d:%02d:%02d +0000", year, month, day, hour, min, sec)
    end

    local exitCode = 0
    for _, fname in ipairs(files) do
        local fullPath = resolvePath(fname)
        local inode, err = sys.stat(fullPath)
        if inode == nil then
            sys.write(STDERR, "stat: cannot stat '" .. fname .. "': " .. tostring(err) .. "\n")
            exitCode = 1
        else
            local tc = typeChar(inode.mode)
            local ms = modeStr(inode.mode)
            local oct = modeOctal(inode.mode)
            local ft = fileType(inode.mode)
            local size = inode.size or 0
            local blocks = math.floor((size + 511) / 512)
            local ino = inode.ino or 0
            local nlinks = inode.nlinks or 1
            local uid = inode.uid or 0
            local gid = inode.gid or 0
            local mt = formatTime(inode.mtime)

            sys.write(STDOUT, "  File: " .. fname .. "\n")
            sys.write(STDOUT, string.format("  Size: %-12d Blocks: %-10d IO Block: 4096   %s\n", size, blocks, ft))
            sys.write(STDOUT, string.format("Device: 0            Inode: %-10d Links: %d\n", ino, nlinks))
            sys.write(STDOUT, string.format("Access: (0%s/%s%s)  Uid: ( %d)  Gid: ( %d)\n", oct, tc, ms, uid, gid))
            sys.write(STDOUT, "Modify: " .. mt .. "\n")
        end
    end

    return exitCode
end
