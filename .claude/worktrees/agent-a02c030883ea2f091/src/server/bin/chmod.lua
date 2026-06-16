return function(proc, sys, argv)
    if #argv < 2 then
        sys.write(STDERR, "chmod: missing operand\nUsage: chmod MODE FILE...\n")
        return 2
    end

    local mode_str = argv[1]
    local files = {}
    for i = 2, #argv do
        table.insert(files, argv[i])
    end

    local function resolve(path)
        if string.sub(path, 1, 1) == "/" then return path end
        return proc.cwd.."/"..path
    end

    -- Parse mode string: either octal number or symbolic
    local function parse_octal(s)
        local n = 0
        for ci = 1, #s do
            local d = string.byte(s, ci) - string.byte("0")
            if d < 0 or d > 7 then return nil end
            n = n * 8 + d
        end
        return n
    end

    -- Get current mode from file
    local function get_mode(path)
        local stat, err = sys.stat(path)
        if not stat then return nil, err end
        return stat.mode, nil
    end

    -- Bit helpers for symbolic mode manipulation
    local function bits_or(a, b)
        local result = 0
        local bit = 1
        while bit <= a or bit <= b do
            if math.floor(a / bit) % 2 == 1 or math.floor(b / bit) % 2 == 1 then
                result = result + bit
            end
            bit = bit * 2
        end
        return result
    end

    local function bits_and(a, b)
        local result = 0
        local bit = 1
        while bit <= a and bit <= b do
            if math.floor(a / bit) % 2 == 1 and math.floor(b / bit) % 2 == 1 then
                result = result + bit
            end
            bit = bit * 2
        end
        return result
    end

    local function bits_not(a, maxbits)
        local result = 0
        local bit = 1
        for _ = 1, maxbits do
            if math.floor(a / bit) % 2 == 0 then
                result = result + bit
            end
            bit = bit * 2
        end
        return result
    end

    local function apply_sym_clause(perm, clause)
        local pos = 1
        local who = ""
        while pos <= #clause do
            local ch = string.sub(clause, pos, pos)
            if ch == "u" or ch == "g" or ch == "o" or ch == "a" then
                who = who..ch
                pos = pos + 1
            else
                break
            end
        end
        if who == "" then who = "a" end

        local op = string.sub(clause, pos, pos)
        pos = pos + 1
        if op ~= "+" and op ~= "-" and op ~= "=" then
            return nil, "invalid operator"
        end

        local perm_chars = string.sub(clause, pos)
        local triplet = 0
        for ci = 1, #perm_chars do
            local ch = string.sub(perm_chars, ci, ci)
            if ch == "r" then triplet = bits_or(triplet, 4)
            elseif ch == "w" then triplet = bits_or(triplet, 2)
            elseif ch == "x" or ch == "X" then triplet = bits_or(triplet, 1)
            end
        end

        local apply_u = string.find(who, "u") or string.find(who, "a")
        local apply_g = string.find(who, "g") or string.find(who, "a")
        local apply_o = string.find(who, "o") or string.find(who, "a")

        local function apply_to(p, shift, t, operation)
            local cur = math.floor(p / (2^shift)) % 8
            local new_cur
            if operation == "+" then
                new_cur = bits_or(cur, t)
            elseif operation == "-" then
                new_cur = bits_and(cur, bits_not(t, 3))
            elseif operation == "=" then
                new_cur = t
            else
                new_cur = cur
            end
            local base = p - cur * math.floor(2^shift)
            return base + new_cur * math.floor(2^shift)
        end

        if apply_u then perm = apply_to(perm, 6, triplet, op) end
        if apply_g then perm = apply_to(perm, 3, triplet, op) end
        if apply_o then perm = apply_to(perm, 0, triplet, op) end

        return perm, nil
    end

    local function compute_new_mode(current_mode, mode_string)
        local perm = current_mode % 4096
        local high = current_mode - perm

        -- Try octal first
        local octal_val = parse_octal(mode_string)
        if octal_val then
            return high + octal_val
        end

        -- Symbolic
        local p = 1
        while p <= #mode_string do
            local comma = string.find(mode_string, ",", p, true)
            local clause
            if comma then
                clause = string.sub(mode_string, p, comma - 1)
                p = comma + 1
            else
                clause = string.sub(mode_string, p)
                p = #mode_string + 1
            end
            if #clause > 0 then
                local new_perm, err = apply_sym_clause(perm, clause)
                if not new_perm then
                    return nil, err
                end
                perm = new_perm
            end
        end

        return high + perm
    end

    local function format_octal(n)
        if n == 0 then return "0" end
        local s = ""
        while n > 0 do
            s = tostring(n % 8)..s
            n = math.floor(n / 8)
        end
        return s
    end

    local exit_code = 0

    for _, f in ipairs(files) do
        local path = resolve(f)
        local current_mode, err = get_mode(path)
        if not current_mode then
            sys.write(STDERR, "chmod: cannot access '"..f.."': No such file or directory\n")
            exit_code = 1
        else
            local new_mode, merr = compute_new_mode(current_mode, mode_str)
            if not new_mode then
                sys.write(STDERR, "chmod: invalid mode: '"..mode_str.."'\n")
                exit_code = 1
            else
                sys.write(STDOUT, "chmod: "..f..": mode changed to "..format_octal(new_mode % 4096).."\n")
            end
        end
    end

    return exit_code
end
