#!/bin/zsh
#
# by: Scott Kendall
#
# Written: 09/05/2025
# Last updated: 09/05/2025

# Script to retrieve the inTune profile picture and store that as their login picture
# Original idea by lucaesse https://github.com/lucaesse/Jamf-McNuggets 
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

PHOTO_DIR="/Users/$LOGGED_IN_USER/Library/Application Support"
JSS_FILE="$PHOTO_DIR/com.GiantEagleEntra.plist"
DOMAIN="gianteagle.com"
PERM_PHOTO_DIR="/Library/User Pictures"
TMP_FILE_STORAGE=$(mktemp /var/tmp/EntraPhoto.XXXXX)
/bin/chmod 666 $TMP_FILE_STORAGE

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

function get_ms_access_token ()
{
    # PURPOSE: obtain the MS inTune Graph API Token
    # RETURN: access_token
    # EXPECTED: TENANT_ID, CLIENT_ID, CLIENT_SECRET

    token_response=$(curl -s -X POST "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&scope=https://graph.microsoft.com/.default")

    ms_access_token=$(echo "$token_response" | jq -r '.access_token')

    if [[ "$ms_access_token" == "null" ]] || [[ -z "$ms_access_token" ]]; then
        echo "Failed to acquire access ms_access_token"
        echo "$token_response"
        exit 1
    fi
    echo "INFO: Valid MS Graph Token Acquired"
}

function get_ms_user_photo ()
{
    # PURPOSE: Retrieve the user's Graph API Record
    # RETURN: last_password_change
    # EXPECTED: MS_USER_NAME, ms_access_token

    user_response=$(curl -s -X GET "https://graph.microsoft.com/v1.0/users/${MS_USER_NAME}/photo" -H "Authorization: Bearer $ms_access_token")

    echo "$user_response" | jq -r '."@odata.mediaEtag"'
}

function upn_sanity_check ()
{
    # 1) if the local name already contains “@” we take it like this
    if [[ "$LOGGED_IN_USER" == *"@"* ]]; then
        MS_USER_NAME="$LOGGED_IN_USER"
    else
        # 2) if it ends with the domain without the “@” → we add the @ sign
        if [[ "$LOGGED_IN_USER" == *"$DOMAIN" ]]; then
            CLEAN_USER=${LOGGED_IN_USER%$DOMAIN}
            MS_USER_NAME="${CLEAN_USER}@${DOMAIN}"
        else
            # 3) normal short name → user@domain
            MS_USER_NAME="${LOGGED_IN_USER}@${DOMAIN}"
        fi
    fi
}

function retrieve_ms_user_photo ()
{
    curl -s -L -H "Authorization: Bearer ${ms_access_token}" "https://graph.microsoft.com/v1.0/users/${MS_USER_NAME}/photo/\$value" --output "$PHOTO_FILE"
}

function create_photo_dir ()
{
    # Store retrieved file to perm location  
    PERM_PHOTO_FILE="${PERM_PHOTO_DIR}/${LOGGED_IN_USER}.jpg"
    mkdir -p "$PERM_PHOTO_DIR"
    cp "$PHOTO_FILE" "$PERM_PHOTO_FILE"
    chmod 644 "$PERM_PHOTO_FILE"
}

function set_proflie_picture ()
{
    
    sips -Z 128 "$PERM_PHOTO_FILE" --out "$TMP_FILE_STORAGE" >/dev/null 2>&1 || {
        echo "ERROR: Cannot resize image"; cleanup_and_exit 1
    }

    dscl . -create "/Users/$LOGGED_IN_USER" JPEGPhoto "$(base64 < "$TMP_FILE_STORAGE")" && \
        echo "SUCCESS: JPEGPhoto updated for $LOGGED_IN_USER" || \
        echo "ERROR: Failed to set JPEGPhoto"

    # Optional: keep path attribute for legacy
    dscl . -create "/Users/$LOGGED_IN_USER" picture "$PERM_PHOTO_FILE"

}

function cleanup_and_exit ()
{
	[[ -f ${JSON_OPTIONS} ]] && /bin/rm -rf ${JSON_OPTIONS}
	[[ -f ${TMP_FILE_STORAGE} ]] && /bin/rm -rf ${TMP_FILE_STORAGE}
    [[ -f ${DIALOG_COMMAND_FILE} ]] && /bin/rm -rf ${DIALOG_COMMAND_FILE}
	exit $1
}

####################################################################################################
#
# Main Script
#
####################################################################################################

declare ETAG_FILE

# Get Access token
get_ms_access_token
CURRENT_ETAG=$(get_ms_user_photo)
upn_sanity_check

# Get Logged in User info

echo "INFO: Logged-in user (short name): $LOGGED_IN_USER"
echo "INFO: Resolved UPN for Graph: $MS_USER_NAME"

# Create filenames
SAFE_UPN=$(echo "$MS_USER_NAME" | sed 's/[^a-zA-Z0-9]/_/g')
PHOTO_FILE="$PHOTO_DIR/${SAFE_UPN}.jpg"
ETAG_FILE="$PHOTO_DIR/${SAFE_UPN}.etag"
[[ ! -e "$PHOTO_DIR" ]] && mkdir -p "$PHOTO_DIR"
# Check the current eTAg info
[[ "$CURRENT_ETAG" == "null" ]] && { echo "INFO: No photo in Entra ID"; cleanup_and_exit 0; }

if [[ -f "$ETAG_FILE" ]]; then
    PREV_ETAG=$(cat "$ETAG_FILE")
    [[ "$CURRENT_ETAG" == "$PREV_ETAG" ]] && { echo "INFO: Photo unchanged"; cleanup_and_exit 0; }
fi

# Retrieve photo
retrieve_ms_user_photo
[[ ! -s "$PHOTO_FILE" ]] && { echo "ERROR: Downloaded file empty"; cleanup_and_exit 1; }
create_photo_dir
set_proflie_picture

echo "$CURRENT_ETAG" > "$ETAG_FILE"
echo "SUCCESS: Photo saved to: $PHOTO_FILE"
cleanup_and_exit 0
