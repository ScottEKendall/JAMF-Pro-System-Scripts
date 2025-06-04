#!/bin/bash

LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
LOGGED_IN_UID=$(/usr/bin/id -u "$LOGGED_IN_USER")

/bin/launchctl asuser "${LOGGED_IN_UID}" /bin/launchctl stop /Library/LaunchAgents/com.zscaler.tray.plist

/bin/launchctl asuser "${LOGGED_IN_UID}" /bin/launchctl stop /Library/LaunchDaemons/com.zscaler.service.plist

/bin/launchctl asuser "${LOGGED_IN_UID}" /bin/launchctl stop /Library/LaunchDaemons/com.zscaler.tunnel.plist

/bin/rm -f /Library/LaunchAgents/com.zscaler.tray.plist
/bin/rm -f /Library/LaunchDaemons/com.zscaler.*
/bin/rm -rf /Applications/Zscaler

/usr/bin/killall ZscalerService
/usr/bin/killall ZscalerTunnel
/usr/bin/killall Zscaler
