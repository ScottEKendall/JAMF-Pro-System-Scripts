#!/bin/zsh

run_for_each_user() {
    local user="$1"
    local userHome
    local platformStatus
    local plist

    # More efficient user home directory retrieval in zsh
    userHome=$(dscl . -read "/Users/$user" NFSHomeDirectory | cut -d' ' -f2)

    # Platform SSO registration check with zsh-optimized parsing
    platformStatus=$(su "$user" -c "app-sso platform -s" 2>/dev/null | awk '/registration/ {gsub(/,/, ""); print $3}')

    # Zsh-specific parameter expansion and conditional checks
    if [[ "$platformStatus" == "true" ]]; then
        # Simplified check for jamfAAD registration
        if [[ -f "$userHome/Library/Preferences/com.jamf.management.jamfAAD.plist" ]] && 
           defaults read "$userHome/Library/Preferences/com.jamf.management.jamfAAD.plist" have_an_Azure_id &>/dev/null; then
            retval+="Running - $userHome"
            return 0
        fi
        retval+="Platform SSO registered but AAD ID not acquired for user home: $userHome"
        return 0
    fi

    # WPJ key check with zsh parameter expansion
    if security dump "$userHome/Library/Keychains/login.keychain-db" | grep -q MS-ORGANIZATION-ACCESS; then
        plist="$userHome/Library/Preferences/com.jamf.management.jamfAAD.plist"
        
        # Zsh file test and plist check
        if [[ ! -f "$plist" ]]; then
            retval+="WPJ Key present, JamfAAD PLIST missing from user home: $userHome"
            return 0
        fi

        # Check AAD ID acquisition
        if defaults read "$plist" have_an_Azure_id &>/dev/null; then
            retval+="Running - $userHome"
            return 0
        fi

        retval+="WPJ Key Present. AAD ID not acquired for user home: $userHome"
        return 0
    fi

    # No registration found
    retval+="Not Registered for user home $userHome"
}

# Main script with zsh-specific argument handling
declare retval
declare user
main() {
    local user="${1:-$USER}"
    run_for_each_user "$user"
    retval+="
"
}
user=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
main "$user"
echo "$retval"
