return function(proc, sys, argv)
    local delete = false
    local squeeze = false
    local complement = false
    local i = 1
    local sets = {}

    while i <= #argv do
        local a = argv[i]
        if a == "-d" then
            delete = true
        elseif a == "-s" then
            squeeze = true
        elseif a == "-c" or a == "-C" then
            complement = true
        elseif a == "--" then
            i = i + 1
            while i <= #argv do
                table.insert(sets, argv[i])
                i = i + 1
            end
            break
        elseif string.sub(a, 1, 1) == "-" and #a > 1 then
            -- combined flags
            local flags = string.sub(a, 2)
            local ok = true
            for ci = 1, #flags do
                local ch = string.sub(flags, ci, ci)
                if ch == "d" then delete = true
                elseif ch == "s" then squeeze = true
                elseif ch == "c" or ch == "C" then complement = true
                else ok = false end
            end
            if not ok then
                sys.write(STDERR, "tr: invalid option -- '"..string.sub(a,2).."'\n")
                return 2
            end
        else
            table.insert(sets, a)
        end
        i = i + 1
    end

    local set1_str = sets[1]
    local set2_str = sets[2]

    if not set1_str then
        sys.write(STDERR, "tr: missing operand\nUsage: tr [OPTIONS] SET1 [SET2]\n")
        return 2
    end

    -- Expand escape sequences in a set string
    local function expand_escapes(s)
        local result = {}
        local pos = 1
        while pos <= #s do
            local ch = string.sub(s, pos, pos)
            if ch == "\\" and pos < #s then
                local next = string.sub(s, pos+1, pos+1)
                if next == "n" then table.insert(result, "\n"); pos = pos + 2
                elseif next == "t" then table.insert(result, "\t"); pos = pos + 2
                elseif next == "\\" then table.insert(result, "\\"); pos = pos + 2
                elseif next == "a" then table.insert(result, "\7"); pos = pos + 2
                elseif next == "b" then table.insert(result, "\8"); pos = pos + 2
                elseif next == "r" then table.insert(result, "\13"); pos = pos + 2
                elseif next == "0" then table.insert(result, "\0"); pos = pos + 2
                else
                    table.insert(result, ch)
                    pos = pos + 1
                end
            else
                table.insert(result, ch)
                pos = pos + 1
            end
        end
        return result
    end

    -- Expand ranges in a char array (e.g. a-z)
    local function expand_ranges(chars)
        local result = {}
        local ci = 1
        while ci <= #chars do
            if ci + 2 <= #chars and chars[ci+1] == "-" then
                local from_b = string.byte(chars[ci])
                local to_b = string.byte(chars[ci+2])
                if from_b <= to_b then
                    for b = from_b, to_b do
                        table.insert(result, string.char(b))
                    end
                else
                    -- invalid range: just add chars literally
                    table.insert(result, chars[ci])
                    table.insert(result, chars[ci+1])
                    table.insert(result, chars[ci+2])
                end
                ci = ci + 3
            else
                table.insert(result, chars[ci])
                ci = ci + 1
            end
        end
        return result
    end

    local function build_set(s)
        if not s then return {} end
        local escaped = expand_escapes(s)
        local expanded = expand_ranges(escaped)
        return expanded
    end

    local set1 = build_set(set1_str)
    local set2 = build_set(set2_str)

    -- Build lookup: char -> index in set1 (1-based)
    -- If complement, we invert set1
    local set1_lookup = {}
    for idx, ch in ipairs(set1) do
        set1_lookup[ch] = idx
    end

    local function in_set1(ch)
        return set1_lookup[ch] ~= nil
    end

    -- Complement: all bytes not in set1
    local set1_comp = nil
    if complement then
        set1_comp = {}
        local comp_lookup = {}
        for b = 0, 255 do
            local ch = string.char(b)
            if not set1_lookup[ch] then
                table.insert(set1_comp, ch)
                comp_lookup[ch] = #set1_comp
            end
        end
        set1_lookup = comp_lookup
        in_set1 = function(ch)
            return comp_lookup[ch] ~= nil
        end
        set1 = set1_comp
    end

    -- Build translation table (for non-delete mode)
    -- set1[i] -> set2[i] (if set2 shorter, use last char of set2)
    local trans = {}
    if not delete and #set2 > 0 then
        local last2 = set2[#set2]
        for idx, ch in ipairs(set1) do
            local to = set2[idx] or last2
            trans[ch] = to
        end
    end

    -- Set2 for squeeze (when -s without -d, squeeze uses set2; with -d -s, squeeze uses set2)
    local squeeze_set_lookup = {}
    if squeeze then
        local sq_set
        if delete and set2_str then
            sq_set = set2
        elseif not delete then
            sq_set = set2
        else
            sq_set = set1
        end
        for _, ch in ipairs(sq_set) do
            squeeze_set_lookup[ch] = true
        end
    end

    -- Read all stdin
    local function read_all(fd)
        local chunks = {}
        while true do
            local data = sys.read(fd, 4096)
            if not data or #data == 0 then break end
            table.insert(chunks, data)
        end
        return table.concat(chunks)
    end

    local input = read_all(STDIN)

    local output = {}
    local prev_ch = nil

    for bi = 1, #input do
        local ch = string.sub(input, bi, bi)
        local out_ch = ch

        if delete then
            if in_set1(ch) then
                out_ch = nil
            end
        else
            if in_set1(ch) then
                out_ch = trans[ch] or ch
            end
        end

        if out_ch ~= nil then
            if squeeze then
                local sq_ch = out_ch
                if squeeze_set_lookup[sq_ch] then
                    if sq_ch == prev_ch then
                        out_ch = nil
                    end
                end
            end
        end

        if out_ch ~= nil then
            table.insert(output, out_ch)
            prev_ch = out_ch
        end
    end

    sys.write(STDOUT, table.concat(output))

    return 0
end
