#!/bin/zsh
#
# by: Scott Kendall
#
# Written: 04/17/2025
# Last updated: 04/17/2025

# Script to populate /Library/Managed Preferences/com.gianteagle.jss file with uses EntraID password info
# 
# 1.0 - Initial code
#
######################################################################################################
#
# Gobal "Common" variables
#
######################################################################################################

SUPPORT_DIR="/Library/Application Support/GiantEagle"
LOG_STAMP=$(echo $(/bin/date +%Y%m%d))
LOG_DIR="${SUPPORT_DIR}/logs"
LOG_FILE="${LOG_DIR}/ViewDeviceInventory.log"
JQ_INSTALL_POLICY="install_jq"
MAC_SERIAL_NUMBER=$(scutil --get HostName)
JSS_FILE="/Library/Managed Preferences/com.gianteagle.jss.plist"

###################################################
#
# App Specfic variables (Feel free to change these)
#
###################################################

JAMF_LOGGED_IN_USER=$3                          # Passed in by JAMF automatically  
CLIENT_ID="$4"
CLIENT_SECRET="$5"
####################################################################################################
#
# Functions
#
####################################################################################################

function create_log_directory ()
{
    # Ensure that the log directory and the log files exist. If they
    # do not then create them and set the permissions.
    #
    # RETURN: None

	# If the log directory doesnt exist - create it and set the permissions
	[[ ! -d "${LOG_DIR}" ]] && /bin/mkdir -p "${LOG_DIR}"
	/bin/chmod 755 "${LOG_DIR}"

	# If the log file does not exist - create it and set the permissions
	[[ ! -f "${LOG_FILE}" ]] && /usr/bin/touch "${LOG_FILE}"
	/bin/chmod 644 "${LOG_FILE}"
}

function logMe () 
{
    # Basic two pronged logging function that will log like this:
    #
    # 20231204 12:00:00: Some message here
    #
    # This function logs both to STDOUT/STDERR and a file
    # The log file is set by the $LOG_FILE variable.
    #
    # RETURN: None
    echo "$(/bin/date '+%Y-%m-%d %H:%M:%S'): ${1}" | tee -a "${LOG_FILE}"
}

function check_support_files ()
{
    [[ $(which jq) == *"not found"* ]] && /usr/local/bin/jamf policy -trigger ${JQ_INSTALL_POLICY}
}

function cleanup_and_exit ()
{
	[[ -f ${JSON_OPTIONS} ]] && /bin/rm -rf ${JSON_OPTIONS}
	[[ -f ${TMP_FILE_STORAGE} ]] && /bin/rm -rf ${TMP_FILE_STORAGE}
    [[ -f ${DIALOG_COMMAND_FILE} ]] && /bin/rm -rf ${DIALOG_COMMAND_FILE}
	exit 0
}

function check_JSS_Connection()
{
    # PURPOSE: Function to check connectivity to the Jamf Pro server
    # RETURN: None
    # EXPECTED: None

    if ! /usr/local/bin/jamf -checkjssconnection -retry 5; then
        logMe "Error: JSS connection not active."
        exit 1
    fi
    logMe "JSS connection active!"
}

function get_JAMF_Server ()
{
    # PURPOSE: Retreive your JAMF server URL from the preferences file
    # RETURN: None
    # EXPECTED: None

    jamfpro_url=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)
    logMe "JAMF Pro server is: $jamfpro_url"
}

function get_JamfPro_Classic_API_Token ()
{
    # PURPOSE: Get a new bearer token for API authentication.  This is used if you are using a JAMF Pro ID & password to obtain the API (Bearer token)
    # PARMS: None
    # RETURN: api_token
    # EXPECTED: CLIENT_ID, CLIENT_SECRET, jamfpro_url

     api_token=$(/usr/bin/curl -X POST --silent -u "${CLIENT_ID}:${CLIENT_SECRET}" "${jamfpro_url}/api/v1/auth/token" | plutil -extract token raw -)

}

function get_JAMF_Access_Token()
{
    # PURPOSE: obtain an OAuth bearer token for API authentication.  This is used if you are using  Client ID & Secret credentials)
    # RETURN: connection stringe (either error code or valid data)
    # PARMS: None
    # EXPECTED: CLIENT_ID, CLIENT_SECRET, jamfpro_url

    returnval=$(curl --silent --location --request POST "${jamfpro_url}/api/oauth/token" \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "client_id=${CLIENT_ID}" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_secret=${CLIENT_SECRET}")
    
    if [[ -z "$returnval" ]]; then
        logMe "Check Jamf URL"
        exit 1
    elif [[ "$returnval" == '{"error":"invalid_client"}' ]]; then
        logMe "Check the API Client credentials and permissions"
        exit 1
    fi
    
    api_token=$(echo "$returnval" | plutil -extract access_token raw -)
}

function get_JAMF_DeviceID ()
{
    # PURPOSE: uses the serial number or hostname to get the device ID (UDID) from the JAMF Pro server. (JAMF pro 11.5.1 or higher)
    # RETURN: the device ID (UDID) for the device in question.
    # PARMS: $1 - search identifier to use (Serial or Hostname)

    [[ "$1" == "Hostname" ]] && type="general.name" || type="hardware.serialNumber"

    jamfID=$(/usr/bin/curl --silent --fail -H "Authorization: Bearer ${api_token}" -H "Accept: application/json" "${jamfpro_url}/api/v1/computers-inventory?filter=${type}==${computer_id}" | /usr/bin/plutil -extract results.0.id raw -)

    # if ID is not found, display a message or something...
    if [[ "$jamfID" == *"Could not extract value"* || "$jamfID" == *"null"* ]]; then
    	logMe "Error: Could not find inventory record for JAMF Device #${computer_id}"
        logMe "Last error message: $jamfID"
        exit 1
    fi
    echo $jamfID
}

function invalidate_JAMF_Token()
{
    # PURPOSE: invalidate the JAMF Token to the server
    # RETURN: None
    # Expected jamfpro_url, ap_token

    returnval=$(/usr/bin/curl -w "%{http_code}" -H "Authorization: Bearer ${api_token}" "${jamfpro_url}/api/v1/auth/invalidate-token" -X POST -s -o /dev/null)

    if [[ $returnval == 204 ]]; then
        logMe "Token successfully invalidated"
    elif [[ $returnval == 401 ]]; then
        logMe "Token already invalid"
    else
        logMe "Unexpected response code: $returnval"
        exit 1  # Or handle it in a different way (e.g., retry or log the error)
    fi    
}

function get_JAMF_InventoryRecord ()
{
    # PURPOSE: Uses the JAMF 
    # RETURN: the device ID (UDID) for the device in question.
    # PARMS: $1 - Section of inventory record to retrieve (GENERAL, DISK_ENCRYPTION, PURCHASING, APPLICATIONS, STORAGE, USER_AND_LOCATION, CONFIGURATION_PROFILES, PRINTERS, 
    #                                                      SERVICES, HARDWARE, LOCAL_USER_ACCOUNTS, CERTIFICATES, ATTACHMENTS, PLUGINS, PACKAGE_RECEIPTS, FONTS, SECURITY, OPERATING_SYSTEM,
    #                                                      LICENSED_SOFTWARE, IBEACONS, SOFTWARE_UPDATES, EXTENSION_ATTRIBUTES, CONTENT_CACHING, GROUP_MEMBERSHIPS)
    retval=$(/usr/bin/curl --silent --fail  -H "Authorization: Bearer ${api_token}" -H "Accept: application/json" "${jamfpro_url}api/v1/computers-inventory/$jamfID?section=$1") # 2>/dev/null)
    echo $retval | tr -d '
'
}

####################################################################################################
#
# Main Script
#
####################################################################################################
declare jamfpro_url
declare api_token
declare jamfID
declare search_type
declare recordGeneral
declare recordExtensions

search_type="Hostname"
computer_id=$MAC_SERIAL_NUMBER

autoload 'is-at-least'

create_log_directory
check_support_files

# Perform JAMF API calls to locate device & retrieve device info

#check_JSS_Connection
get_JAMF_Server
get_JamfPro_Classic_API_Token
jamfID=$(get_JAMF_DeviceID ${search_type})

recordExtensions=$(get_JAMF_InventoryRecord "EXTENSION_ATTRIBUTES")
#logMe "INFO: Inventory Record Info: $recordExtensions"
forceRecon="Yes"
# These variables are specific to JAMF EA fields
newPasswordDate=$(echo $recordExtensions | jq -r '.extensionAttributes[] | select(.name == "Password Change Date") | .values[]' )
logMe "INFO: inTune password date shows: $newPasswordDate"

if [[ -z $newPasswordDate ]]; then
	# Couldn't find the key in the plist file, so we have to rely on the local login password last changed date
    curUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
    passwordAge=$(expr $(expr $(date +%s) - $(dscl . read /Users/${curUser} | grep -A1 passwordLastSetTime | grep real | awk -F'real>|</real' '{print $2}' | awk -F'.' '{print $1}')) / 86400)
	[[ -z ${passwordAge} ]] && passwordAge=0
	newPasswordDate=$(date -j -v-${passwordAge}d +"%Y-%m-%dT12:00:00Z")
    forceRecon="Yes"
    echo "INFO: The PLIST entry is blank.  New Password Date is: ${newPasswordDate} based off of local system password."
    echo "INFO: JAMF inventory update triggered"
fi

retval=$(/usr/libexec/plistbuddy -c "print PasswordLastChanged" $JSS_FILE 2>&1)

# If the password is blank, then set it to the calculated value
[[ -z $retval ]] && retval=$newPasswordDate

# do a quick santity check...convert both dates to epoch time
timestamp_lastretval=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" $retval +%s)
timestamp_lastPass=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" $newPasswordDate +%s)

# and see if the inTune password is greater than the recorded date, if so, then set it to the inTune password
if [[ $timestamp_lastPass -gt $timestamp_lastretval ]]; then
	echo "INFO: inTune password is greater than stored date...using inTune date for reference"
	retval=$newPasswordDate
fi

if [[ $retval == *"Does Not Exist"* ]]; then
    # Entry does not exist so lets create it and populate the userPassword into it
    retval=$(/usr/libexec/plistbuddy -c "add PasswordLastChanged string $newPasswordDate" $JSS_FILE 2>&1)
    echo "INFO: Created new key 'PasswordLastChanged' with contents $newPasswordDate"
    echo "INFO: Results of last command: "$retval

else
    #found the key, so let replace (set) it instead
    retval=$(/usr/libexec/plistbuddy -c "set PasswordLastChanged $newPasswordDate" $JSS_FILE 2>&1)	
    echo "INFO: Replaced key 'PasswordLastChanged' with contents $newPasswordDate"
    echo "INFO: Results of last command: "$retval
fi
[[ "${forceRecon}" == "Yes" ]] && jamf recon
exit 0
