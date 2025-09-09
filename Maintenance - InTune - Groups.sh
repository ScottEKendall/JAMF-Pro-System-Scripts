#!/bin/zsh
#
# by: Scott Kendall
#
# Written: 09/09/2025
# Last updated: 09/09/2025

# Script to retrieve users groups from EntraID and store them in the Users plist file
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
function msgraph_getdomain ()
{
    local url
    url=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)

    # Extract the desired part using Zsh parameter expansion
    tmp=${url#*://}  # Remove the protocol part
    MS_DOMAIN=${tmp%%.*}".com"  # Remove everything after the first dot and add '.com' to the end
}

function msgraph_get_access_token ()
{
    # PURPOSE: obtain the MS inTune Graph API Token
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
    # PARAMETERS: $1 = User name
    # EXPECTED: LOGGED_IN_USER, MS_DOMAIN, MS_USER_NAME

    # if the local name already contains “@”, then it should be good
    if [[ "$LOGGED_IN_USER" == *"@"* ]]; then
        echo "$LOGGED_IN_USER"
        return 0
    fi
    # if it ends with the domain without the “@” → we add the @ sign
    if [[ "$LOGGED_IN_USER" == *"$MS_DOMAIN" ]]; then
        CLEAN_USER=${LOGGED_IN_USER%$MS_DOMAIN}
        MS_USER_NAME="${CLEAN_USER}@${MS_DOMAIN}"
    else
        # 3) normal short name → user@domain
        MS_USER_NAME="${LOGGED_IN_USER}@${MS_DOMAIN}"
    fi
}

function msgraph_get_group_data ()
{
    # PURPOSE: Retrieve the user's Graph API group membership
    # RETURN: None
    # EXPECTED: MS_USER_NAME, MS_ACCESS_TOKEN, MSGRAPH_GROUP

    response=$(curl -s -X GET "https://graph.microsoft.com/v1.0/users/$MS_USER_NAME/memberOf" -H "Authorization: Bearer $MS_ACCESS_TOKEN" | jq -r '.value[].displayName')

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

declare MS_ACCESS_TOKEN
declare MS_DOMAIN
declare MSGRAPH_GROUPS=()
declare localGroups=()

# Get Access token
msgraph_getdomain
msgraph_get_access_token
msgraph_upn_sanity_check
msgraph_get_group_data

# Determine if users have RO or RW in their groupnames.  This denotes legacy drive access

for item in ${MSGRAPH_GROUPS[@]}; do
    if [[ "${item:l}" == "_rw" ]] || [[ "{$item:l}" == "_ro" ]]; then
        localGroups+=${item:u}
        echo "Drive Share: "${item:u}
    fi
done

# Write out the info it our plist array
echo "INFO: Plist file: "$JSS_FILE

retval=$(/usr/libexec/plistbuddy -c "print DriveMappings" $JSS_FILE 2>&1)
if [[ "$retval" == *"Does Not Exist"* ]]; then
    echo "INFO: Creating Drive Mapping"
else
    echo "INFO: Updating existing info"
    /usr/libexec/PlistBuddy -c "Delete DriveMappings" $JSS_FILE 2>&1
fi

retval=$(/usr/libexec/plistbuddy -c "add DriveMappings array $adminUser" $JSS_FILE 2>&1)
# Make sure nothing went wrong while creating the array
[[ ! -z $retval ]] && {echo "ERROR: Results of last command: "$retval; exit 1;} 

for item in ${localGroups[@]}; do
    /usr/libexec/PlistBuddy -c "Add DriveMappings: string $item" $JSS_FILE 2>&1
done
exit 0