local Lexer = {}

local TK = {
	WORD="WORD", PIPE="PIPE", REDIR_OUT="REDIR_OUT", REDIR_APPEND="REDIR_APPEND",
	REDIR_IN="REDIR_IN", REDIR_ERR="REDIR_ERR", REDIR_ERR_APPEND="REDIR_ERR_APPEND",
	REDIR_HEREDOC="REDIR_HEREDOC", REDIR_BOTH="REDIR_BOTH",
	AMP="AMP", SEMI="SEMI", AND_IF="AND_IF", OR_IF="OR_IF",
	LPAREN="LPAREN", RPAREN="RPAREN", LBRACE="LBRACE", RBRACE="RBRACE",
	NEWLINE="NEWLINE", EOF="EOF",
	IF="IF", THEN="THEN", ELSE="ELSE", ELIF="ELIF", FI="FI",
	WHILE="WHILE", DO="DO", DONE="DONE", FOR="FOR", IN="IN",
	CASE="CASE", ESAC="ESAC", UNTIL="UNTIL", FUNCTION="FUNCTION",
	CMD_SUBST="CMD_SUBST", ARITH="ARITH",
}
Lexer.TK = TK

local KEYWORDS = {
	["if"]=TK.IF, ["then"]=TK.THEN, ["else"]=TK.ELSE, ["elif"]=TK.ELIF, ["fi"]=TK.FI,
	["while"]=TK.WHILE, ["do"]=TK.DO, ["done"]=TK.DONE,
	["for"]=TK.FOR, ["in"]=TK.IN,
	["case"]=TK.CASE, ["esac"]=TK.ESAC,
	["until"]=TK.UNTIL, ["function"]=TK.FUNCTION,
}

local function tok(type, value)
	return { type = type, value = value }
end

function Lexer.tokenize(input)
	local tokens = {}
	local i = 1
	local n = #input

	local function peek(offset)
		local j = i + (offset or 0)
		return j <= n and input:sub(j, j) or ""
	end

	local function consume()
		local ch = peek()
		i += 1
		return ch
	end

	local function readSingleQuote()
		-- consume opening '
		i += 1
		local s = ""
		while i <= n do
			local ch = consume()
			if ch == "'" then return s end
			s ..= ch
		end
		return s
	end

	local function readDoubleQuote()
		i += 1
		local s = "\""
		while i <= n do
			local ch = peek()
			if ch == "\"" then i += 1; s ..= "\""; return s end
			if ch == "\\" then
				i += 1
				local esc = consume()
				if esc == "$" or esc == "`" or esc == "\"" or esc == "\\" or esc == "\n" then
					s ..= esc
				else
					s ..= "\\" .. esc
				end
			else
				s ..= consume()
			end
		end
		return s
	end

	local function readCmdSubst()
		-- after $(
		local depth = 1
		local s = ""
		while i <= n do
			local ch = peek()
			if ch == "(" then depth += 1; s ..= consume()
			elseif ch == ")" then
				depth -= 1
				if depth == 0 then i += 1; return s end
				s ..= consume()
			else
				s ..= consume()
			end
		end
		return s
	end

	local function readArith()
		-- after $((
		local depth = 1
		local s = ""
		while i <= n do
			if peek() == ")" and peek(1) == ")" then
				i += 2
				return s
			end
			s ..= consume()
		end
		return s
	end

	local function readWord()
		local s = ""
		while i <= n do
			local ch = peek()
			if ch == " " or ch == "\t" or ch == "\n" or ch == "" then break end
			if ch == "|" or ch == "&" or ch == ";" or ch == "(" or ch == ")" or ch == "<" or ch == ">" then break end
			if ch == "#" and s == "" then
				-- comment: skip to end of line
				while i <= n and peek() ~= "\n" do i += 1 end
				break
			end
			if ch == "'" then s ..= readSingleQuote()
			elseif ch == "\"" then s ..= readDoubleQuote()
			elseif ch == "\\" then
				i += 1
				if peek() == "\n" then i += 1  -- line continuation
				else s ..= consume() end
			elseif ch == "$" then
				i += 1
				local nx = peek()
				if nx == "(" then
					i += 1
					if peek() == "(" then
						i += 1
						local expr = readArith()
						s ..= "$((" .. expr .. "))"
					else
						local cmd = readCmdSubst()
						s ..= "$(" .. cmd .. ")"
					end
				elseif nx == "{" then
					i += 1
					local var = ""
					while i <= n and peek() ~= "}" do var ..= consume() end
					i += 1
					s ..= "${" .. var .. "}"
				elseif nx:match("[%w_?@*#!$-]") then
					local var = ""
					while i <= n and peek():match("[%w_?@*#!$]") do var ..= consume() end
					s ..= "$" .. var
				else
					s ..= "$"
				end
			elseif ch == "`" then
				i += 1
				local cmd = ""
				while i <= n and peek() ~= "`" do cmd ..= consume() end
				i += 1
				s ..= "$(" .. cmd .. ")"
			else
				s ..= consume()
			end
		end
		return s
	end

	while i <= n do
		local ch = peek()

		if ch == " " or ch == "\t" then
			i += 1

		elseif ch == "\n" then
			i += 1
			table.insert(tokens, tok(TK.NEWLINE, "\n"))

		elseif ch == "#" then
			while i <= n and peek() ~= "\n" do i += 1 end

		elseif ch == "|" then
			i += 1
			if peek() == "|" then i += 1; table.insert(tokens, tok(TK.OR_IF, "||"))
			else table.insert(tokens, tok(TK.PIPE, "|")) end

		elseif ch == "&" then
			i += 1
			if peek() == "&" then i += 1; table.insert(tokens, tok(TK.AND_IF, "&&"))
			elseif peek() == ">" then i += 1; table.insert(tokens, tok(TK.REDIR_BOTH, "&>"))
			else table.insert(tokens, tok(TK.AMP, "&")) end

		elseif ch == ";" then
			i += 1
			table.insert(tokens, tok(TK.SEMI, ";"))

		elseif ch == "(" then i += 1; table.insert(tokens, tok(TK.LPAREN, "("))
		elseif ch == ")" then i += 1; table.insert(tokens, tok(TK.RPAREN, ")"))
		elseif ch == "{" then i += 1; table.insert(tokens, tok(TK.LBRACE, "{"))
		elseif ch == "}" then i += 1; table.insert(tokens, tok(TK.RBRACE, "}"))

		elseif ch == ">" then
			i += 1
			if peek() == ">" then i += 1; table.insert(tokens, tok(TK.REDIR_APPEND, ">>"))
			else table.insert(tokens, tok(TK.REDIR_OUT, ">")) end

		elseif ch == "<" then
			i += 1
			if peek() == "<" then i += 1; table.insert(tokens, tok(TK.REDIR_HEREDOC, "<<"))
			else table.insert(tokens, tok(TK.REDIR_IN, "<")) end

		elseif ch == "2" and peek(1) == ">" then
			i += 2
			if peek() == ">" then i += 1; table.insert(tokens, tok(TK.REDIR_ERR_APPEND, "2>>"))
			else table.insert(tokens, tok(TK.REDIR_ERR, "2>")) end

		else
			local word = readWord()
			if word ~= "" then
				local kw = KEYWORDS[word]
				if kw then
					table.insert(tokens, tok(kw, word))
				else
					table.insert(tokens, tok(TK.WORD, word))
				end
			end
		end
	end

	table.insert(tokens, tok(TK.EOF, ""))
	return tokens
end

return Lexer
