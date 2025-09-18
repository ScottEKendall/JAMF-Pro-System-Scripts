#!/bin/zsh
#
# by: Scott Kendall
#
# Written: 09/03/2025
# Last updated: 09/08/2025

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
USER_HOME="/Users/$LOGGED_IN_USER"
MS_USER_NAME=$(dscl . read $USER_HOME | grep "NetworkUser" | awk -F ':' '{print $2}' | xargs)

SUPPORT_DIR="$USER_HOME/Library/Application Support"
USER_JSS_FILE="$SUPPORT_DIR/com.GiantEagleEntra.plist"
SYSTEM_JSS_FILE="/Library/Managed Preferences/com.jamf.pro.plist"

JQ_INSTALL_POLICY="install_jq"

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

function msgraph_getdomain ()
{
    # PURPOSE: construct the domain from the jamf.plist file
    # PARAMETERS: None
    # RETURN: None
    # EXPECTED: MS_DOMAIN

    local url
    url=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)

    # Extract the desired part using Zsh parameter expansion
    tmp=${url#*://}  # Remove the protocol part
    MS_DOMAIN=${tmp%%.*}".com"  # Remove everything after the first dot and add '.com' to the end
}

function msgraph_get_access_token ()
{
    # PURPOSE: obtain the MS inTune Graph API Token
    # PARAMETERS: None
    # RETURN: access_token
    # EXPECTED: TENANT_ID, CLIENT_ID, CLIENT_SECRET

    token_response=$(curl -s -X POST "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&scope=https://graph.microsoft.com/.default")

    MS_ACCESS_TOKEN=$(echo "$token_response" | jq -r '.access_token')

    if [[ "$MS_ACCESS_TOKEN" == "null" ]] || [[ -z "$MS_ACCESS_TOKEN" ]]; then
        echo "Failed to acquire access token"
        echo "$token_response"
        exit 1
    fi
    echo "Valid Token Acquired"
}

function msgraph_upn_sanity_check ()
{
    # PURPOSE: format the user name to make sure it is in the format <first.last>@domain.com
    # RETURN: None
    # PARAMETERS: None
    # EXPECTED: LOGGED_IN_USER, MS_DOMAIN, MS_USER_NAME

    # if the local name already contains “@”, then it should be good
    CLEAN_USER=""
    MS_USER_NAME="scottkendall"
    [[ "$MS_USER_NAME" == *"@"* ]] && CLEAN_USER=$MS_USER_NAME
    # If the user name doesn't have a "." in it, then it must be formatted correctly so that MS Graph API can find them
    
    # if it isn't ormatted correctly, grab it from the users com.microsoft.CompanyPortalMac.usercontext.info
    if [[ "$CLEAN_USER" != *"."* ]] && [[ -e "$SUPPORT_DIR/com.microsoft.CompanyPortalMac.usercontext.info" ]]; then
        echo "INFO: Trying to acquire network user name from MS UserContext File"
        CLEAN_USER=$(/usr/bin/more $SUPPORT_DIR/com.microsoft.CompanyPortalMac.usercontext.info | xmllint --xpath 'string(//dict/key[.="aadUserId"]/following-sibling::string[1])' -)
        echo "INFO: User name found: $CLEAN_USER"
    fi
    
    # if it still isn't formatted correctly, try the email from the system JSS file
    
    if [[ "$CLEAN_USER" != *"."* ]]; then
        echo "INFO: Trying to acquire network name from $SYSTEM_JSS_FILE"
        CLEAN_USER=$(/usr/libexec/plistbuddy -c "print 'User Name'" $SYSTEM_JSS_FILE 2>&1)
        echo "INFO: User name found: $CLEAN_USER"
    fi

    # if it has the correct domain and formatted properly then assign it the MS_USER_NAME
    if [[ "$CLEAN_USER" == *"$MS_DOMAIN" && "$CLEAN_USER" == *"."* ]]; then
        MS_USER_NAME=$CLEAN_USER
    else
        # 3) normal short name → user@domain
        MS_USER_NAME="${LOGGED_IN_USER}@${MS_DOMAIN}"
    fi
}

function msgraph_get_password_data ()
{
    # PURPOSE: Retrieve the user's Graph API Record
    # RETURN: last_password_change
    # EXPECTED: MS_USER_NAME, MS_ACCESS_TOKEN

    user_response=$(curl -s -X GET "https://graph.microsoft.com/v1.0/users/$MS_USER_NAME?\$select=lastPasswordChangeDateTime" -H "Authorization: Bearer $MS_ACCESS_TOKEN")
    last_password_change=$(echo "$user_response" | jq -r '.lastPasswordChangeDateTime')
    echo $last_password_change

}

# Define the function to calculate days between today and the given date

function calculate_days_between() 
{

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

function check_logged_in_user () 
{
    if [[ ! -n "$LOGGED_IN_USER" ]]; then
        echo "No user is logged in"
        exit 0
    fi
}

####################################################################################################
#
# Main Script
#
####################################################################################################
declare ms_access_token
declare last_password_change
declare MS_DOMAIN

forceRecon="No"
noPasswordEntry="false"

check_support_files
check_logged_in_user

# Routine for getitng the info from MS Intune Graph API
msgraph_getdomain
msgraph_get_access_token
msgraph_upn_sanity_check
newPasswordDate=$(msgraph_get_password_data)

echo "INFO: Logged-in user (short name): $LOGGED_IN_USER"
echo "INFO: Resolved UPN for Graph: $MS_USER_NAME"
echo "INFO: Plist file: $USER_JSS_FILE"

# the date of 1601-01-01T00:00:00Z means that a user has never changed their password.  That is the default MS Epoch time...
if [[ -z $newPasswordDate ]] || [[ "$newPasswordDate" == "null" ]] || [[ "$newPasswordDate" == "1601-01-01T00:00:00Z" ]]; then
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
retval=$(/usr/libexec/plistbuddy -c "print PasswordLastChanged" $USER_JSS_FILE 2>&1)
# If the password is blank, then set it to the calculated value
[[ "$retval" == *"Does Not Exist"* ]] && {noPasswordEntry="true"; retval="null";}
[[ -z $retval ]] || [[ "$retval" == "null" ]]  && retval=$newPasswordDate

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
if [[ $retval == *"Does Not Exist"* ]] || [[ "$noPasswordEntry" == "true" ]]; then
    # Entry does not exist so lets create it and populate the userPassword into it
    retval=$(/usr/libexec/plistbuddy -c "add PasswordLastChanged string $newPasswordDate" $USER_JSS_FILE 2>&1)
    echo "INFO: Created new key 'PasswordLastChanged' with contents $newPasswordDate"
else
    #found the key, so let replace (set) it instead
    retval=$(/usr/libexec/plistbuddy -c "set PasswordLastChanged $newPasswordDate" $USER_JSS_FILE 2>&1)	
    echo "INFO: Replaced key 'PasswordLastChanged' with contents $newPasswordDate"
fi
[[ ! -z $retval ]] && echo "ERROR: Results of last command: "$retval

# Store the Password Age in this file as well
retval=$(/usr/libexec/plistbuddy -c "print PasswordAge" $USER_JSS_FILE 2>&1)

if [[ $retval == *"Does Not Exist"* ]]; then
    # Entry does not exist so lets create it and populate the Password Age into it"
    retval=$(/usr/libexec/plistbuddy -c "add PasswordAge string $passwordAge" $USER_JSS_FILE 2>&1)
    echo "INFO: Created new key 'PasswordAge' with contents $passwordAge"

else
    #found the key, so let replace (set) it instead
    retval=$(/usr/libexec/plistbuddy -c "set PasswordAge $passwordAge" $USER_JSS_FILE 2>&1)	
    echo "INFO: Replaced key 'PasswordAge' with contents $passwordAge"
fi
[[ ! -z $retval ]] && echo "ERROR: Results of last command: "$retval

[[ "${forceRecon}" == "Yes" ]] && jamf recon
exit 0
