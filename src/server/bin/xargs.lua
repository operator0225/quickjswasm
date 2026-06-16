return function(proc, sys, argv)
	local cmd = argv[2] or "echo"
	local args = {}
	for i = 3, #argv do table.insert(args, argv[i]) end
	local buf = ""
	while true do
		local chunk = sys.read(0, 4096)
		if not chunk or chunk == "" then break end
		buf ..= chunk
	end
	for token in buf:gmatch("%S+") do
		table.insert(args, token)
	end
	-- 서브셸에서 실행
	local Lexer    = require(script.Parent.Parent.shell.Lexer)
	local Parser   = require(script.Parent.Parent.shell.Parser)
	local Executor = require(script.Parent.Parent.shell.Executor)
	local line = cmd .. " " .. table.concat(args, " ")
	local tokens = Lexer.tokenize(line)
	local ast = Parser.parse(tokens)
	if ast then return Executor.execute(ast, proc, sys, {aliases={},functions={},history={},jobs={}}) end
	return 0
end
