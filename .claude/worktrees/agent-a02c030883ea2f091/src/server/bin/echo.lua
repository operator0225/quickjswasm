return function(proc, sys, argv)
    local no_newline = false
    local interpret = false
    local args = {}
    local i = 1
    -- Process flags only at the start
    local done_flags = false
    while i <= #argv do
        local a = argv[i]
        if not done_flags and a == "-n" then
            no_newline = true
        elseif not done_flags and a == "-e" then
            interpret = true
        elseif not done_flags and string.sub(a, 1, 1) == "-" and #a > 1 then
            -- Check if it's a valid combination of n and e flags
            local flags = string.sub(a, 2)
            local valid = true
            local has_n = false
            local has_e = false
            for ci = 1, #flags do
                local ch = string.sub(flags, ci, ci)
                if ch == "n" then has_n = true
                elseif ch == "e" then has_e = true
                else valid = false; break end
            end
            if valid then
                if has_n then no_newline = true end
                if has_e then interpret = true end
            else
                done_flags = true
                table.insert(args, a)
            end
        else
            done_flags = true
            table.insert(args, a)
        end
        i = i + 1
    end

    local function interpret_escapes(s)
        local result = {}
        local pos = 1
        local len = #s
        while pos <= len do
            local ch = string.sub(s, pos, pos)
            if ch == "\\" and pos < len then
                local next = string.sub(s, pos + 1, pos + 1)
                if next == "n" then
                    table.insert(result, "\n")
                    pos = pos + 2
                elseif next == "t" then
                    table.insert(result, "\t")
                    pos = pos + 2
                elseif next == "\\" then
                    table.insert(result, "\\")
                    pos = pos + 2
                elseif next == "a" then
                    table.insert(result, "\7")
                    pos = pos + 2
                elseif next == "b" then
                    table.insert(result, "\8")
                    pos = pos + 2
                elseif next == "r" then
                    table.insert(result, "\13")
                    pos = pos + 2
                elseif next == "0" then
                    table.insert(result, "\0")
                    pos = pos + 2
                else
                    table.insert(result, ch)
                    pos = pos + 1
                end
            else
                table.insert(result, ch)
                pos = pos + 1
            end
        end
        return table.concat(result)
    end

    local parts = {}
    for _, a in ipairs(args) do
        if interpret then
            table.insert(parts, interpret_escapes(a))
        else
            table.insert(parts, a)
        end
    end

    local out = table.concat(parts, " ")
    if not no_newline then
        out = out.."\n"
    end
    sys.write(STDOUT, out)

    return 0
end
