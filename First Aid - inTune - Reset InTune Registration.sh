#!/bin/bash

# Reset InTune/Jamf integration. Removes all files and keychain items.
# Updated by Scott Kendall
# Last update 02/03/2026

jamfTrigger="install_mscompanyportal"
LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
AAD_ID=$(su "$LOGGED_IN_USER" -c "security find-certificate -a -Z | grep -B 9 "MS-ORGANIZATION-ACCESS" | awk '/\"alis\"<blob>=\"/ {print $NF}' | sed 's/  \"alis\"<blob>=\"//;s/.$//'")
USER_UID=$(id -u "$LOGGED_IN_USER")

function runAsUser () 
{  
    launchctl asuser "${USER_UID}" sudo -u "${LOGGED_IN_USER}" "$@"

}

if [[ $(pgrep "Company Portal") != "" ]]; then
  echo "Quitting Company Portal"
  killall "Company Portal"
fi

file_Array=(
	"/Applications/Company Portal.app/"
	"/Library/Preferences/com.microsoft.CompanyPortalMac.plist"
  	"/Users/${LOGGED_IN_USER}/Library/Application Support/com.microsoft.CompanyPortalMac.usercontext.info"
  	"/Users/${LOGGED_IN_USER}/Library/Application Support/com.microsoft.CompanyPortalMac"
	  "/Users/${LOGGED_IN_USER}/Library/Application Support/com.jamfsoftware.selfservice.mac"
    "/Users/${LOGGED_IN_USER}/Library/Application Support/Company Portal"
    "/Users/${LOGGED_IN_USER}/Library/Containers/com.microsoft.entrabroker.BrokerApp"
    "/Users/${LOGGED_IN_USER}/Library/Containers/com.microsoft.CompanyPortalMac.Mac-Autofill-Extension"
    "/Users/${LOGGED_IN_USER}/Library/Group Containers/UBF8T346G9.com.microsoft.entrabroker"
    "/Users/${LOGGED_IN_USER}/Library/Group Containers/UBF8T346G9.com.microsoft.oneauth*"
    "/Users/${LOGGED_IN_USER}/Library/Saved Application State/com.jamfsoftware.selfservice.mac.savedState"
    "/Users/${LOGGED_IN_USER}/Library/Saved Application State/com.jamf.management.jamfAAD.savedState"
    "/Users/${LOGGED_IN_USER}/Library/Saved Application State/com.microsoft.CompanyPortalMac.savedState"
    "/Users/${LOGGED_IN_USER}/Library/Preferences/com.microsoft.CompanyPortalMac"
    "/Users/${LOGGED_IN_USER}/Library/Preferences/com.microsoft.CompanyPortal*.plist"
    "/Users/${LOGGED_IN_USER}/Library/Preferences/com.jamf.management.jamfAAD.plist"
    "/Users/${LOGGED_IN_USER}/Library/Cookies/com.microsoft.CompanyPortalMac.binarycookies"
    "/Users/${LOGGED_IN_USER}/Library/Cookies/com.jamf.management.jamfAAD.binarycookies"
)

for i in "${file_Array[@]}"; do
  if [[ -e $i ]]; then
    echo "Deleting file $i"
    rm -rf "$i"
  fi
done

/usr/sbin/pkgutil --forget com.microsoft.CompanyPortalMac

passwordItemAccounts_Array=(
  'com.microsoft.workplacejoin.thumbprint'
  'com.microsoft.workplacejoin.registeredUserPrincipalName'
  'com.microsoft.workplacejoin.deviceName'
  'com.microsoft.workplacejoin.thumbprint'
  'com.microsoft.workplacejoin.deviceOSVersion'
  'com.microsoft.workplacejoin.discoveryHint'
)

for i in "${passwordItemAccounts_Array[@]}"; do
  itemCheck=$(/usr/bin/security find-generic-password -a $i | grep svce) #> /dev/null 2>&1)
  if [[ "$itemCheck" != "" ]]; then
    echo "Deleting Password Item $i"
    /usr/bin/security delete-generic-password -a $i /Users/${LOGGED_IN_USER}/Library/Keychains/login.keychain-db > /dev/null 2>&1
  fi
done

# There may be more than one of 'com.microsoft.workplacejoin.devicePatchAttemptTimestamp' so using a while loop to get them all
devicePatchAttemptTimestamp=$(/usr/bin/security find-generic-password -a 'com.microsoft.workplacejoin.devicePatchAttemptTimestamp' | grep svce)
while [[ $devicePatchAttemptTimestamp != "" ]]; do
  /usr/bin/security delete-generic-password -a 'com.microsoft.workplacejoin.devicePatchAttemptTimestamp' /Users/${LOGGED_IN_USER}/Library/Keychains/login.keychain-db > /dev/null 2>&1
  devicePatchAttemptTimestamp=$(/usr/bin/security find-generic-password -a 'com.microsoft.workplacejoin.devicePatchAttemptTimestamp' | grep svce)
done

identityPref_Array=(
  'com.jamf.management.jamfAAD'
  'com.microsoft.CompanyPortal'
  'com.microsoft.CompanyPortalMac'
  'com.microsoft.CompanyPortal.HockeySDK'
  'enterpriseregistration.windows.net'
  'com.microsoft.adalcache'
  'https://device.login.microsoftonline.com'
  'https://device.login.microsoftonline.com/'
  'https://enterpriseregistration.windows.net'
  'https://enterpriseregistration.windows.net/'
)

for i in "${identityPref_Array[@]}"; do
  itemCheck=$(/usr/bin/security find-generic-password -l $i | grep svce)
  if [[ $itemCheck != "" ]]; then
    echo "Deleting Identity Preference $i"
    /usr/bin/security delete-generic-password -l $i /Users/${LOGGED_IN_USER}/Library/Keychains/login.keychain-db > /dev/null 2>&1
  fi
done

certCheck=$(/usr/bin/security find-certificate -a -Z | grep -B 9 "MS-ORGANIZATION-ACCESS" | grep "SHA-1" | awk '{print $3}')
if [[ $certCheck != "" ]]; then
    echo "Deleting $certCheck"
    /usr/bin/security delete-identity -Z "$certCheck" -t /Users/${LOGGED_IN_USER}/Library/Keychains/login.keychain-db > /dev/null 2>&1
fi

echo "Removing WPJ for Device AAD ID $AAD_ID for $LOGGED_IN_USER"
if [[ ! -z $AAD_ID ]]; then
    runAsUser "security delete-identity -c $AAD_ID"
fi
echo "Performing JamfAAD Clean command"
runAsUser /usr/local/jamf/bin/jamfAAD clean

/usr/local/bin/jamf policy -event $jamfTrigger
sleep 10
echo "Launching Registration Process"
runAsUser /usr/local/jamf/bin/jamfAAD registerWithIntune
runAsUser /usr/local/jamf/bin/jamfAAD gatherAADInfo
sudo jamf recon
