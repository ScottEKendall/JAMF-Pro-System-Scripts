#!/bin/sh

# Variables
## Path to macOSLAPS binary ##
LAPS=/usr/local/laps/macOSLAPS
## Path to Password File ##
PW_FILE="/var/root/Library/Application Support/macOSLAPS-password"
## Local Admin Account ##
LOCAL_ADMIN=$(/usr/bin/defaults read \
    "/Library/Managed Preferences/edu.psu.macoslaps.plist" LocalAdminAccount)
    
defaultPassword=""

# Identify the location of the jamf binary for the jamf_binary variable.
CheckBinary (){
    # Identify location of jamf binary.
    jamf_binary=`/usr/bin/which jamf`

    if [[ "$jamf_binary" == "" ]] && [[ -e "/usr/sbin/jamf" ]] && [[ ! -e "/usr/local/bin/jamf" ]]; then jamf_binary="/usr/sbin/jamf";
    elif [[ "$jamf_binary" == "" ]] && [[ ! -e "/usr/sbin/jamf" ]] && [[ -e "/usr/local/bin/jamf" ]]; then jamf_binary="/usr/local/bin/jamf";
    elif [[ "$jamf_binary" == "" ]] && [[ -e "/usr/sbin/jamf" ]] && [[ -e "/usr/local/bin/jamf" ]]; then jamf_binary="/usr/local/bin/jamf";
    fi
}

# Verify that macOSLAPS is installed.  If not, exit immediately.
if [ ! -e $LAPS ]
then
    /bin/echo "macOSLAPS Not Installed"
    exit 0
fi

CheckBinary

# Reset local admin account password to a known default value
## Verify Local Admin Specified Exists ##
if  id "$LOCAL_ADMIN" &> /dev/null
    then
    /bin/echo "Account exists."
    if [ -z "$defaultPassword" ]; then
        echo "No default password has been specified.  Skipping password reset."
    else
        echo "A default password has been specified.  Reverting $LOCAL_ADMIN password to known default."
        
            ## Ask macOSLAPS to write out the current password and echo it for the Jamf EA
            $LAPS -getPassword > /dev/null
            CURRENT_PASSWORD=$( cat "$PW_FILE" )

            ## Test $current_password to ensure there is a value
            if [ -z "$CURRENT_PASSWORD" ]
            then
                echo "No password saved in keychain.  Assuming already using default."
            else
                ## Run macOSLAPS a second time to remove the password file
                ## and expiration date file from the system
                $LAPS
                # Change password back to default
                $jamf_binary changePassword -username $LOCAL_ADMIN -oldPassword $CURRENT_PASSWORD -password $defaultPassword
            fi
        
    fi

    # Account not found, no need to reset the password to a known default.
else
    /bin/echo "Account Not Found.  Skipping password reset."
fi
    

# Remove LaunchAgent
if [ -e /Library/LaunchDaemons/edu.psu.macoslaps-check.plist ]; then
    echo "Removing LaunchAgent"
    rm /Library/LaunchDaemons/edu.psu.macoslaps-check.plist
else
    echo "LaunchAgent not present"
fi

# Remove paths.d shortcut
if [ -e /private/etc/paths.d/laps ]; then
    echo "Removing macOSLAPS terminal shortcut"
    rm /private/etc/paths.d/laps
fi

# Remove Main Binary and repair tool
if [ -e $LAPS ]; then
    echo "Removing main binary and repair tool."
    rm -rf /usr/local/laps
fi

# Remove keychain entries
echo "Removing macOSLAPS keychain entries"
security delete-generic-password -l "macOSLAPS" /Library/Keychains/System.keychain || set t 0
