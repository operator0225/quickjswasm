local E     = require(script.Parent.Parent.Parent.shared.Errno)
local C     = require(script.Parent.Parent.Parent.shared.Constants)
local Inode = require(script.Parent.Inode)

-- 순수 메모리 FS (/tmp 용)
local nodes = {}  -- { [path] = { inode, content } }

-- 루트 디렉토리
nodes["/"] = { inode = Inode.new({ mode = C.S_IFDIR + 0x1ED }), content = "" }

local TmpFS = {}

local function normPath(p)
	p = p:gsub("//+", "/")
	if p ~= "/" then p = p:gsub("/$", "") end
	return p
end

local function parentOf(p)
	local parent = p:match("^(.*)/[^/]+$")
	return (parent == "" or parent == nil) and "/" or parent
end

function TmpFS.stat(path)
	path = normPath(path)
	local node = nodes[path]
	if not node then return nil, E.ENOENT end
	return node.inode
end

function TmpFS.readdir(path)
	path = normPath(path)
	local node = nodes[path]
	if not node then return nil, E.ENOENT end
	if not Inode.isDir(node.inode.mode) then return nil, E.ENOTDIR end

	local entries = {}
	local prefix = path == "/" and "/" or (path .. "/")
	for p in pairs(nodes) do
		if p ~= path and p:sub(1, #prefix) == prefix then
			local rest = p:sub(#prefix + 1)
			if not rest:find("/") then
				table.insert(entries, rest)
			end
		end
	end
	return entries
end

function TmpFS.read(path)
	path = normPath(path)
	local node = nodes[path]
	if not node then return nil, E.ENOENT end
	if Inode.isDir(node.inode.mode) then return nil, E.EISDIR end
	return node.content
end

function TmpFS.write(path, content)
	path = normPath(path)
	local parent = parentOf(path)
	if not nodes[parent] then return nil, E.ENOENT end

	if nodes[path] then
		nodes[path].content = content
		nodes[path].inode.size  = #content
		nodes[path].inode.mtime = os.time()
	else
		nodes[path] = {
			inode   = Inode.new({ mode = C.S_IFREG + 0x1B6, size = #content }),
			content = content,
		}
	end
	return 0
end

function TmpFS.mkdir(path)
	path = normPath(path)
	if nodes[path] then return nil, E.EEXIST end
	local parent = parentOf(path)
	if not nodes[parent] then return nil, E.ENOENT end
	nodes[path] = { inode = Inode.new({ mode = C.S_IFDIR + 0x1ED }), content = "" }
	return 0
end

function TmpFS.unlink(path)
	path = normPath(path)
	if not nodes[path] then return nil, E.ENOENT end
	nodes[path] = nil
	return 0
end

function TmpFS.rename(oldPath, newPath)
	oldPath = normPath(oldPath)
	newPath = normPath(newPath)
	if not nodes[oldPath] then return nil, E.ENOENT end
	nodes[newPath] = nodes[oldPath]
	nodes[oldPath] = nil
	return 0
end

return TmpFS
