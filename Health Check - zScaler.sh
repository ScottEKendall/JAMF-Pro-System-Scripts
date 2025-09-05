#!/bin/zsh
# Check to see if the zScaler tunnel is running

currentUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
keychainKey=$(su - $currentUser -c "security find-generic-password -l 'com.zscaler.tray'")

# If the keychain entry is not found, they haven't logged in
[[ ! -z $keychainKey ]] && zStatus="Running" || zStatus="Error"
 
#report results
echo "$zStatus"
