#!/bin/zsh

# Define output file
output="/tmp/speedtest.txt"
# Get logged in user
loggedInUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }')
# Get Jamf helper location
Jhelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
# Run speed test
curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 - > "$output"
# Define the message
Message=$(cat "$output" | sed -e '/^Retrieving speedtest.net configuration/d ; /^Retrieving speedtest.net server list/d ; /^Selecting best server based on ping/d ; /^Testing download speed/d ; /^Testing upload speed/d')
# Run the Jamf helper window
Alert=$("$Jhelper" -windowType utility -title "Speed Test" -description "$Message" -button1 "Close" -defaultButton 1 -icon "/Users/$loggedInUser/Library/Application Support/com.jamfsoftware.selfservice.mac/Documents/Images/brandingimage.png" -iconSize 100)
if [ -f "$output" ]; then
        echo "$Message"
        exit 0
    else
        echo "Something went wrong"
        exit 1
fi
