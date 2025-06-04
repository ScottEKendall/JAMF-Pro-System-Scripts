#!/bin/zsh
toggle="${4:-"on"}"

if [[ "$toggle" == "off" ]]; then
	find /Library/LaunchAgents -name '*zscaler*' -exec launchctl unload {} \;;sudo find /Library/LaunchDaemons -name '*zscaler*' -exec launchctl unload {} \;
    echo "Unloaded zScaler"
else
	echo "Attempting to load zScaler"
 	launchctl bootstrap system /Library/LaunchDaemons/com.zscaler.service.plist
 	launchctl bootstrap system /Library/LaunchDaemons/com.zscaler.tunnel.plist
fi
