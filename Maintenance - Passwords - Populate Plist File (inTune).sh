#!/bin/zsh
#
# by: Scott Kendall
#
# Written: 09/03/2025
# Last updated: 09/04/2025

# Script to populate /Library/Managed Preferences/com.gianteagle.jss file with uses EntraID password info
# 
# 1.0 - Initial code
#
######################################################################################################
#
# Gobal "Common" variables
#
######################################################################################################

LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
MS_USER_NAME=$(dscl . read /Users/$LOGGED_IN_USER | grep "NetworkUser" | awk -F ':' '{print $2}' | xargs)

SUPPORT_DIR="/Library/Application Support/GiantEagle"
LOG_FILE="${SUPPORT_DIR}/logs/PopulatePasswordPlist"
JQ_INSTALL_POLICY="install_jq"
JSS_FILE="/Library/Managed Preferences/com.gianteagle.jss.plist"

##################################################
#
# Passed in variables
# 
#################################################

JAMF_LOGGED_IN_USER=$3                          # Passed in by JAMF automatically  
CLIENT_ID="$4"
CLIENT_SECRET="$5"
TENANT_ID="$6"

####################################################################################################
#
# Functions
#
####################################################################################################

function check_support_files ()
{
    [[ $(which jq) == *"not found"* ]] && /usr/local/bin/jamf policy -trigger ${JQ_INSTALL_POLICY}
}

function get_MS_access_token ()
{
    # PURPOSE: obtain the MS inTune Graph API Token
    # RETURN: access_token
    # EXPECTED: TENANT_ID, CLIENT_ID, CLIENT_SECRET

    token_response=$(curl -s -X POST "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&scope=https://graph.microsoft.com/.default")

    ms_access_token=$(echo "$token_response" | jq -r '.access_token')

    if [[ "$ms_access_token" == "null" ]] || [[ -z "$ms_access_token" ]]; then
        echo "Failed to acquire access token"
        echo "$token_response"
        exit 1
    fi
    echo "Valid Token Acquired"
}

function get_ms_user_data ()
{
    # PURPOSE: Retrieve the user's Graph API Record
    # RETURN: last_password_change
    # EXPECTED: MS_USER_NAME, ms_access_token

    user_response=$(curl -s -X GET "https://graph.microsoft.com/v1.0/users/$MS_USER_NAME?\$select=lastPasswordChangeDateTime" -H "Authorization: Bearer $ms_access_token")

    last_password_change=$(echo "$user_response" | jq -r '.lastPasswordChangeDateTime')
    echo $last_password_change

}

# Define the function to calculate days between today and the given date

function calculate_days_between() {

    # Convert passdate to seconds since the epoch
    local passdate_seconds=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" "+%s")
    
    # Get today's date in seconds since the epoch
    local today_seconds=$(date "+%s")
    
    # Calculate the difference in seconds
    local difference=$((today_seconds - passdate_seconds))
    
    # Convert seconds to days
    local difference_days=$((difference / 86400))
    
    echo $difference_days
}

####################################################################################################
#
# Main Script
#
####################################################################################################
declare ms_access_token
declare last_password_change

forceRecon="No"

check_support_files

# Routine for getitng the info from MS Intune Graph API
get_MS_access_token
newPasswordDate=$(get_ms_user_data)

# the date of 1601-01-01T00:00:00Z means that a user has never changed their password.  That is the default MS Epoch time...
if [[ -z $newPasswordDate ]] || [[ "$newPasswordDate" == "null" ]] || "$newPasswordDate" == "1601-01-01T00:00:00Z"; then
	# Couldn't find the key in the plist file, so we have to rely on the local login password last changed date
    
    passwordAge=$(expr $(expr $(date +%s) - $(dscl . read /Users/${LOGGED_IN_USER} | grep -A1 passwordLastSetTime | grep real | awk -F'real>|</real' '{print $2}' | awk -F'.' '{print $1}')) / 86400)
    
	[[ -z ${passwordAge} ]] && passwordAge=0
	newPasswordDate=$(date -j -v-${passwordAge}d +"%Y-%m-%dT12:00:00Z")
    forceRecon="Yes"
    echo "INFO: The PLIST entry is blank.  New Password Date is: ${newPasswordDate} based off of local system password."
    echo "INFO: JAMF inventory update triggered"
fi
# Determine the password age 
passwordAge=$(calculate_days_between "$newPasswordDate")

echo "INFO: inTune password date shows: $newPasswordDate"
echo "INFO: Curent Password Age: $passwordAge"

# Get the value of the date stored in our plist file
retval=$(/usr/libexec/plistbuddy -c "print PasswordLastChanged" $JSS_FILE 2>&1)

# If the password is blank, then set it to the calculated value
[[ -z $retval ]]  || [[ "$retval" == "null" ]] && retval=$newPasswordDate

# do a quick santity check...convert both dates to epoch time
timestamp_lastretval=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" $retval +%s)
timestamp_lastPass=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" $newPasswordDate +%s)

# and see if the inTune password is greater than the recorded date, if so, then set it to the inTune password
if [[ $timestamp_lastPass -gt $timestamp_lastretval ]]; then
	echo "INFO: inTune password date is greater than stored date...using inTune date for reference"
    forceRecon="Yes"
	retval=$newPasswordDate
fi

# Store the Password Last Date changed in this file
if [[ $retval == *"Does Not Exist"* ]]; then
    # Entry does not exist so lets create it and populate the userPassword into it
    retval=$(/usr/libexec/plistbuddy -c "add PasswordLastChanged string $newPasswordDate" $JSS_FILE 2>&1)
    echo "INFO: Created new key 'PasswordLastChanged' with contents $newPasswordDate"
else
    #found the key, so let replace (set) it instead
    retval=$(/usr/libexec/plistbuddy -c "set PasswordLastChanged $newPasswordDate" $JSS_FILE 2>&1)	
    echo "INFO: Replaced key 'PasswordLastChanged' with contents $newPasswordDate"
fi
[[ ! -z $retval ]] && echo "ERROR: Results of last command: "$retval

# Store the Password Age in this file as well
retval=$(/usr/libexec/plistbuddy -c "print PasswordAge" $JSS_FILE 2>&1)

if [[ $retval == *"Does Not Exist"* ]]; then
    # Entry does not exist so lets create it and populate the Password Age into it"
    retval=$(/usr/libexec/plistbuddy -c "add PasswordAge string $passwordAge" $JSS_FILE 2>&1)
    echo "INFO: Created new key 'PasswordAge' with contents $passwordAge"

else
    #found the key, so let replace (set) it instead
    retval=$(/usr/libexec/plistbuddy -c "set PasswordAge $passwordAge" $JSS_FILE 2>&1)	
    echo "INFO: Replaced key 'PasswordAge' with contents $passwordAge"
fi
[[ ! -z $retval ]] && echo "ERROR: Results of last command: "$retval

[[ "${forceRecon}" == "Yes" ]] && jamf recon
exit 0