#!/bin/zsh

# Get the currently logged-in user
# JAMF typically populates $3 with the username in Self Service scripts
loggedInUser=$3

# If $3 is empty (common outside of Self Service), use stat as a fallback
if [ -z "$loggedInUser" ]; then
    loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
fi

# Run the command as the logged-in user
sudo -u "$loggedInUser" /usr/bin/defaults write -g NSMenuEnableActionImages -bool NO
