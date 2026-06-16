local Expander = {}

local function globMatch(pattern, str)
	-- glob을 Lua 패턴으로 변환
	local p = pattern:gsub("[%(%)%.%%%+%-%^%$]", "%%%1")
		:gsub("%*", ".*")
		:gsub("%?", ".")
	return str:match("^" .. p .. "$") ~= nil
end

local function evalArith(expr, env)
	-- 변수 치환
	expr = expr:gsub("%$([%w_]+)", function(v) return tostring(tonumber(env[v] or "0") or 0) end)
	expr = expr:gsub("%$%{([%w_]+)%}", function(v) return tostring(tonumber(env[v] or "0") or 0) end)
	-- 단순 산술 (보안상 loadstring 대신 수동 파싱)
	local function calc(s)
		s = s:match("^%s*(.-)%s*$")
		-- 비교 연산
		local a, op, b = s:match("^(.-)%s*([=!<>]+)%s*(.+)$")
		if a and op and b then
			local na, nb = tonumber(calc(a)), tonumber(calc(b))
			if na and nb then
				if op == "==" or op == "=" then return na == nb and 1 or 0
				elseif op == "!=" then return na ~= nb and 1 or 0
				elseif op == "<"  then return na <  nb and 1 or 0
				elseif op == "<=" then return na <= nb and 1 or 0
				elseif op == ">"  then return na >  nb and 1 or 0
				elseif op == ">=" then return na >= nb and 1 or 0
				end
			end
		end
		return tonumber(s) or 0
	end
	return tostring(calc(expr))
end

local function expandVar(name, env, default)
	local val = env[name]
	if val == nil and default ~= nil then val = default end
	return tostring(val or "")
end

-- 단일 단어 내 변수/산술/커맨드 치환
local function expandWord(word, proc, sys, allowGlob)
	if word:sub(1,1) == "'" and word:sub(-1) == "'" then
		-- single quoted: 그대로 (따옴표 제거)
		return { word:sub(2,-2) }
	end

	local inDQ = false
	if word:sub(1,1) == "\"" then
		inDQ = true
		word = word:sub(2,-2)
	end

	local result = ""
	local i = 1
	while i <= #word do
		local ch = word:sub(i,i)

		if ch == "$" then
			i += 1
			local nx = word:sub(i,i)

			if nx == "(" then
				i += 1
				if word:sub(i,i) == "(" then
					-- 산술 $((expr))
					i += 1
					local depth = 2
					local expr = ""
					while i <= #word do
						if word:sub(i,i) == ")" and word:sub(i+1,i+1) == ")" then
							i += 2; depth = 0; break
						end
						expr ..= word:sub(i,i); i += 1
					end
					result ..= evalArith(expr, proc.env)
				else
					-- 커맨드 치환 $(cmd)
					local depth = 1
					local cmd = ""
					while i <= #word do
						local c = word:sub(i,i)
						if c == "(" then depth += 1
						elseif c == ")" then depth -= 1; if depth == 0 then i += 1; break end
						end
						cmd ..= c; i += 1
					end
					-- 서브셸 실행 후 출력 캡처
					local Pipe = require(script.Parent.Parent.kernel.Pipe)
					local pipe = Pipe.new()
					local capturedOutput = ""
					-- 간단한 구현: Shell.runCapture 사용
					local Shell = require(script.Parent.Shell)
					capturedOutput = Shell.capture(cmd, proc, sys) or ""
					capturedOutput = capturedOutput:gsub("\n+$", "")  -- trailing newline 제거
					result ..= capturedOutput
				end

			elseif nx == "{" then
				i += 1
				local var = ""
				local modifier = nil
				local modVal = nil
				while i <= #word and word:sub(i,i) ~= "}" do
					local c = word:sub(i,i)
					if c == ":" or c == "#" or c == "%" then
						modifier = c
						i += 1
						modVal = ""
						while i <= #word and word:sub(i,i) ~= "}" do
							modVal ..= word:sub(i,i); i += 1
						end
						break
					end
					var ..= c; i += 1
				end
				i += 1  -- }
				if modifier == ":" then
					local op = modVal and modVal:sub(1,1) or ""
					local def = modVal and modVal:sub(2) or ""
					if op == "-" then result ..= (proc.env[var] ~= "" and proc.env[var]) or def
					elseif op == "+" then result ..= proc.env[var] and def or ""
					else result ..= expandVar(var, proc.env) end
				elseif modifier == "#" then
					result ..= tostring(#(proc.env[var] or ""))
				elseif modifier == "%" then
					local v = proc.env[var] or ""
					result ..= v:gsub(modVal:gsub("%*",".*") .. "$", "")
				else
					result ..= expandVar(var, proc.env)
				end

			elseif nx == "?" then
				i += 1
				result ..= tostring(proc.env["?"] or "0")
			elseif nx == "$" then
				i += 1
				result ..= tostring(proc.pid)
			elseif nx == "*" then
				i += 1
				result ..= table.concat(proc.argv or {}, " ")
			elseif nx == "@" then
				i += 1
				result ..= table.concat(proc.argv or {}, " ")
			elseif nx == "#" then
				i += 1
				result ..= tostring(#(proc.argv or {}) - 1)
			elseif nx:match("[%w_]") then
				local var = ""
				while i <= #word and word:sub(i,i):match("[%w_]") do
					var ..= word:sub(i,i); i += 1
				end
				result ..= expandVar(var, proc.env)
			else
				result ..= "$"
			end

		elseif ch == "~" and i == 1 then
			result ..= proc.env["HOME"] or "/home/user"
			i += 1
		else
			result ..= ch; i += 1
		end
	end

	-- glob 처리 (double-quote 내부에서는 X)
	if allowGlob and not inDQ and (result:find("%*") or result:find("%?") or result:find("%[")) then
		local dir, pat
		local slash = result:match("^(.*/)[^/]*$")
		if slash then
			dir = slash
			pat = result:sub(#slash + 1)
		else
			dir = proc.cwd .. "/"
			pat = result
		end
		local entries, _ = sys.readdir(dir ~= "/" and dir:sub(1,-2) or dir)
		if entries and #entries > 0 then
			local matched = {}
			for _, e in ipairs(entries) do
				if globMatch(pat, e) then
					table.insert(matched, (slash or "") .. e)
				end
			end
			if #matched > 0 then return matched end
		end
	end

	return { result }
end

function Expander.expand(words, proc, sys)
	local result = {}
	for _, word in ipairs(words) do
		local expanded = expandWord(word, proc, sys, true)
		for _, v in ipairs(expanded) do
			table.insert(result, v)
		end
	end
	return result
end

-- 단일 단어 확장 (글로브 없음)
function Expander.expandOne(word, proc, sys)
	return expandWord(word, proc, sys, false)[1] or ""
end

return Expander
