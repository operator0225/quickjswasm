return function(proc, sys, argv)
	local uid = proc.uid
	local gid = proc.gid
	local name = proc.env["USER"] or "user"
	sys.write(1, string.format("uid=%d(%s) gid=%d(%s) groups=%d(%s)\n",
		uid, name, gid, name, gid, name))
	return 0
end
