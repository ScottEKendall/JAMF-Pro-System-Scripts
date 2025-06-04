#!/bin/zsh
# set -x

:<<ABOUT_THIS_SCRIPT
-----------------------------------------------------------------------

	Written by:William Smith
	Partner Program Manager
	Jamf
	bill@talkingmoose.net
	https://gist.github.com/talkingmoose/fe84537a3a6951caa7fcb767d15ee3e6
	
	Originally posted: April 30, 2023

	Updated: August 16, 2023
	Includes support for multiple LAPS admin accounts
	after upgrading to Jamf Pro 10.49.0 or later

	Updated: October 9, 2024
	macOS Sequoia is more sensitive to shell error messages. Corrected
	'2>&1' to '2>/dev/null' in function displayDialog.
	
	Updated Jamf Pro local-admin-password endpoints to v2.

	Purpose: Retrieves the Jamf Pro LAPS password for the current
	computer.
	
	The script assumes a desktop administrator is operating
	the computer. The administrator will open Self Service, authenticate,
	and run the policy with the script.
	
	Instructions:

	1. Create a new script in Jamf Pro with the entirety of
	this script.
	
	2. Create a new ongoing policy in Jamf Pro and add the script.
	
	3. Enable the policy for Self Service. Make the policy available
	only to desktop administrators.

	Except where otherwise noted, this work is licensed under
	http://creativecommons.org/licenses/by/4.0/

	"Some people feel the rain, others just get wet."
	
-----------------------------------------------------------------------
ABOUT_THIS_SCRIPT

trap "exit 1" TERM
export TOP_PID=$$

function displayDialog()	{
	/usr/bin/osascript -e "text returned of (display dialog \"$1\" default answer \"$2\" buttons {\"Cancel\",\"OK\"} default button {\"OK\"} with title \"Retrieve LAPS Password\" with icon POSIX file \"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns\" $3)" 2> /dev/null
}

function evaluateResponse	{
	if [[ $1 == *"User canceled"* ]] || [[ $1 == "false" ]]; then
		kill -s TERM $TOP_PID
	fi
}

function checkResponseCode()	{
	httpErrorCodes="000 No HTTP code received
200 Request successful
201 Request to create or update object successful
400 Bad request
401 Authentication failed
403 Invalid permissions
404 Object/resource not found
409 Conflict
500 Internal server error"
	
	responseCode=${1: -3}
	code=$( /usr/bin/grep "$responseCode" <<< "$httpErrorCodes" )
	
	echo "$code"
}

function apiGET	{
	apiGetResponse=$( /usr/bin/curl \
	--header "Authorization: Bearer $token" \
	--header "$1" \
	--request GET \
	--silent \
	--url "$2" \
	--write-out "%{http_code}" )
	
	codeCheck=$( checkResponseCode "$apiGetResponse" )
	
	if [[ $codeCheck != 2* ]]; then
		quitMessage=$( /usr/bin/osascript -e "display dialog \"Error while attempting to retrieve password:

$codeCheck\" buttons {\"OK\"} default button {\"OK\"} with title \"Retrieve LAPS Password\" with icon POSIX file \"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns\"" )
		kill -s TERM $TOP_PID
	else
		echo "${apiGetResponse%???}"
	fi
}

# prompt for server URL and credentials

while [ "$jamfProURL" = "" ]
do
	foundJamfProURL=$( /usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url )
	
	# strip any trailing slashes
	if [[ $foundJamfProURL == */ ]]; then
		foundJamfProURL=$( /usr/bin/sed 's/.$//' <<< "$foundJamfProURL" )
	fi
	
	jamfProURL=$( displayDialog "Jamf Pro server URL (including port, if needed):" "$foundJamfProURL" "" )
	evaluateResponse "$jamfProURL"
done

echo "Jamf Pro URL: $jamfProURL"

while [ "$jamfProUsername" = "" ]
do
	jamfProUsername=$( displayDialog "Username for
$jamfProURL:" "" "" )
	evaluateResponse "$jamfProUsername"
done

echo "Jamf Pro URL: $jamfProUsername"

while [ "$jamfProPassword" = "" ]
do
	jamfProPassword=$( displayDialog "Password for account \"$jamfProUsername\" at
$jamfProURL:" "" "with hidden answer" )
	evaluateResponse "$jamfProPassword"
done

# request auth token

authTokenResponse=$( /usr/bin/curl \
--request POST \
--silent \
--url "$jamfProURL/api/v1/auth/token" \
--user "$jamfProUsername:$jamfProPassword" \
--write-out "%{http_code}" )

checkResponseCode "$authTokenResponse"

# extract data from result
authToken=${authTokenResponse%???}

# parse auth token
		
token=$( /usr/bin/plutil \
-extract token raw - <<< "$authToken" )
		
# get computer serial number

serialNumber=$( /usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk -F": " /"Serial Number"/'{ print $2 }' )

echo "Computer serial number: $serialNumber"

# get computer Jamf Pro ID
		
computerGeneralXML=$( apiGET "Accept: text/xml" "$jamfProURL/JSSResource/computers/serialnumber/$serialNumber" )

jamfProComputerID=$( /usr/bin/xpath -e "/computer/general/id/text()" 2>/dev/null <<< "$computerGeneralXML" )

echo "Jamf Pro computer ID: $jamfProComputerID"

# get computer management ID

computerGeneralJson=$( apiGET "Accept: application/json" "$jamfProURL/api/v1/computers-inventory/${jamfProComputerID}?section=GENERAL" )
		
computerManagementID=$( /usr/bin/awk -F "\"" '/managementId/{ print $4 }' <<< "$computerGeneralJson" )

echo "Jamf Pro management ID: $computerManagementID"

# get computer local admin username

computerLocalAdminUsernameJson=$( apiGET "Accept: application/json" "$jamfProURL/api/v2/local-admin-password/${computerManagementID}/accounts" )

computerLocalAdminUsername=$( /usr/bin/awk -F "\"" '/username/{ print $4 }' <<< "$computerLocalAdminUsernameJson" )

while [ $( wc -l <<< "$computerLocalAdminUsername" ) -eq 2 ]
do
	theCommand="choose from list every paragraph of \"$computerLocalAdminUsername\" with title \"Retrieve LAPS Password\" with prompt \"This computer has two LAPS accounts.

Choose one...\" multiple selections allowed false empty selection allowed false"
	
	computerLocalAdminUsername=$( /usr/bin/osascript -e "$theCommand" )
	
	evaluateResponse "$computerLocalAdminUsername"
done

echo "LAPS username: $computerLocalAdminUsername"
	
# get computer local admin password

computerLocalAdminPasswordJson=$( apiGET "Accept: application/json" "$jamfProURL/api/v2/local-admin-password/${computerManagementID}/account/${computerLocalAdminUsername}/password" )

computerLocalAdminPassword=$( /usr/bin/awk -F "\"" '/password/{ print $4 }' <<< "$computerLocalAdminPasswordJson" )

# get password rotation time

auditJson=$( apiGET "Accept: application/json" "$jamfProURL/api/v2/local-admin-password/${computerManagementID}/account/${computerLocalAdminUsername}/audit" )
		
lapsRotationTimestamp=$( /usr/bin/grep -A 2 "$computerLocalAdminPassword" <<< "$auditJson" )
lapsExpirationTime=$( /usr/bin/awk -F "\"" '/expirationTime/{ print $4 }' <<< "$lapsRotationTimestamp" )

rotationTimeGMT=$( /bin/date -jf "%FT%T" "$lapsExpirationTime" +"%FT%T"  2> /dev/null )

rotationTimeLocal=$( /bin/date -jf "%FT%T %z" "$rotationTimeGMT +0000" +"%r"  2> /dev/null )

echo "LAPS expiration: $rotationTimeLocal"

/usr/bin/osascript -e "display dialog \"Computer serial number:
$serialNumber

Local admin username:
$computerLocalAdminUsername

Local admin password:
$computerLocalAdminPassword

Password Expires:
$rotationTimeLocal\" buttons {\"OK\"} default button {\"OK\"} with title \"Retrieve LAPS Password\" with icon POSIX file \"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Clock.icns\""

# expire auth token
expireToken=$( /usr/bin/curl \
--header "Authorization: Bearer $token" \
--request POST \
--silent \
--url "$jamfProURL/api/v1/auth/invalidate-token" \
--write-out "%{http_code}" )

if [[ $expireToken == 2* ]]; then
	echo "Token destroyed"
else
	echo "Token was not successfully destroyed"
fi

exit 0
