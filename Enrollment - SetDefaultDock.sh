export PATH=/usr/bin:/bin:/usr/sbin:/sbin
LoggedInUser=$(echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
UserDir=$(dscl . -read /Users/${LoggedInUser} NFSHomeDirectory | awk '{ print $2 }' )

cp -f "/Library/Application Support/GiantEagle/Enrollment/com.apple.dock.plist" "${UserDir}/Library/Preferences"
killall Dock
