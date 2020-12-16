use AppleScript version "2.4" -- Yosemite (10.10) or later
use scripting additions
use framework "Foundation"

property pTitle : "DEVONthink Smart Rename"

on run
	tell application "Finder"
		set current_path to container of (path to me) as alias
		set current_path to "/Users/You/PathToPerlScriptFolder/"
		set myScriptPath to POSIX path of current_path & "smartrename.pl"
		-- log current_path
		-- log myScriptPath
	end tell
	
	tell application id "DNtp"
		-- display dialog "Hello"
		if not (exists think window 1) then error "No window is open."
		-- if not (exists content record) then error "Please open exactly one document."
		
		set selectedText to selected text of think window 1 as string
		-- log selectedText
		
		-- set today to do shell script "date +'%Y-%m-%d'"
		
		try
			set selectedItems to selection
			
			repeat with selectedItem in selectedItems
				if class of selectedItem = record then
					
					set documentName to name of selectedItem as Unicode text
					-- log documentName
					set _creationDate to creation date of selectedItem
					-- log _creationDate
					set creationDate to my formatDate(_creationDate)
					-- log _creationDate
					
					set scriptCommand to ("perl " & quoted form of (myScriptPath) & space & quoted form of documentName & space & quoted form of creationDate & space & quoted form of selectedText) as Unicode text
					-- set scriptCommand to ("perl " & quoted form of (myScriptPath) & space & quoted form of "„Hallö ß ü — -" & space & quoted form of creationDate)
					-- log scriptCommand
					
					set newName to (do shell script scriptCommand)
					-- set test to do shell script "echo " & quoted form of "Hallö" & " | sed -E 's/" & "ö" & "/" & "o" & "/g'"
					-- set test to do shell script "echo " & "„Hallö ß ü — -" & "| perl -e ' print @ARGV[0,1]; while (<STDIN>) { print } '"
					
					-- log test
					-- display alert newName
					
					set name of selectedItem to newName
					
				else
					-- log "Not a record"
				end if
			end repeat
			
		on error error_message number error_number
			-- if error_number is not -128 then display alert "DEVONthink" message error_message as warning
			if error_number is not -128 then log error_message
		end try
	end tell
end run

on formatDate(baseDate)
	set [_day, _month, _year] to [day, month, year] of baseDate
	# Change "May" to "5" -> crazy
	set _month to _month * 1
	set _month to text -1 thru -2 of ("0" & _month)
	set _day to text -1 thru -2 of ("0" & _day)
	set the text item delimiters to "-"
	return {_year, _month, _day} as string
end formatDate
