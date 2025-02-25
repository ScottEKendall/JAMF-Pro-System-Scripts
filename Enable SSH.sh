#!/bin/sh

# trun ssh off
#systemsetup -f -setremotelogin off
# turn ssh on
systemsetup -f -setremotelogin on


#Add Administrator to Remote Login access list
dseditgroup -o edit -a "$4" -t user com.apple.access_ssh

# restart ssh
launchctl unload /System/Library/LaunchDaemons/ssh.plist
sleep 5
launchctl load -w /System/Library/LaunchDaemons/ssh.plist

exit 0