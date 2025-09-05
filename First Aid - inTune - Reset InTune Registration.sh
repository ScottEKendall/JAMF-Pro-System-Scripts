#!/bin/bash

# Reset InTune/Jamf integration. Removes all files and keychain items.
# Updated by Patrick Gallagher
# Last update 07/11/2025

jamfTrigger="install_mscompanyportal"
loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
AAD_ID=$(su "$loggedInUser" -c "security find-certificate -a -Z | grep -B 9 "MS-ORGANIZATION-ACCESS" | awk '/\"alis\"<blob>=\"/ {print $NF}' | sed 's/  \"alis\"<blob>=\"//;s/.$//'")

if [[ $(pgrep "Company Portal") != "" ]]; then
  echo "Quitting Company Portal"
  killall "Company Portal"
fi


file_Array=(
	"/Applications/Company Portal.app/"
	"/Library/Preferences/com.microsoft.CompanyPortalMac.plist"
  	"/Users/${loggedInUser}/Library/Application Support/com.microsoft.CompanyPortalMac.usercontext.info"
  	"/Users/${loggedInUser}/Library/Application Support/com.microsoft.CompanyPortalMac"
	"/Users/${loggedInUser}/Library/Application Support/com.jamfsoftware.selfservice.mac"
    "/Users/${loggedInUser}/Library/Application Support/Company Portal"
    "/Users/${loggedInUser}/Library/Saved Application State/com.jamfsoftware.selfservice.mac.savedState"
    "/Users/${loggedInUser}/Library/Saved Application State/com.jamf.management.jamfAAD.savedState"
    "/Users/${loggedInUser}/Library/Saved Application State/com.microsoft.CompanyPortalMac.savedState"
    "/Users/${loggedInUser}/Library/Preferences/com.microsoft.CompanyPortalMac"
    "/Users/${loggedInUser}/Library/Preferences/com.jamf.management.jamfAAD.plist"
    "/Users/${loggedInUser}/Library/Cookies/com.microsoft.CompanyPortalMac.binarycookies"
    "/Users/${loggedInUser}/Library/Cookies/com.jamf.management.jamfAAD.binarycookies"
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
    /usr/bin/security delete-generic-password -a $i /Users/${loggedInUser}/Library/Keychains/login.keychain-db > /dev/null 2>&1
  fi
done

# There may be more than one of 'com.microsoft.workplacejoin.devicePatchAttemptTimestamp' so using a while loop to get them all
devicePatchAttemptTimestamp=$(/usr/bin/security find-generic-password -a 'com.microsoft.workplacejoin.devicePatchAttemptTimestamp' | grep svce)
while [[ $devicePatchAttemptTimestamp != "" ]]; do
  /usr/bin/security delete-generic-password -a 'com.microsoft.workplacejoin.devicePatchAttemptTimestamp' /Users/${loggedInUser}/Library/Keychains/login.keychain-db > /dev/null 2>&1
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
    /usr/bin/security delete-generic-password -l $i /Users/${loggedInUser}/Library/Keychains/login.keychain-db > /dev/null 2>&1
  fi
done

certCheck=$(/usr/bin/security find-certificate -a -Z | grep -B 9 "MS-ORGANIZATION-ACCESS" | grep "SHA-1" | awk '{print $3}')
if [[ $certCheck != "" ]]; then
    echo "Deleting $certCheck"
    /usr/bin/security delete-identity -Z "$certCheck" -t /Users/${loggedInUser}/Library/Keychains/login.keychain-db > /dev/null 2>&1
fi

echo "Removing WPJ for Device AAD ID $AAD_ID for $loggedInUser"
if [[ ! -z $AAD_ID ]]; then
    su "$loggedInUser" -c "security delete-identity -c $AAD_ID"
fi
echo "Performing JamfAAD Clean command"
su "$loggedInUser" -c "/usr/local/jamf/bin/jamfAAD clean"

/usr/local/bin/jamf policy -event $jamfTrigger
sleep 10
echo "Launching Registration Process"
su "$loggedInUser" -c "/usr/local/jamf/bin/jamfAAD registerWithIntune"
su "$loggedInUser" -c "/usr/local/jamf/bin/jamfAAD gatherAADInfo"
