#!/bin/bash

# Use JamfHelper tool to show alert message
jHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# Location of icon
icon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns"

# Set maximum days to X before warning about restart
maxDays="30"

# Get current uptime
upTimeDays=$(uptime | awk '{print $3}' | cut -d: -f1)

# Display uptime
echo "Uptime days: $upTimeDays"

# Advise user of uptime and give the option to reboot
msg="Your Mac has not been restarted for at least $upTimeDays days.
Please restart as soon as it is convenient in order to maintain smooth operation of your system."
msgnope="No need to restart yet.

You are still Ok, if your mac has been up for more than $maxDays days, you should restart."


# Check to see if machine has restarted in the last day
# See if "days" exists in the uptime
upTime=$(uptime | grep "days")
if [ -z "$upTime"  ];
then
    # Mac has been restarted within X days
    result=$("$jHelper" -windowType utility -description "$msgnope" -title "Reboot reminder" -button1 "Close" -defaultButton 2 -icon "$icon" -iconSize 90)
    echo "Mac has been up for less than $maxDays days. Exiting."
    exit 0
else 
    echo "More than one day"
fi


# If uptime is equal to or greater than X days then display message

if [ "$upTimeDays" -ge "$maxDays" ]; then
    echo "Mac has been up for more than $maxDays days"
    # Get answer from user
    result=$("$jHelper" -windowType utility -description "$msg" -title "Reboot reminder" -button1 "Restart now" -button2 "Not yet" -defaultButton 2 -icon "$icon" -iconSize 90)
    # If answer is Restart now, then restart
    if [ $result -eq 0 ];
    then
        echo "I am rebooting...."
        #reboot 
        shutdown -r now  
    else
    # Else delay restart
        echo "Not yet..."
        exit 0
    fi
else
    # Mac has been restarted within X days
    result=$("$jHelper" -windowType utility -description "$msgnope" -title "Reboot reminder" -button1 "Close" -defaultButton 2 -icon "$icon" -iconSize 90)
    echo "Mac has been up for less than $maxDays days. Exiting."
    exit 0
fi
