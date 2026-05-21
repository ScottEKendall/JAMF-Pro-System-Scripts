#!/bin/zsh 
#
# Script Purpose: Allow non-admin users to change wifi settings without admin password
#
# This script modifies the authorization rules for the system preferences and network preference panes to allow non-admin users to access and modify wifi settings without requiring an admin password. 
# It uses the `security` command to read and write authorization rules, and `PlistBuddy` to modify the plist files that contain these rules. 
# The script ensures that the necessary permissions are set for both the system preferences and network preference panes, allowing users to change wifi settings without administrative privileges.
# Variables 
SECURITYBIN="/usr/bin/security" 
PLISTBUDDYBIN="/usr/libexec/PlistBuddy" 
# Write authorization rules
$SECURITYBIN authorizationdb write system.preferences.network allow 
$SECURITYBIN authorizationdb write system.services.systemconfiguration.network allow 
$SECURITYBIN authorizationdb write com.apple.wifi allow 

# Set airport preferences
/usr/libexec/airportd prefs RequireAdminNetworkChange=NO RequireAdminIBSS=NO 

# Read authorization rules into temporary files
$SECURITYBIN authorizationdb read system.preferences > /tmp/system.preferences.plist 
$SECURITYBIN authorizationdb read system.preferences.network > /tmp/system.preferences.network.plist 

# Allow access to system wide preference panes
TARGETPLIST="/tmp/system.preferences.plist" 
ARRAY=($($PLISTBUDDYBIN -c "print :rule" $TARGETPLIST | sed -e 's/^Array {//' | sed -e 's/}//' | xargs )) 
#echo $ARRAY 
if [[ ! $ARRAY =~ '(^allow)|(\sallow)' ]] ; then 
    echo "Modifying $TARGETPLIST" 
    $PLISTBUDDYBIN -c "set :class rule" $TARGETPLIST 
    $PLISTBUDDYBIN -c "add :rule array" $TARGETPLIST 
    $PLISTBUDDYBIN -c "add :rule: string allow" $TARGETPLIST 
    $PLISTBUDDYBIN -c "set :shared true" $TARGETPLIST 
    $PLISTBUDDYBIN -c "delete :authenticate-user" $TARGETPLIST 
    $PLISTBUDDYBIN -c "delete :group" $TARGETPLIST 
fi 

# Allow access to network preference pane
TARGETPLIST="/tmp/system.preferences.network.plist" 
ARRAY=($($PLISTBUDDYBIN -c "print :rule" $TARGETPLIST | sed -e 's/^Array {//' | sed -e 's/}//' | xargs )) 
#echo $ARRAY 
if [[ ! $ARRAY =~ '(^allow)|(\sallow)' ]] ; then 
    echo "Modifying $TARGETPLIST" 
    $PLISTBUDDYBIN -c "set :class rule" $TARGETPLIST 
    $PLISTBUDDYBIN -c "add :rule array" $TARGETPLIST 
    $PLISTBUDDYBIN -c "add :rule: string allow" $TARGETPLIST 
    $PLISTBUDDYBIN -c "set :shared true" $TARGETPLIST 
    $PLISTBUDDYBIN -c "delete :authenticate-user" $TARGETPLIST 
    $PLISTBUDDYBIN -c "delete :group" $TARGETPLIST 
fi 

$SECURITYBIN authorizationdb write system.preferences < /tmp/system.preferences.plist 
$SECURITYBIN authorizationdb write system.preferences.network < /tmp/system.preferences.network.plist 
