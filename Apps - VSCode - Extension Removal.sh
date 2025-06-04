#!/bin/bash

# Get the current logged-in user and their home directory
LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
USER_DIR=$( dscl . -read /Users/${LOGGED_IN_USER} NFSHomeDirectory | awk '{ print $2 }' )

rm -rf "$USER_DIR/.vscode/extensions/equinusocio.vsc-material-theme*"
rm -rf "$USER_DIR/.vscode/extensions/equinusocio.vsc-material-theme-icons*"
echo "Malicious extensions removed."
