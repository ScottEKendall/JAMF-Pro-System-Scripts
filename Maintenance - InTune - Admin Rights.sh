#!/bin/zsh
#
# by: Scott Kendall
#
# Written: 09/08/2025

# Script determines if users is a member of GE Corporate Mac Users-Admins and send results to the user .plist file
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
SUPPORT_DIR="/Users/$LOGGED_IN_USER/Library/Application Support"
JSS_FILE="$SUPPORT_DIR/com.GiantEagleEntra.plist"
JQ_INSTALL_POLICY="install_jq"
DOMAIN="gianteagle.com"

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

function msgraph_get_access_token ()
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

function msgraph_upn_sanity_check ()
{
    # PURPOSE: format the user name to make sure it is in the format <first.last>@domain.com
    # RETURN: Properly formatted UPN name
    # PARAMETERS: $1 = User name
    # EXPECTED: LOGGED_IN_USER, DOMAIN

    # if the local name already contains “@”, then it should be good
    if [[ "$LOGGED_IN_USER" == *"@"* ]]; then
        echo "$LOGGED_IN_USER"
        return 0
    fi
    # if it ends with the domain without the “@” → we add the @ sign
    if [[ "$LOGGED_IN_USER" == *"$DOMAIN" ]]; then
        CLEAN_USER=${LOGGED_IN_USER%$DOMAIN}
        MS_USER_NAME="${CLEAN_USER}@${DOMAIN}"
    else
        # 3) normal short name → user@domain
        MS_USER_NAME="${LOGGED_IN_USER}@${DOMAIN}"
    fi
    echo $MS_USER_NAME
}

function msgraph_get_group_data ()
{
    # PURPOSE: Retrieve the user's Graph API group membership
    # RETURN: None
    # EXPECTED: MS_USER_NAME, ms_access_token, MSGRAPH_GROUP

    response=$(curl -s -X GET "https://graph.microsoft.com/v1.0/users/$MS_USER_NAME/memberOf" -H "Authorization: Bearer $ms_access_token" | jq -r '.value[].displayName')

    # Use a while loop to read and handle the line break delimiter - store the final list into an array
    MSGRAPH_GROUPS=()
    while IFS= read -r line; do
        MSGRAPH_GROUPS+=("$line")
    done <<< "$response"
}

####################################################################################################
#
# Main Script
#
####################################################################################################

declare MSGRAPH_GROUPS
declare ADMIN_GROUP="GE Corporate Mac Users-Admins"

check_support_files

# Get Access token
msgraph_get_access_token
MS_USER_NAME=$(msgraph_upn_sanity_check $MS_USER_NAME)

# Read in group data and see if user is part of admin group
msgraph_get_group_data
adminUser="No"
for item in ${MSGRAPH_GROUPS[@]}; do
    if [[ "$item" == "$ADMIN_GROUP" ]]; then
        adminUser="Yes" 
        echo "INFO: Admin Privlege found"
    fi
done
retval=$(/usr/libexec/plistbuddy -c "print EntraAdminRights" $JSS_FILE 2>&1)
echo "Read : "$retval
if [[ "$retval" == *"Does Not Exist"* ]]; then
    echo "INFO: Creating Admin Field"
    retval=$(/usr/libexec/plistbuddy -c "add EntraAdminRights string $adminUser" $JSS_FILE 2>&1)
else
    echo "INFO: Recording Privlege"
    retval=$(/usr/libexec/plistbuddy -c "set EntraAdminRights $adminUser" $JSS_FILE 2>&1)
    [[ ! -z $retval ]] && echo "ERROR: Results of last command: "$retval
fi
exit 0