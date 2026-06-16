return function(proc, sys, argv)
	local host  = argv[2] or "localhost"
	local count = 4
	for i = 2, #argv do
		if argv[i] == "-c" then count = tonumber(argv[i+1]) or 4 end
	end

	sys.write(1, "PING " .. host .. " (127.0.0.1): 56 data bytes\n")
	for i = 1, count do
		sys.sleep(1)
		local rtt = math.random(1, 100) / 10
		sys.write(1, string.format("64 bytes from %s: icmp_seq=%d ttl=64 time=%.1f ms\n", host, i, rtt))
	end
	sys.write(1, string.format("\n--- %s ping statistics ---\n", host))
	sys.write(1, string.format("%d packets transmitted, %d received, 0%% packet loss\n", count, count))
	return 0
end
