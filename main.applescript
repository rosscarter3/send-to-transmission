-- Send to Transmission: a macOS handler for magnet links and .torrent files
-- that hands each one to a Transmission daemon on another machine.
-- The work is done by send.sh, in the app's Resources folder.

on open location theURL
	send(theURL)
end open location

on open theFiles
	repeat with f in theFiles
		send(POSIX path of f)
	end repeat
end open

on run
	set webURL to do shell script (sh()) & " --web-url"
	display dialog "Click a magnet link or open a .torrent file and it is sent to Transmission at:" & return & webURL buttons {"Open web UI", "OK"} default button "OK" with title "Send to Transmission"
	if button returned of result is "Open web UI" then open location webURL
end run

on sh()
	return quoted form of (POSIX path of (path to resource "send.sh"))
end sh

on send(thing)
	try
		set n to do shell script (sh()) & " " & quoted form of thing
		display notification n with title "Sent to Transmission"
	on error msg
		activate
		display alert "Couldn't send to Transmission" message msg as critical
	end try
end send
