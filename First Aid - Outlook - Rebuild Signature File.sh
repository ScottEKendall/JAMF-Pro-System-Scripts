#!/bin/zsh

# Written: May 27, 2025
# Last updated: May 27, 2025
# by: Scott Kendall
#
# Script Purpose: Force Outlook desktop app to reindex all of the signatures by deleting the .sqlite files
#
# Version History
#
# 1.0 - Initial code
######################################################################################################
#
# Gobal "Common" variables
#
######################################################################################################

LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
USER_DIR=$( dscl . -read /Users/${LOGGED_IN_USER} NFSHomeDirectory | awk '{ print $2 }' )
OUTLOOK_DIR="${USER_DIR}/Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles/Main Profile/Data"

cd "${OUTLOOK_DIR}"
rm -rf *.sqlite*
exit 0
