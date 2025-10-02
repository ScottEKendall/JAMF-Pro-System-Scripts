#!/bin/zsh
#
# by: Scott Kendall
#
# Written: 09/08/2025
# Modified: 09/29/25

# Script determines if users is a member of inTune admin group and send results to the user .plist file
# 
# 1.0 - Initial code
# 1.1 - Added option to change local user privleges based on inTune group settings
# 1.2 - Added option to not change predefined local admin accounts
#
######################################################################################################
#
# Gobal "Common" variables
#
######################################################################################################

LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
#MS_USER_NAME=$(dscl . read /Users/$LOGGED_IN_USER | grep "NetworkUser" | awk -F ':' '{print $2}' | xargs)
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
CHANGE_LOCAL="${7:-"no"}"                       # Yes / No - Change local user privleges to reflect admin rights

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
    local url
    url=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)

    # Extract the desired part using Zsh parameter expansion
    tmp=${url#*://}  # Remove the protocol part
    tmp=${tmp%%.*}  # Remove everything after the first dot

    # Append the ".com" part
    MS_DOMAIN="${tmp}.com"

    # Print the result
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
    if [[ "$MS_USER_NAME" == *"@"* ]]; then
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

function change_admin_rights ()
{
    if [[ ${1:l} == "yes" ]]; then
        # Elevate user to admin
        echo "Elevating user to admin"
        /usr/sbin/dseditgroup -o edit -a "$LOGGED_IN_USER" -t user admin
    else
        # Revoke admin rights
        echo "Removing Admin Rights"
        /usr/sbin/dseditgroup -o edit -d "$LOGGED_IN_USER" -t user admin
    fi
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

declare MSGRAPH_GROUPS
declare MS_DOMAIN
declare MS_ACCESS_TOKEN
declare MS_USER_NAME
declare ADMIN_GROUP="GE Corporate Mac Users-Admins"
declare KEEP_ADMIN_ACCOUNTS="localmgr"

check_logged_in_user
# Exit if this is a local admin account that you don't want to have changed
[[ "${LOGGED_IN_USER:l}" == "${KEEP_ADMIN_ACCOUNTS:l}" ]] && exit 0

#MS_USER_NAME=$(dscl . read /Users/${LOGGED_IN_USER} AltSecurityIdentities 2>&1 | grep "PlatformSSO" | awk -F ':' '{ print $NF }')
[[ -z $MS_USER_NAME ]] && MS_USER_NAME=$(/usr/libexec/plistbuddy -c "print 'aadUserId'" "$SUPPORT_DIR/com.microsoft.CompanyPortalMac.usercontext.info")

check_support_files

# Get Access token
msgraph_get_access_token
msgraph_upn_sanity_check

# Read in group data and see if user is part of admin group
msgraph_get_group_data
echo "INFO: Logged-in user (short name): $LOGGED_IN_USER"
echo "INFO: Resolved UPN for Graph: $MS_USER_NAME"
echo "INFO: Plist file: $JSS_FILE"
adminUser="No"
for item in ${MSGRAPH_GROUPS[@]}; do
    if [[ "$item" == "$ADMIN_GROUP" ]]; then
        adminUser="Yes" 
        echo "INFO: Admin Privilege found"
    fi
done
retval=$(/usr/libexec/plistbuddy -c "print EntraAdminRights" $JSS_FILE 2>&1)
if [[ "$retval" == *"Does Not Exist"* ]]; then
    echo "INFO: Creating Admin Field"
    retval=$(/usr/libexec/plistbuddy -c "add EntraAdminRights string $adminUser" $JSS_FILE 2>&1)
else
    [[ ${CHANGE_LOCAL:l} == "yes" ]] && change_admin_rights $adminUser
    echo "INFO: Recording Privilege"
    retval=$(/usr/libexec/plistbuddy -c "set EntraAdminRights $adminUser" $JSS_FILE 2>&1)
    [[ ! -z $retval ]] && echo "ERROR: Results of last command: "$retval
fi
exit 0