#!/bin/zsh

# Enable Location Services script

# Find the device UUID
uuid=$( /usr/sbin/ioreg -d2 -c IOPlatformExpertDevice | /usr/bin/awk -F\" '/IOPlatformUUID/{print $(NF-1)}' )

# Enable macOS Location Services
/usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -int 1
/usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd.$uuid LocationServicesEnabled -int 1

# Set date and time automatically
/usr/bin/defaults write /Library/Preferences/com.apple.timezone.auto Active -bool YES
/usr/bin/defaults write /private/var/db/timed/Library/Preferences/com.apple.timed.plist TMAutomaticTimeOnlyEnabled -bool YES
/usr/bin/defaults write /private/var/db/timed/Library/Preferences/com.apple.timed.plist TMAutomaticTimeZoneEnabled -bool YES

# Force time zone and time sync
/usr/sbin/systemsetup -setusingnetworktime on
/usr/sbin/systemsetup -gettimezone
/usr/sbin/systemsetup -getnetworktimeserver

# Restart Location Services daemon
/usr/bin/killall locationd

exit 0
