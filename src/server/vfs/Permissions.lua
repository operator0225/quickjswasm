local Permissions = {}

-- flags: "r", "w", "x" 또는 조합
function Permissions.check(inode, uid, gid, flags)
	if uid == 0 then return true end  -- root 무적

	local mode = inode.mode
	local shift
	if inode.uid == uid then
		shift = 6   -- user bits
	elseif inode.gid == gid then
		shift = 3   -- group bits
	else
		shift = 0   -- other bits
	end

	for i = 1, #flags do
		local ch = flags:sub(i, i)
		local bit
		if ch == "r" then bit = bit32.lshift(4, shift)
		elseif ch == "w" then bit = bit32.lshift(2, shift)
		elseif ch == "x" then bit = bit32.lshift(1, shift)
		end
		if bit and bit32.band(mode, bit) == 0 then
			return false
		end
	end
	return true
end

return Permissions
