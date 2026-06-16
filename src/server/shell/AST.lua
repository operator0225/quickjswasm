local AST = {}

AST.SimpleCmd  = "SimpleCmd"
AST.Pipeline   = "Pipeline"
AST.List       = "List"
AST.Background = "Background"
AST.If         = "If"
AST.While      = "While"
AST.Until      = "Until"
AST.For        = "For"
AST.Case       = "Case"
AST.FuncDef    = "FuncDef"
AST.Subshell   = "Subshell"
AST.Group      = "Group"
AST.Redirect   = "Redirect"
AST.Error      = "Error"

function AST.simpleCmd(words, redirs)
	return { type = AST.SimpleCmd, words = words or {}, redirs = redirs or {} }
end

function AST.pipeline(cmds, negate)
	return { type = AST.Pipeline, cmds = cmds, negate = negate or false }
end

function AST.list(left, op, right)
	return { type = AST.List, left = left, op = op, right = right }
end

function AST.background(cmd)
	return { type = AST.Background, cmd = cmd }
end

function AST.ifNode(cond, thenBody, elseifClauses, elseBody)
	return { type = AST.If, cond = cond, then_body = thenBody,
	         elseif_clauses = elseifClauses or {}, else_body = elseBody }
end

function AST.whileNode(cond, body)
	return { type = AST.While, cond = cond, body = body }
end

function AST.untilNode(cond, body)
	return { type = AST.Until, cond = cond, body = body }
end

function AST.forNode(var, words, body)
	return { type = AST.For, var = var, words = words, body = body }
end

function AST.caseNode(word, items)
	return { type = AST.Case, word = word, items = items }
end

function AST.funcDef(name, body)
	return { type = AST.FuncDef, name = name, body = body }
end

function AST.subshell(list)
	return { type = AST.Subshell, list = list }
end

function AST.group(list)
	return { type = AST.Group, list = list }
end

function AST.redirect(fd, op, target)
	return { type = AST.Redirect, fd = fd, op = op, target = target }
end

function AST.error(msg)
	return { type = AST.Error, msg = msg }
end

return AST
