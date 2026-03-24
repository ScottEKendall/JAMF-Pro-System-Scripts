#!/bin/zsh
#
# Remove Docker.app and all of its files
set -x

LoggedInUser=$(echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
UserDir=$(dscl . -read /Users/${LoggedInUser} NFSHomeDirectory | awk '{ print $2 }' )

function clean_up ()
{
	for CleanUp_Path (
        "$UserDir/Library/Group Containers/group.com.docker"
        "$UserDir/Library/LaunchDaemons/com.docker.socket.plist"
        "/Library/PrivilegedHelperTools/com.docker.vmnetd"
        "/Library/PrivilegedHelperTools/com.docker.socket"
        "$UserDir/Library/Caches/com.docker.docker/"
        "$UserDir/Library/Containers/com.docker.docker/"
        "$UserDir/LibraryPreferences/com.docker.docker.plist/"
        "$UserDir/Library/Logs/Docker Desktop/"
        "$UserDir/.docker"
        "/Applications/Docker.app"
	) { [[ -e "${CleanUp_Path}" ]] && { rm -rf "${CleanUp_Path}" ;  echo "Cleaning up: ${CleanUp_Path}" ; }}
}

[[ -e "/Applications/Docker.app" ]] && /Applications/Docker.app/Contents/MacOS/uninstall
clean_up
