local AST   = require(script.Parent.AST)
local Lexer = require(script.Parent.Lexer)
local TK    = Lexer.TK

local Parser = {}

local function newParser(tokens)
	local p = { tokens = tokens, pos = 1 }

	function p:peek()
		return self.tokens[self.pos] or { type = TK.EOF, value = "" }
	end

	function p:peekType()
		return self:peek().type
	end

	function p:consume()
		local t = self:peek()
		self.pos += 1
		return t
	end

	function p:expect(type)
		local t = self:peek()
		if t.type ~= type then
			return nil, "expected " .. type .. " got " .. t.type .. " '" .. tostring(t.value) .. "'"
		end
		self.pos += 1
		return t
	end

	function p:skipNewlines()
		while self:peekType() == TK.NEWLINE do self.pos += 1 end
	end

	function p:isWordLike()
		local tp = self:peekType()
		return tp == TK.WORD or tp == TK.CMD_SUBST or tp == TK.ARITH
	end

	-- redirect: [fd] op target
	function p:parseRedirect()
		local tp = self:peekType()
		local redirTypes = {
			[TK.REDIR_OUT]=">", [TK.REDIR_APPEND]=">>", [TK.REDIR_IN]="<",
			[TK.REDIR_ERR]="2>", [TK.REDIR_ERR_APPEND]="2>>",
			[TK.REDIR_HEREDOC]="<<", [TK.REDIR_BOTH]="&>",
		}
		if not redirTypes[tp] then return nil end
		local op = self:consume().type
		local target = self:peek()
		if not self:isWordLike() then return AST.error("expected redirect target") end
		self:consume()
		return AST.redirect(nil, redirTypes[op] or op, target.value)
	end

	function p:parseSimpleCmd()
		local words = {}
		local redirs = {}

		while true do
			local tp = self:peekType()
			if tp == TK.WORD then
				table.insert(words, self:consume().value)
			elseif tp == TK.REDIR_OUT or tp == TK.REDIR_APPEND or tp == TK.REDIR_IN
			    or tp == TK.REDIR_ERR or tp == TK.REDIR_ERR_APPEND
			    or tp == TK.REDIR_HEREDOC or tp == TK.REDIR_BOTH then
				local r = self:parseRedirect()
				if r then table.insert(redirs, r) end
			else
				break
			end
		end

		if #words == 0 and #redirs == 0 then return nil end
		return AST.simpleCmd(words, redirs)
	end

	function p:parsePipeline()
		local negate = false
		if self:peekType() == TK.WORD and self:peek().value == "!" then
			self:consume(); negate = true
		end

		local cmds = {}
		local first = self:parseCompoundOrSimple()
		if not first then return nil end
		table.insert(cmds, first)

		while self:peekType() == TK.PIPE do
			self:consume()
			self:skipNewlines()
			local cmd = self:parseCompoundOrSimple()
			if not cmd then return AST.error("expected command after |") end
			table.insert(cmds, cmd)
		end

		if #cmds == 1 and not negate then return cmds[1] end
		return AST.pipeline(cmds, negate)
	end

	function p:parseList()
		local left = self:parsePipeline()
		if not left then return nil end

		while true do
			local tp = self:peekType()
			if tp == TK.SEMI or tp == TK.NEWLINE then
				self:consume()
				self:skipNewlines()
				if self:peekType() == TK.EOF then return left end
				local right = self:parsePipeline()
				if right then left = AST.list(left, ";", right) end
			elseif tp == TK.AND_IF then
				self:consume(); self:skipNewlines()
				local right = self:parsePipeline()
				if not right then return AST.error("expected command after &&") end
				left = AST.list(left, "&&", right)
			elseif tp == TK.OR_IF then
				self:consume(); self:skipNewlines()
				local right = self:parsePipeline()
				if not right then return AST.error("expected command after ||") end
				left = AST.list(left, "||", right)
			elseif tp == TK.AMP then
				self:consume()
				left = AST.background(left)
				self:skipNewlines()
				if self:peekType() == TK.EOF then return left end
				local right = self:parseList()
				if right then left = AST.list(left, ";", right) end
				return left
			else
				break
			end
		end
		return left
	end

	function p:parseCompoundOrSimple()
		local tp = self:peekType()

		if tp == TK.IF then return self:parseIf()
		elseif tp == TK.WHILE then return self:parseWhile()
		elseif tp == TK.UNTIL then return self:parseUntil()
		elseif tp == TK.FOR then return self:parseFor()
		elseif tp == TK.CASE then return self:parseCase()
		elseif tp == TK.FUNCTION then return self:parseFuncDef()
		elseif tp == TK.WORD and self:peek().value ~= "" then
			-- function shorthand: name()
			local saved = self.pos
			local name = self:consume().value
			if self:peekType() == TK.LPAREN then
				self:consume()
				if self:peekType() == TK.RPAREN then
					self:consume(); self:skipNewlines()
					local body = self:parseGroup()
					return AST.funcDef(name, body)
				end
			end
			self.pos = saved
		elseif tp == TK.LPAREN then
			self:consume(); self:skipNewlines()
			local list = self:parseList()
			self:skipNewlines()
			self:expect(TK.RPAREN)
			return AST.subshell(list)
		elseif tp == TK.LBRACE then
			return self:parseGroup()
		end

		return self:parseSimpleCmd()
	end

	function p:parseGroup()
		self:consume()  -- {
		self:skipNewlines()
		local list = self:parseList()
		self:skipNewlines()
		self:expect(TK.RBRACE)
		return AST.group(list)
	end

	function p:parseIf()
		self:consume()  -- if
		self:skipNewlines()
		local cond = self:parseList()
		self:skipNewlines()
		self:expect(TK.THEN)
		self:skipNewlines()
		local thenBody = self:parseList()
		self:skipNewlines()

		local elseifClauses = {}
		local elseBody = nil

		while self:peekType() == TK.ELIF do
			self:consume()
			self:skipNewlines()
			local eicond = self:parseList()
			self:skipNewlines()
			self:expect(TK.THEN)
			self:skipNewlines()
			local eibody = self:parseList()
			self:skipNewlines()
			table.insert(elseifClauses, { cond = eicond, body = eibody })
		end

		if self:peekType() == TK.ELSE then
			self:consume(); self:skipNewlines()
			elseBody = self:parseList()
			self:skipNewlines()
		end

		self:expect(TK.FI)
		return AST.ifNode(cond, thenBody, elseifClauses, elseBody)
	end

	function p:parseWhile()
		self:consume()  -- while
		self:skipNewlines()
		local cond = self:parseList()
		self:skipNewlines()
		self:expect(TK.DO); self:skipNewlines()
		local body = self:parseList()
		self:skipNewlines()
		self:expect(TK.DONE)
		return AST.whileNode(cond, body)
	end

	function p:parseUntil()
		self:consume()  -- until
		self:skipNewlines()
		local cond = self:parseList()
		self:skipNewlines()
		self:expect(TK.DO); self:skipNewlines()
		local body = self:parseList()
		self:skipNewlines()
		self:expect(TK.DONE)
		return AST.untilNode(cond, body)
	end

	function p:parseFor()
		self:consume()  -- for
		local varTok = self:expect(TK.WORD)
		if not varTok then return AST.error("expected variable name after for") end
		self:skipNewlines()
		local words = {}
		if self:peekType() == TK.IN then
			self:consume()
			while self:peekType() == TK.WORD do
				table.insert(words, self:consume().value)
			end
		end
		self:skipNewlines()
		if self:peekType() == TK.SEMI then self:consume() end
		self:skipNewlines()
		self:expect(TK.DO); self:skipNewlines()
		local body = self:parseList()
		self:skipNewlines()
		self:expect(TK.DONE)
		return AST.forNode(varTok.value, words, body)
	end

	function p:parseCase()
		self:consume()  -- case
		local word = self:peek().value; self:consume()
		self:skipNewlines()
		self:expect(TK.IN); self:skipNewlines()
		local items = {}
		while self:peekType() ~= TK.ESAC and self:peekType() ~= TK.EOF do
			-- patterns separated by |, ending with )
			local patterns = {}
			if self:peekType() == TK.LPAREN then self:consume() end
			while self:peekType() == TK.WORD do
				table.insert(patterns, self:consume().value)
				if self:peekType() == TK.PIPE then self:consume()
				else break end
			end
			if self:peekType() == TK.RPAREN then self:consume() end
			self:skipNewlines()
			local body = nil
			if self:peekType() ~= TK.SEMI and self:peekType() ~= TK.ESAC then
				body = self:parseList()
			end
			-- ;; or ;&
			if self:peekType() == TK.SEMI then self:consume() end
			if self:peekType() == TK.SEMI then self:consume() end
			self:skipNewlines()
			table.insert(items, { patterns = patterns, body = body })
		end
		self:expect(TK.ESAC)
		return AST.caseNode(word, items)
	end

	function p:parseFuncDef()
		self:consume()  -- function
		local name = self:expect(TK.WORD)
		if not name then return AST.error("expected function name") end
		if self:peekType() == TK.LPAREN then self:consume() end
		if self:peekType() == TK.RPAREN then self:consume() end
		self:skipNewlines()
		local body = self:parseCompoundOrSimple()
		return AST.funcDef(name.value, body)
	end

	return p
end

function Parser.parse(tokens)
	local p = newParser(tokens)
	p:skipNewlines()
	if p:peekType() == TK.EOF then return nil end
	return p:parseList()
end

return Parser
