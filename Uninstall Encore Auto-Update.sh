#!/bin/bash


/bin/rm -rf "/Applications/Utilities/Managed Software Update.app"
/bin/rm -rf "/Applications/Managed Software Center.app"

/bin/rm -f /Library/LaunchDaemons/com.googlecode.munki.*
/bin/rm -f /Library/LaunchAgents/com.googlecode.munki.*
/bin/rm -rf "/Library/Managed Installs"
/bin/rm -f /Library/Preferences/ManagedInstalls.plist
/bin/rm -rf /usr/local/munki
/bin/rm /etc/paths.d/munki
/bin/rm -rf "/Applications/Utilities/Notifier.app"

if [[ -e /Library/LaunchDaemons/com.googlecode.munki.* ]]; then
	/bin/launchctl unload /Library/LaunchDaemons/com.googlecode.munki.*
fi


/usr/sbin/pkgutil --forget com.googlecode.munki.admin
/usr/sbin/pkgutil --forget com.googlecode.munki.app
/usr/sbin/pkgutil --forget com.googlecode.munki.core
/usr/sbin/pkgutil --forget com.googlecode.munki.launchd
/usr/sbin/pkgutil --forget com.googlecode.munki.app_usage
