#!/bin/zsh

##  This script will attempt to audit all of the settings based on the installed profile.

##  This script is provided as-is and should be fully tested on a system that is not in a production environment.

###################  Variables  ###################

pwpolicy_file=""

###################  COMMANDS START BELOW THIS LINE  ###################

## Must be run as root
if [[ $EUID -ne 0 ]]; then
    /bin/echo "This script must be run as root"
    exit 1
fi

# path to PlistBuddy
plb="/usr/libexec/PlistBuddy"

# get the currently logged in user
CURRENT_USER=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

# get system architecture
arch=$(/usr/bin/arch)

# configure colors for text
RED='[31m'
STD='[39m'
GREEN='[32m'
YELLOW='[33m'

audit_plist="/Library/Preferences/org.giant-eagle.audit.plist"
audit_log="/Library/Logs/giant-eagle_baseline.log"

# pause function
pause(){
vared -p "Press [Enter] key to continue..." -c fackEnterKey
}

ask() {
    # if fix flag is passed, assume YES for everything
    if [[ $fix ]]; then
        return 0
    fi

    while true; do

        if [ "${2:-}" = "Y" ]; then
            prompt="Y/n"
            default=Y
        elif [ "${2:-}" = "N" ]; then
            prompt="y/N"
            default=N
        else
            prompt="y/n"
            default=
        fi

        # Ask the question - use /dev/tty in case stdin is redirected from somewhere else
        printf "${YELLOW} $1 [$prompt] ${STD}"
        read REPLY

        # Default?
        if [ -z "$REPLY" ]; then
            REPLY=$default
        fi

        # Check if the reply is valid
        case "$REPLY" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac

    done
}

# function to display menus
show_menus() {
    lastComplianceScan=$(defaults read /Library/Preferences/org.giant-eagle.audit.plist lastComplianceCheck)

    if [[ $lastComplianceScan == "" ]];then
        lastComplianceScan="No scans have been run"
    fi

    /usr/bin/clear
    /bin/echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    /bin/echo "        M A I N - M E N U"
    /bin/echo "  macOS Security Compliance Tool"
    /bin/echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    /bin/echo "Last compliance scan: $lastComplianceScan
"
    /bin/echo "1. View Last Compliance Report"
    /bin/echo "2. Run New Compliance Scan"
    /bin/echo "3. Run Commands to remediate non-compliant settings"
    /bin/echo "4. Exit"
}

# function to read options
read_options(){
    local choice
    vared -p "Enter choice [ 1 - 4 ] " -c choice
    case $choice in
        1) view_report ;;
        2) run_scan ;;
        3) run_fix ;;
        4) exit 0;;
        *) echo -e "${RED}Error: please choose an option 1-4...${STD}" && sleep 1
    esac
}

# function to reset and remove plist file.  Used to clear out any previous findings
reset_plist(){
    echo "Clearing results from /Library/Preferences/org.giant-eagle.audit.plist"
    defaults delete /Library/Preferences/org.giant-eagle.audit.plist
}

# Generate the Compliant and Non-Compliant counts. Returns: Array (Compliant, Non-Compliant)
compliance_count(){
    compliant=0
    non_compliant=0

    results=$(/usr/libexec/PlistBuddy -c "Print" /Library/Preferences/org.giant-eagle.audit.plist)

    while IFS= read -r line; do
        if [[ "$line" =~ "finding = false" ]]; then
            compliant=$((compliant+1))
        fi
        if [[ "$line" =~ "finding = true" ]]; then
            non_compliant=$((non_compliant+1))
        fi
    done <<< "$results"

    # Enable output of just the compliant or non-compliant numbers.
    if [[ $1 = "compliant" ]]
    then
        /bin/echo $compliant
    elif [[ $1 = "non-compliant" ]]
    then
        /bin/echo $non_compliant
    else # no matching args output the array
        array=($compliant $non_compliant)
        /bin/echo ${array[@]}
    fi
}

exempt_count(){
    exempt=0

    if [[ -e "/Library/Managed Preferences/org.giant-eagle.audit.plist" ]];then
        mscp_prefs="/Library/Managed Preferences/org.giant-eagle.audit.plist"
    else
        mscp_prefs="/Library/Preferences/org.giant-eagle.audit.plist"
    fi

    results=$(/usr/libexec/PlistBuddy -c "Print" "$mscp_prefs")

    while IFS= read -r line; do
        if [[ "$line" =~ "exempt = true" ]]; then
            exempt=$((exempt+1))
        fi
    done <<< "$results"

    /bin/echo $exempt
}


generate_report(){
    count=($(compliance_count))
    exempt_rules=$(exempt_count)
    compliant=${count[1]}
    non_compliant=${count[2]}

    total=$((non_compliant + compliant - exempt_rules))
    percentage=$(printf %.2f $(( compliant * 100. / total )) )
    /bin/echo
    echo "Number of tests passed: ${GREEN}$compliant${STD}"
    echo "Number of test FAILED: ${RED}$non_compliant${STD}"
    echo "Number of exempt rules: ${YELLOW}$exempt_rules${STD}"
    echo "You are ${YELLOW}$percentage%${STD} percent compliant!"
    pause
}

view_report(){

    if [[ $lastComplianceScan == "No scans have been run" ]];then
        /bin/echo "no report to run, please run new scan"
        pause
    else
        generate_report
    fi
}

# Designed for use with MDM - single unformatted output of the Compliance Report
generate_stats(){
    count=($(compliance_count))
    compliant=${count[1]}
    non_compliant=${count[2]}

    total=$((non_compliant + compliant))
    percentage=$(printf %.2f $(( compliant * 100. / total )) )
    /bin/echo "PASSED: $compliant FAILED: $non_compliant, $percentage percent compliant!"
}

run_scan(){
# append to existing logfile
if [[ $(/usr/bin/tail -n 1 "$audit_log" 2>/dev/null) = *"Remediation complete" ]]; then
 	/bin/echo "$(date -u) Beginning giant-eagle baseline scan" >> "$audit_log"
else
 	/bin/echo "$(date -u) Beginning giant-eagle baseline scan" > "$audit_log"
fi

# run mcxrefresh
/usr/bin/mcxrefresh -u $CURR_USER_UID

# write timestamp of last compliance check
/usr/bin/defaults write "$audit_plist" lastComplianceCheck "$(date)"
    
#####----- Rule: audit_acls_files_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_acls_files_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/ls -le $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}') | /usr/bin/awk '{print $1}' | /usr/bin/grep -c ":"
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_acls_files_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_acls_files_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) audit_acls_files_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_acls_files_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_acls_files_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_acls_files_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) audit_acls_files_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_acls_files_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_acls_files_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_acls_folders_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_acls_folders_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/ls -lde $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}') | /usr/bin/awk '{print $1}' | /usr/bin/grep -c ":"
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_acls_folders_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_acls_folders_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) audit_acls_folders_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_acls_folders_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_acls_folders_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_acls_folders_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) audit_acls_folders_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_acls_folders_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_acls_folders_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_auditd_enabled -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-12, AU-12(1), AU-12(3)
# * AU-14(1)
# * AU-3, AU-3(1)
# * AU-8
# * CM-5(1)
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_auditd_enabled ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/launchctl list | /usr/bin/grep -c com.apple.auditd
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_auditd_enabled'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_auditd_enabled'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) audit_auditd_enabled passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_auditd_enabled passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_auditd_enabled failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_auditd_enabled failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) audit_auditd_enabled failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_auditd_enabled failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_auditd_enabled does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add finding -bool NO
fi
    
#####----- Rule: audit_control_acls_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_control_acls_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/ls -le /etc/security/audit_control | /usr/bin/awk '{print $1}' | /usr/bin/grep -c ":"
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_acls_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_acls_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) audit_control_acls_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_control_acls_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_control_acls_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_control_acls_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) audit_control_acls_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_control_acls_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_control_acls_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_control_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_control_group_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/ls -dn /etc/security/audit_control | /usr/bin/awk '{print $4}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_group_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_group_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) audit_control_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_control_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_control_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_control_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) audit_control_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_control_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_control_group_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_control_mode_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_control_mode_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/ls -l /etc/security/audit_control | awk '!/-r--r-----|current|total/{print $1}' | /usr/bin/wc -l | /usr/bin/xargs
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_mode_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_mode_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) audit_control_mode_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_control_mode_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_control_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_control_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) audit_control_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_control_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_control_mode_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_control_owner_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_control_owner_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/ls -dn /etc/security/audit_control | /usr/bin/awk '{print $3}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_owner_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_owner_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) audit_control_owner_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_control_owner_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_control_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_control_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) audit_control_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_control_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_control_owner_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_files_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_files_group_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/ls -n $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}') | /usr/bin/awk '{s+=$4} END {print s}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_files_group_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_files_group_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) audit_files_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_files_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_files_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_files_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) audit_files_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_files_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_files_group_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_files_mode_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_files_mode_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/ls -l $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}') | /usr/bin/awk '!/-r--r-----|current|total/{print $1}' | /usr/bin/wc -l | /usr/bin/tr -d ' '
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_files_mode_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_files_mode_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) audit_files_mode_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_files_mode_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_files_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_files_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) audit_files_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_files_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_files_mode_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_files_owner_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_files_owner_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/ls -n $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}') | /usr/bin/awk '{s+=$3} END {print s}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_files_owner_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_files_owner_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) audit_files_owner_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_files_owner_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_files_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_files_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) audit_files_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_files_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_files_owner_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_flags_aa_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * CM-5(1)
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_flags_aa_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '
' | /usr/bin/grep -Ec 'aa'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_aa_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_aa_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) audit_flags_aa_configure passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_flags_aa_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_flags_aa_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_flags_aa_configure failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_aa_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_aa_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) audit_flags_aa_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_aa_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_aa_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_flags_aa_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_flags_aa_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_flags_ad_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12), AC-2(4)
# * AC-6(9)
# * AU-12
# * AU-2
# * CM-5(1)
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_flags_ad_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '
' | /usr/bin/grep -Ec 'ad'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_ad_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_ad_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) audit_flags_ad_configure passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_flags_ad_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_flags_ad_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_flags_ad_configure failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_ad_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_ad_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) audit_flags_ad_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_ad_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_ad_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_flags_ad_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_flags_ad_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_flags_ex_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * CM-5(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_flags_ex_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '
' | /usr/bin/grep -Ec '\-ex'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_ex_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_ex_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) audit_flags_ex_configure passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_flags_ex_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_flags_ex_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_flags_ex_configure failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_ex_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_ex_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) audit_flags_ex_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_ex_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_ex_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_flags_ex_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_flags_ex_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_flags_fm_failed_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_flags_fm_failed_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '
' | /usr/bin/grep -Ec '\-fm'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_fm_failed_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_fm_failed_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) audit_flags_fm_failed_configure passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_flags_fm_failed_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_flags_fm_failed_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_flags_fm_failed_configure failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_fm_failed_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_fm_failed_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) audit_flags_fm_failed_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_fm_failed_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_fm_failed_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_flags_fm_failed_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_flags_fm_failed_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_flags_fr_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_flags_fr_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '
' | /usr/bin/grep -Ec '\-fr'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_fr_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_fr_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) audit_flags_fr_configure passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_flags_fr_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_flags_fr_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_flags_fr_configure failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_fr_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_fr_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) audit_flags_fr_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_fr_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_fr_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_flags_fr_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_flags_fr_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_flags_fw_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_flags_fw_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '
' | /usr/bin/grep -Ec '\-fw'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_fw_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_fw_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) audit_flags_fw_configure passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_flags_fw_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_flags_fw_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_flags_fw_configure failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_fw_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_fw_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) audit_flags_fw_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_fw_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_fw_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_flags_fw_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_flags_fw_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_flags_lo_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17(1)
# * AC-2(12)
# * AU-12
# * AU-2
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_flags_lo_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '
' | /usr/bin/grep -Ec '^lo'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_lo_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_lo_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) audit_flags_lo_configure passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_flags_lo_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_flags_lo_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_flags_lo_configure failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_lo_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_lo_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) audit_flags_lo_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_flags_lo_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_flags_lo_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_flags_lo_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_flags_lo_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_folder_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_folder_group_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/ls -dn $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}') | /usr/bin/awk '{print $4}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_folder_group_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_folder_group_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) audit_folder_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_folder_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_folder_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_folder_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) audit_folder_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_folder_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_folder_group_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_folder_owner_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_folder_owner_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/ls -dn $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}') | /usr/bin/awk '{print $3}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_folder_owner_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_folder_owner_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) audit_folder_owner_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_folder_owner_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_folder_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_folder_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) audit_folder_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_folder_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_folder_owner_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_folders_mode_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_folders_mode_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/stat -f %A $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}')
)
    # expected result {'integer': 700}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_folders_mode_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_folders_mode_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "700" ]]; then
        /bin/echo "$(date -u) audit_folders_mode_configure passed (Result: $result_value, Expected: "{'integer': 700}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_folders_mode_configure passed (Result: $result_value, Expected: "{'integer': 700}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_folders_mode_configure failed (Result: $result_value, Expected: "{'integer': 700}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_folders_mode_configure failed (Result: $result_value, Expected: "{'integer': 700}")"
        else
            /bin/echo "$(date -u) audit_folders_mode_configure failed (Result: $result_value, Expected: "{'integer': 700}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_folders_mode_configure failed (Result: $result_value, Expected: "{'integer': 700}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_folders_mode_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add finding -bool NO
fi
    
#####----- Rule: audit_retention_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-11
# * AU-4
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: audit_retention_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/awk -F: '/expire-after/{print $2}' /etc/security/audit_control
)
    # expected result {'string': '60d or 1g'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_retention_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_retention_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "60d OR 1G" ]]; then
        /bin/echo "$(date -u) audit_retention_configure passed (Result: $result_value, Expected: "{'string': '60d or 1g'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - audit_retention_configure passed (Result: $result_value, Expected: "{'string': '60d or 1g'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) audit_retention_configure failed (Result: $result_value, Expected: "{'string': '60d or 1g'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_retention_configure failed (Result: $result_value, Expected: "{'string': '60d or 1g'}")"
        else
            /bin/echo "$(date -u) audit_retention_configure failed (Result: $result_value, Expected: "{'string': '60d or 1g'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - audit_retention_configure failed (Result: $result_value, Expected: "{'string': '60d or 1g'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) audit_retention_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add finding -bool NO
fi
    
#####----- Rule: icloud_sync_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: icloud_sync_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCloudDesktopAndDocuments').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('icloud_sync_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('icloud_sync_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "false" ]]; then
        /bin/echo "$(date -u) icloud_sync_disable passed (Result: $result_value, Expected: "{'string': 'false'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - icloud_sync_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) icloud_sync_disable failed (Result: $result_value, Expected: "{'string': 'false'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - icloud_sync_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            /bin/echo "$(date -u) icloud_sync_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - icloud_sync_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) icloud_sync_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add finding -bool NO
fi
    
#####----- Rule: os_airdrop_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * AC-3
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_airdrop_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowAirDrop').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_airdrop_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_airdrop_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "false" ]]; then
        /bin/echo "$(date -u) os_airdrop_disable passed (Result: $result_value, Expected: "{'string': 'false'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_airdrop_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_airdrop_disable failed (Result: $result_value, Expected: "{'string': 'false'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_airdrop_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            /bin/echo "$(date -u) os_airdrop_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_airdrop_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_airdrop_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add finding -bool NO
fi
    
#####----- Rule: os_authenticated_root_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-3
# * CM-5
# * MA-4(1)
# * SC-34
# * SI-7, SI-7(6)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_authenticated_root_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/csrutil authenticated-root | /usr/bin/grep -c 'enabled'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_authenticated_root_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_authenticated_root_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) os_authenticated_root_enable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_authenticated_root_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_authenticated_root_enable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_authenticated_root_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) os_authenticated_root_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_authenticated_root_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_authenticated_root_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add finding -bool NO
fi
    
#####----- Rule: os_bonjour_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_bonjour_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.mDNSResponder')\
.objectForKey('NoMulticastAdvertisements').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_bonjour_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_bonjour_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) os_bonjour_disable passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_bonjour_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_bonjour_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_bonjour_disable failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_bonjour_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_bonjour_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) os_bonjour_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_bonjour_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_bonjour_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_bonjour_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_bonjour_disable -dict-add finding -bool NO
fi
    
#####----- Rule: os_config_data_install_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-2(5)
# * SI-3
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_config_data_install_enforce ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SoftwareUpdate')\
.objectForKey('ConfigDataInstall').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_config_data_install_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_config_data_install_enforce'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) os_config_data_install_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_config_data_install_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_config_data_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_config_data_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) os_config_data_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_config_data_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_config_data_install_enforce does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add finding -bool NO
fi
    
#####----- Rule: os_efi_integrity_validated -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch="i386"
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_efi_integrity_validated ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(if /usr/sbin/ioreg -w 0 -c AppleSEPManager | /usr/bin/grep -q AppleSEPManager; then echo "1"; else /usr/libexec/firmwarecheckers/eficheck/eficheck --integrity-check | /usr/bin/grep -c "No changes detected"; fi
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_efi_integrity_validated'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_efi_integrity_validated'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) os_efi_integrity_validated passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_efi_integrity_validated -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_efi_integrity_validated passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_efi_integrity_validated failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_efi_integrity_validated -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_efi_integrity_validated failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) os_efi_integrity_validated failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_efi_integrity_validated -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_efi_integrity_validated failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_efi_integrity_validated does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_efi_integrity_validated -dict-add finding -bool NO
fi
    
#####----- Rule: os_firewall_log_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-12
# * SC-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_firewall_log_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let pref1 = $.NSUserDefaults.alloc.initWithSuiteName('com.apple.security.firewall')\
  .objectForKey('EnableLogging').js
  let pref2 = $.NSUserDefaults.alloc.initWithSuiteName('com.apple.security.firewall')\
  .objectForKey('LoggingOption').js
  if ( pref1 == true && pref2 == "detail" ){
    return("true")
  } else {
    return("false")
  }
}
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_firewall_log_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_firewall_log_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) os_firewall_log_enable passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_firewall_log_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_firewall_log_enable failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_firewall_log_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) os_firewall_log_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_firewall_log_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_firewall_log_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add finding -bool NO
fi
    
#####----- Rule: os_gatekeeper_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-14
# * CM-5
# * SI-3
# * SI-7(1), SI-7(15)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_gatekeeper_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/sbin/spctl --status | /usr/bin/grep -c "assessments enabled"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_gatekeeper_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_gatekeeper_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) os_gatekeeper_enable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_gatekeeper_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_gatekeeper_enable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_gatekeeper_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) os_gatekeeper_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_gatekeeper_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_gatekeeper_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool NO
fi
    
#####----- Rule: os_guest_folder_removed -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_guest_folder_removed ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/ls /Users/ | /usr/bin/grep -c "Guest"
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_guest_folder_removed'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_guest_folder_removed'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) os_guest_folder_removed passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_guest_folder_removed -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_guest_folder_removed passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_guest_folder_removed failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_guest_folder_removed -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_guest_folder_removed failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) os_guest_folder_removed failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_guest_folder_removed -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_guest_folder_removed failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_guest_folder_removed does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_guest_folder_removed -dict-add finding -bool NO
fi
    
#####----- Rule: os_hibernate_mode_destroyfvkeyonstandby_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_hibernate_mode_destroyfvkeyonstandby_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.MCX')\
.objectForKey('DestroyFVKeyOnStandby').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_hibernate_mode_destroyfvkeyonstandby_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_hibernate_mode_destroyfvkeyonstandby_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) os_hibernate_mode_destroyfvkeyonstandby_enable passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_hibernate_mode_destroyfvkeyonstandby_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_hibernate_mode_destroyfvkeyonstandby_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_hibernate_mode_destroyfvkeyonstandby_enable failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_hibernate_mode_destroyfvkeyonstandby_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_hibernate_mode_destroyfvkeyonstandby_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) os_hibernate_mode_destroyfvkeyonstandby_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_hibernate_mode_destroyfvkeyonstandby_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_hibernate_mode_destroyfvkeyonstandby_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_hibernate_mode_destroyfvkeyonstandby_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_hibernate_mode_destroyfvkeyonstandby_enable -dict-add finding -bool NO
fi
    
#####----- Rule: os_hibernate_mode_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_hibernate_mode_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(error_count=0
if /usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice 2>&1 | /usr/bin/grep -q "MacBook"; then
  if [[ "$(/usr/sbin/sysctl -n machdep.cpu.brand_string)" =~ "Intel" ]]; then
      hibernateStandbyLowValue=$(/usr/bin/pmset -g | /usr/bin/grep standbydelaylow 2>&1 | /usr/bin/awk '{print $2}')
      hibernateStandbyHighValue=$(/usr/bin/pmset -g | /usr/bin/grep standbydelayhigh 2>&1 | /usr/bin/awk '{print $2}')
      hibernateStandbyThreshValue=$(/usr/bin/pmset -g | /usr/bin/grep highstandbythreshold 2>&1 | /usr/bin/awk '{print $2}')
      hibernateMode=$(/usr/bin/pmset -b -g | /usr/bin/grep hibernatemode 2>&1 | /usr/bin/awk '{print $2}')
      
      if [[ "$hibernateStandbyLowValue" == "" ]] || [[ "$hibernateStandbyLowValue" -gt 600 ]]; then
          ((error_count++))
      fi
      if [[ "$hibernateStandbyHighValue" == "" ]] || [[ "$hibernateStandbyHighValue" -gt 600 ]]; then
          ((error_count++))
      fi
      if [[ "$hibernateStandbyThreshValue" == "" ]] || [[ "$hibernateStandbyThreshValue" -lt 90 ]]; then
          ((error_count++))
      fi
  else
      if [[ "$(/usr/bin/pmset -g | /usr/bin/grep standbydelay 2>&1 | /usr/bin/awk '{print $2}')" -gt 900 ]]; then
          ((error_count++))
      fi
  fi
fi
echo "$error_count"
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_hibernate_mode_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_hibernate_mode_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) os_hibernate_mode_enable passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_hibernate_mode_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_hibernate_mode_enable passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_hibernate_mode_enable failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_hibernate_mode_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_hibernate_mode_enable failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) os_hibernate_mode_enable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_hibernate_mode_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_hibernate_mode_enable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_hibernate_mode_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_hibernate_mode_enable -dict-add finding -bool NO
fi
    
#####----- Rule: os_home_folders_secure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-6
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_home_folders_secure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/find /System/Volumes/Data/Users -mindepth 1 -maxdepth 1 -type d -perm -1 | /usr/bin/grep -v "Shared" | /usr/bin/grep -v "Guest" | /usr/bin/wc -l | /usr/bin/xargs
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_home_folders_secure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_home_folders_secure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) os_home_folders_secure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_home_folders_secure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_home_folders_secure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_home_folders_secure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) os_home_folders_secure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_home_folders_secure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_home_folders_secure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add finding -bool NO
fi
    
#####----- Rule: os_httpd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_httpd_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"org.apache.httpd" => true'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_httpd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_httpd_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) os_httpd_disable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_httpd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_httpd_disable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_httpd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) os_httpd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_httpd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_httpd_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add finding -bool NO
fi
    
#####----- Rule: os_install_log_retention_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-11
# * AU-4
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_install_log_retention_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/sbin/aslmanager -dd 2>&1 | /usr/bin/awk '/\/var\/log\/install.log/ {count++} /Processing module com.apple.install/,/Finished/ { for (i=1;i<=NR;i++) { if ($i == "TTL" && $(i+2) >= 365) { ttl="True" }; if ($i == "MAX") {max="True"}}} END{if (count > 1) { print "Multiple config files for /var/log/install, manually remove"} else if (ttl != "True") { print "TTL not configured" } else if (max == "True") { print "Max Size is configured, must be removed" } else { print "Yes" }}'
)
    # expected result {'string': 'yes'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_install_log_retention_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_install_log_retention_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "Yes" ]]; then
        /bin/echo "$(date -u) os_install_log_retention_configure passed (Result: $result_value, Expected: "{'string': 'yes'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_install_log_retention_configure passed (Result: $result_value, Expected: "{'string': 'yes'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_install_log_retention_configure failed (Result: $result_value, Expected: "{'string': 'yes'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_install_log_retention_configure failed (Result: $result_value, Expected: "{'string': 'yes'}")"
        else
            /bin/echo "$(date -u) os_install_log_retention_configure failed (Result: $result_value, Expected: "{'string': 'yes'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_install_log_retention_configure failed (Result: $result_value, Expected: "{'string': 'yes'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_install_log_retention_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add finding -bool NO
fi
    
#####----- Rule: os_mobile_file_integrity_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_mobile_file_integrity_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/sbin/nvram -p | /usr/bin/grep -c "amfi_get_out_of_my_way=1"
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_mobile_file_integrity_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_mobile_file_integrity_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) os_mobile_file_integrity_enable passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_mobile_file_integrity_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_mobile_file_integrity_enable passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_mobile_file_integrity_enable failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_mobile_file_integrity_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_mobile_file_integrity_enable failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) os_mobile_file_integrity_enable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_mobile_file_integrity_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_mobile_file_integrity_enable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_mobile_file_integrity_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_mobile_file_integrity_enable -dict-add finding -bool NO
fi
    
#####----- Rule: os_nfsd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_nfsd_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"com.apple.nfsd" => true'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_nfsd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_nfsd_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) os_nfsd_disable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_nfsd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_nfsd_disable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_nfsd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) os_nfsd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_nfsd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_nfsd_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add finding -bool NO
fi
    
#####----- Rule: os_password_hint_remove -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-6
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_password_hint_remove ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/dscl . -list /Users hint | /usr/bin/awk '{print $2}' | /usr/bin/wc -l | /usr/bin/xargs
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_password_hint_remove'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_password_hint_remove'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) os_password_hint_remove passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_password_hint_remove passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_password_hint_remove failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_password_hint_remove failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) os_password_hint_remove failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_password_hint_remove failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_password_hint_remove does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add finding -bool NO
fi
    
#####----- Rule: os_root_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(5)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_root_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/dscl . -read /Users/root UserShell 2>&1 | /usr/bin/grep -c "/usr/bin/false"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_root_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_root_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) os_root_disable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_root_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_root_disable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_root_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) os_root_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_root_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_root_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool NO
fi
    
#####----- Rule: os_safari_open_safe_downloads_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_safari_open_safe_downloads_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/profiles -P -o stdout | /usr/bin/grep -c 'AutoOpenSafeDownloads = 0' | /usr/bin/awk '{ if ($1 >= 1) {print "1"} else {print "0"}}'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_safari_open_safe_downloads_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_safari_open_safe_downloads_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) os_safari_open_safe_downloads_disable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_safari_open_safe_downloads_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_safari_open_safe_downloads_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_safari_open_safe_downloads_disable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_safari_open_safe_downloads_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_safari_open_safe_downloads_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) os_safari_open_safe_downloads_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_safari_open_safe_downloads_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_safari_open_safe_downloads_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_safari_open_safe_downloads_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_safari_open_safe_downloads_disable -dict-add finding -bool NO
fi
    
#####----- Rule: os_show_filename_extensions_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_show_filename_extensions_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults read .GlobalPreferences AppleShowAllExtensions 2>/dev/null
)
    # expected result {'boolean': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_show_filename_extensions_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_show_filename_extensions_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) os_show_filename_extensions_enable passed (Result: $result_value, Expected: "{'boolean': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_show_filename_extensions_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_show_filename_extensions_enable passed (Result: $result_value, Expected: "{'boolean': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_show_filename_extensions_enable failed (Result: $result_value, Expected: "{'boolean': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_show_filename_extensions_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_show_filename_extensions_enable failed (Result: $result_value, Expected: "{'boolean': 1}")"
        else
            /bin/echo "$(date -u) os_show_filename_extensions_enable failed (Result: $result_value, Expected: "{'boolean': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_show_filename_extensions_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_show_filename_extensions_enable failed (Result: $result_value, Expected: "{'boolean': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_show_filename_extensions_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_show_filename_extensions_enable -dict-add finding -bool NO
fi
    
#####----- Rule: os_sip_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-3
# * AU-9, AU-9(3)
# * CM-5, CM-5(6)
# * SC-4
# * SI-2
# * SI-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_sip_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/csrutil status | /usr/bin/grep -c 'System Integrity Protection status: enabled.'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_sip_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_sip_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) os_sip_enable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_sip_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_sip_enable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_sip_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) os_sip_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_sip_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_sip_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add finding -bool NO
fi
    
#####----- Rule: os_software_update_deferral -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_software_update_deferral ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let timeout = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('enforcedSoftwareUpdateDelay')) || 0
  if ( timeout <= 90 ) {
    return("true")
  } else {
    return("false")
  }
}
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_software_update_deferral'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_software_update_deferral'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) os_software_update_deferral passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_software_update_deferral -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_software_update_deferral passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_software_update_deferral failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_software_update_deferral -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_software_update_deferral failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) os_software_update_deferral failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_software_update_deferral -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_software_update_deferral failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_software_update_deferral does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_software_update_deferral -dict-add finding -bool NO
fi
    
#####----- Rule: os_sudo_timeout_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_sudo_timeout_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/sudo /usr/bin/sudo -V | /usr/bin/grep -c "Authentication timestamp timeout: 0.0 minutes"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_sudo_timeout_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_sudo_timeout_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) os_sudo_timeout_configure passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_sudo_timeout_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_sudo_timeout_configure failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_sudo_timeout_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) os_sudo_timeout_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_sudo_timeout_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_sudo_timeout_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add finding -bool NO
fi
    
#####----- Rule: os_sudoers_timestamp_type_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-5(1)
# * IA-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_sudoers_timestamp_type_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/sudo /usr/bin/sudo -V | /usr/bin/awk -F": " '/Type of authentication timestamp record/{print $2}'
)
    # expected result {'string': 'tty'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_sudoers_timestamp_type_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_sudoers_timestamp_type_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "tty" ]]; then
        /bin/echo "$(date -u) os_sudoers_timestamp_type_configure passed (Result: $result_value, Expected: "{'string': 'tty'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_sudoers_timestamp_type_configure passed (Result: $result_value, Expected: "{'string': 'tty'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_sudoers_timestamp_type_configure failed (Result: $result_value, Expected: "{'string': 'tty'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_sudoers_timestamp_type_configure failed (Result: $result_value, Expected: "{'string': 'tty'}")"
        else
            /bin/echo "$(date -u) os_sudoers_timestamp_type_configure failed (Result: $result_value, Expected: "{'string': 'tty'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_sudoers_timestamp_type_configure failed (Result: $result_value, Expected: "{'string': 'tty'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_sudoers_timestamp_type_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add finding -bool NO
fi
    
#####----- Rule: os_system_wide_applications_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_system_wide_applications_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/find /Applications -iname "*\.app" -type d -perm -2 -ls | /usr/bin/wc -l | /usr/bin/xargs
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_system_wide_applications_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_system_wide_applications_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) os_system_wide_applications_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_system_wide_applications_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_system_wide_applications_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_system_wide_applications_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_system_wide_applications_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_system_wide_applications_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) os_system_wide_applications_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_system_wide_applications_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_system_wide_applications_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_system_wide_applications_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_system_wide_applications_configure -dict-add finding -bool NO
fi
    
#####----- Rule: os_terminal_secure_keyboard_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_terminal_secure_keyboard_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.Terminal')\
.objectForKey('SecureKeyboardEntry').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_terminal_secure_keyboard_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_terminal_secure_keyboard_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) os_terminal_secure_keyboard_enable passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_terminal_secure_keyboard_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_terminal_secure_keyboard_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_terminal_secure_keyboard_enable failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_terminal_secure_keyboard_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_terminal_secure_keyboard_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) os_terminal_secure_keyboard_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_terminal_secure_keyboard_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_terminal_secure_keyboard_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_terminal_secure_keyboard_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_terminal_secure_keyboard_enable -dict-add finding -bool NO
fi
    
#####----- Rule: os_time_offset_limit_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_time_offset_limit_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/sntp $(/usr/sbin/systemsetup -getnetworktimeserver | /usr/bin/awk '{print $4}') | /usr/bin/awk -F'.' '/\+\/\-/{if (substr($1,2) >= 270) {print "No"} else {print "Yes"}}'
)
    # expected result {'string': 'yes'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_time_offset_limit_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_time_offset_limit_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "Yes" ]]; then
        /bin/echo "$(date -u) os_time_offset_limit_configure passed (Result: $result_value, Expected: "{'string': 'yes'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_time_offset_limit_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_time_offset_limit_configure passed (Result: $result_value, Expected: "{'string': 'yes'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_time_offset_limit_configure failed (Result: $result_value, Expected: "{'string': 'yes'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_time_offset_limit_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_time_offset_limit_configure failed (Result: $result_value, Expected: "{'string': 'yes'}")"
        else
            /bin/echo "$(date -u) os_time_offset_limit_configure failed (Result: $result_value, Expected: "{'string': 'yes'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_time_offset_limit_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_time_offset_limit_configure failed (Result: $result_value, Expected: "{'string': 'yes'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_time_offset_limit_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_time_offset_limit_configure -dict-add finding -bool NO
fi
    
#####----- Rule: os_unlock_active_user_session_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(5)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_unlock_active_user_session_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/security authorizationdb read system.login.screensaver 2>&1 | /usr/bin/grep -c 'use-login-window-ui'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) os_unlock_active_user_session_disable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_unlock_active_user_session_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_unlock_active_user_session_disable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_unlock_active_user_session_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) os_unlock_active_user_session_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_unlock_active_user_session_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_unlock_active_user_session_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool NO
fi
    
#####----- Rule: os_world_writable_library_folder_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_world_writable_library_folder_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/find /System/Volumes/Data/Library -type d -perm -2 -ls | /usr/bin/grep -v Caches | /usr/bin/grep -v /Preferences/Audio/Data | /usr/bin/wc -l | /usr/bin/xargs
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_world_writable_library_folder_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_world_writable_library_folder_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) os_world_writable_library_folder_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_world_writable_library_folder_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_world_writable_library_folder_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_world_writable_library_folder_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_world_writable_library_folder_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_world_writable_library_folder_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) os_world_writable_library_folder_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_world_writable_library_folder_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_world_writable_library_folder_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_world_writable_library_folder_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_world_writable_library_folder_configure -dict-add finding -bool NO
fi
    
#####----- Rule: os_world_writable_system_folder_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: os_world_writable_system_folder_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/find /System/Volumes/Data/System -type d -perm -2 -ls | /usr/bin/grep -v "Drop Box" | /usr/bin/wc -l | /usr/bin/xargs
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_world_writable_system_folder_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_world_writable_system_folder_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) os_world_writable_system_folder_configure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" os_world_writable_system_folder_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - os_world_writable_system_folder_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) os_world_writable_system_folder_configure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_world_writable_system_folder_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_world_writable_system_folder_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) os_world_writable_system_folder_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" os_world_writable_system_folder_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - os_world_writable_system_folder_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) os_world_writable_system_folder_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" os_world_writable_system_folder_configure -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_airplay_receiver_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_airplay_receiver_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowAirPlayIncomingRequests').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_airplay_receiver_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_airplay_receiver_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "false" ]]; then
        /bin/echo "$(date -u) sysprefs_airplay_receiver_disable passed (Result: $result_value, Expected: "{'string': 'false'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_airplay_receiver_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_airplay_receiver_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_airplay_receiver_disable failed (Result: $result_value, Expected: "{'string': 'false'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_airplay_receiver_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_airplay_receiver_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            /bin/echo "$(date -u) sysprefs_airplay_receiver_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_airplay_receiver_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_airplay_receiver_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_airplay_receiver_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_airplay_receiver_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_automatic_login_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2
# * IA-5(13)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_automatic_login_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.loginwindow')\
.objectForKey('com.apple.login.mcx.DisableAutoLoginClient').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_automatic_login_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_automatic_login_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_automatic_login_disable passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_automatic_login_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_automatic_login_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_automatic_login_disable failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_automatic_login_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_automatic_login_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_automatic_login_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_automatic_login_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_automatic_login_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_automatic_login_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_automatic_login_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_bluetooth_menu_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_bluetooth_menu_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.controlcenter')\
.objectForKey('Bluetooth').js
EOS
)
    # expected result {'integer': 18}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_bluetooth_menu_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_bluetooth_menu_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "18" ]]; then
        /bin/echo "$(date -u) sysprefs_bluetooth_menu_enable passed (Result: $result_value, Expected: "{'integer': 18}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_bluetooth_menu_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_bluetooth_menu_enable passed (Result: $result_value, Expected: "{'integer': 18}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_bluetooth_menu_enable failed (Result: $result_value, Expected: "{'integer': 18}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_bluetooth_menu_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_bluetooth_menu_enable failed (Result: $result_value, Expected: "{'integer': 18}")"
        else
            /bin/echo "$(date -u) sysprefs_bluetooth_menu_enable failed (Result: $result_value, Expected: "{'integer': 18}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_bluetooth_menu_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_bluetooth_menu_enable failed (Result: $result_value, Expected: "{'integer': 18}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_bluetooth_menu_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_bluetooth_menu_enable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_bluetooth_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-18(4)
# * AC-3
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_bluetooth_sharing_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults -currentHost read com.apple.Bluetooth PrefKeyServicesEnabled
)
    # expected result {'boolean': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_bluetooth_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_bluetooth_sharing_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) sysprefs_bluetooth_sharing_disable passed (Result: $result_value, Expected: "{'boolean': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_bluetooth_sharing_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_bluetooth_sharing_disable passed (Result: $result_value, Expected: "{'boolean': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_bluetooth_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_bluetooth_sharing_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_bluetooth_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 0}")"
        else
            /bin/echo "$(date -u) sysprefs_bluetooth_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_bluetooth_sharing_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_bluetooth_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_bluetooth_sharing_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_bluetooth_sharing_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_cd_dvd_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_cd_dvd_sharing_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/pgrep -q ODSAgent; /bin/echo $?
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_cd_dvd_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_cd_dvd_sharing_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) sysprefs_cd_dvd_sharing_disable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_cd_dvd_sharing_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_cd_dvd_sharing_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_cd_dvd_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_cd_dvd_sharing_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_cd_dvd_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) sysprefs_cd_dvd_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_cd_dvd_sharing_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_cd_dvd_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_cd_dvd_sharing_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_cd_dvd_sharing_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_content_caching_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_content_caching_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowContentCaching').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_content_caching_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_content_caching_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "false" ]]; then
        /bin/echo "$(date -u) sysprefs_content_caching_disable passed (Result: $result_value, Expected: "{'string': 'false'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_content_caching_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_content_caching_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_content_caching_disable failed (Result: $result_value, Expected: "{'string': 'false'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_content_caching_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_content_caching_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            /bin/echo "$(date -u) sysprefs_content_caching_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_content_caching_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_content_caching_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_content_caching_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_content_caching_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_critical_update_install_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-2
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_critical_update_install_enforce ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SoftwareUpdate')\
.objectForKey('CriticalUpdateInstall').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_critical_update_install_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_critical_update_install_enforce'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_critical_update_install_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_critical_update_install_enforce -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_critical_update_install_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_critical_update_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_critical_update_install_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_critical_update_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_critical_update_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_critical_update_install_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_critical_update_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_critical_update_install_enforce does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_critical_update_install_enforce -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_diagnostics_reports_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * SC-7(10)
# * SI-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_diagnostics_reports_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
let pref1 = $.NSUserDefaults.alloc.initWithSuiteName('com.apple.SubmitDiagInfo')\
.objectForKey('AutoSubmit').js
let pref2 = $.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowDiagnosticSubmission').js
if ( pref1 == false && pref2 == false ){
    return("true")
} else {
    return("false")
}
}
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_diagnostics_reports_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_diagnostics_reports_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_diagnostics_reports_disable passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_diagnostics_reports_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_diagnostics_reports_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_diagnostics_reports_disable failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_diagnostics_reports_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_diagnostics_reports_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_diagnostics_reports_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_diagnostics_reports_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_diagnostics_reports_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_diagnostics_reports_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_diagnostics_reports_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_filevault_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * SC-28, SC-28(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_filevault_enforce ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/fdesetup status | /usr/bin/grep -c "FileVault is On."
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_filevault_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_filevault_enforce'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) sysprefs_filevault_enforce passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_filevault_enforce -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_filevault_enforce passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_filevault_enforce failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_filevault_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_filevault_enforce failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) sysprefs_filevault_enforce failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_filevault_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_filevault_enforce failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_filevault_enforce does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_filevault_enforce -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_firewall_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-4
# * CM-7, CM-7(1)
# * SC-7, SC-7(12)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_firewall_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.security.firewall')\
.objectForKey('EnableFirewall').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_firewall_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_firewall_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_firewall_enable passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_firewall_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_firewall_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_firewall_enable failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_firewall_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_firewall_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_firewall_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_firewall_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_firewall_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_firewall_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_firewall_enable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_firewall_stealth_mode_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
# * SC-7, SC-7(16)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_firewall_stealth_mode_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.security.firewall')\
.objectForKey('EnableStealthMode').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_firewall_stealth_mode_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_firewall_stealth_mode_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_firewall_stealth_mode_enable passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_firewall_stealth_mode_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_firewall_stealth_mode_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_firewall_stealth_mode_enable failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_firewall_stealth_mode_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_firewall_stealth_mode_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_firewall_stealth_mode_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_firewall_stealth_mode_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_firewall_stealth_mode_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_firewall_stealth_mode_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_firewall_stealth_mode_enable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_guest_access_smb_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2, AC-2(9)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_guest_access_smb_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/defaults read /Library/Preferences/SystemConfiguration/com.apple.smb.server AllowGuestAccess
)
    # expected result {'boolean': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_guest_access_smb_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_guest_access_smb_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) sysprefs_guest_access_smb_disable passed (Result: $result_value, Expected: "{'boolean': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_guest_access_smb_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_guest_access_smb_disable passed (Result: $result_value, Expected: "{'boolean': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_guest_access_smb_disable failed (Result: $result_value, Expected: "{'boolean': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_guest_access_smb_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_guest_access_smb_disable failed (Result: $result_value, Expected: "{'boolean': 0}")"
        else
            /bin/echo "$(date -u) sysprefs_guest_access_smb_disable failed (Result: $result_value, Expected: "{'boolean': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_guest_access_smb_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_guest_access_smb_disable failed (Result: $result_value, Expected: "{'boolean': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_guest_access_smb_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_guest_access_smb_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_guest_account_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2, AC-2(9)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_guest_account_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.MCX')\
.objectForKey('DisableGuestAccount').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_guest_account_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_guest_account_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_guest_account_disable passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_guest_account_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_guest_account_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_guest_account_disable failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_guest_account_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_guest_account_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_guest_account_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_guest_account_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_guest_account_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_guest_account_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_guest_account_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_hot_corners_secure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-11(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_hot_corners_secure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(bl_corner="$(/usr/bin/defaults read /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-bl-corner 2>/dev/null)"
tl_corner="$(/usr/bin/defaults read /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-tl-corner 2>/dev/null)"
tr_corner="$(/usr/bin/defaults read /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-tr-corner 2>/dev/null)"
br_corner="$(/usr/bin/defaults read /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-br-corner 2>/dev/null)"

if [[ "$bl_corner" != "6" ]] && [[ "$tl_corner" != "6" ]] && [[ "$tr_corner" != "6" ]] && [[ "$br_corner" != "6" ]]; then
  echo "0"
fi
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_hot_corners_secure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_hot_corners_secure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) sysprefs_hot_corners_secure passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_hot_corners_secure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_hot_corners_secure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_hot_corners_secure failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_hot_corners_secure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_hot_corners_secure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) sysprefs_hot_corners_secure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_hot_corners_secure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_hot_corners_secure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_hot_corners_secure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_hot_corners_secure -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_install_macos_updates_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_install_macos_updates_enforce ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SoftwareUpdate')\
.objectForKey('AutomaticallyInstallMacOSUpdates').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_install_macos_updates_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_install_macos_updates_enforce'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_install_macos_updates_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_install_macos_updates_enforce -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_install_macos_updates_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_install_macos_updates_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_install_macos_updates_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_install_macos_updates_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_install_macos_updates_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_install_macos_updates_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_install_macos_updates_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_install_macos_updates_enforce does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_install_macos_updates_enforce -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_internet_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * AC-4
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_internet_sharing_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.MCX')\
.objectForKey('forceInternetSharingOff').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_internet_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_internet_sharing_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_internet_sharing_disable passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_internet_sharing_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_internet_sharing_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_internet_sharing_disable failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_internet_sharing_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_internet_sharing_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_internet_sharing_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_internet_sharing_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_internet_sharing_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_internet_sharing_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_internet_sharing_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_location_services_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_location_services_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/defaults read /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd.plist LocationServicesEnabled
)
    # expected result {'boolean': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_location_services_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_location_services_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) sysprefs_location_services_enable passed (Result: $result_value, Expected: "{'boolean': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_location_services_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_location_services_enable passed (Result: $result_value, Expected: "{'boolean': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_location_services_enable failed (Result: $result_value, Expected: "{'boolean': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_location_services_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_location_services_enable failed (Result: $result_value, Expected: "{'boolean': 1}")"
        else
            /bin/echo "$(date -u) sysprefs_location_services_enable failed (Result: $result_value, Expected: "{'boolean': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_location_services_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_location_services_enable failed (Result: $result_value, Expected: "{'boolean': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_location_services_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_location_services_enable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_loginwindow_prompt_username_password_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_loginwindow_prompt_username_password_enforce ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.loginwindow')\
.objectForKey('SHOWFULLNAME').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_loginwindow_prompt_username_password_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_loginwindow_prompt_username_password_enforce'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_loginwindow_prompt_username_password_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_loginwindow_prompt_username_password_enforce -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_loginwindow_prompt_username_password_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_loginwindow_prompt_username_password_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_loginwindow_prompt_username_password_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_loginwindow_prompt_username_password_enforce does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_loginwindow_prompt_username_password_enforce -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_media_sharing_disabled -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_media_sharing_disabled ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let pref1 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.preferences.sharing.SharingPrefsExtension')\
  .objectForKey('homeSharingUIStatus'))
  let pref2 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.preferences.sharing.SharingPrefsExtension')\
  .objectForKey('legacySharingUIStatus'))
  let pref3 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.preferences.sharing.SharingPrefsExtension')\
  .objectForKey('mediaSharingUIStatus'))
  if ( pref1 == 0 && pref2 == 0 && pref3 == 0 ) {
    return("true")
  } else {
    return("false")
  }
}
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_media_sharing_disabled'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_media_sharing_disabled'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_media_sharing_disabled passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_media_sharing_disabled -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_media_sharing_disabled passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_media_sharing_disabled failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_media_sharing_disabled -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_media_sharing_disabled failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_media_sharing_disabled failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_media_sharing_disabled -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_media_sharing_disabled failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_media_sharing_disabled does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_media_sharing_disabled -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_password_hints_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-6
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_password_hints_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.loginwindow')\
.objectForKey('RetriesUntilHint').js
EOS
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_password_hints_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_password_hints_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) sysprefs_password_hints_disable passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_password_hints_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_password_hints_disable passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_password_hints_disable failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_password_hints_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_password_hints_disable failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) sysprefs_password_hints_disable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_password_hints_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_password_hints_disable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_password_hints_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_password_hints_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_personalized_advertising_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_personalized_advertising_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.AdLib')\
.objectForKey('allowApplePersonalizedAdvertising').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_personalized_advertising_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_personalized_advertising_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "false" ]]; then
        /bin/echo "$(date -u) sysprefs_personalized_advertising_disable passed (Result: $result_value, Expected: "{'string': 'false'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_personalized_advertising_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_personalized_advertising_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_personalized_advertising_disable failed (Result: $result_value, Expected: "{'string': 'false'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_personalized_advertising_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_personalized_advertising_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            /bin/echo "$(date -u) sysprefs_personalized_advertising_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_personalized_advertising_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_personalized_advertising_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_personalized_advertising_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_personalized_advertising_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_power_nap_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_power_nap_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/pmset -g custom | /usr/bin/awk '/powernap/ { sum+=$2 } END {print sum}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_power_nap_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_power_nap_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) sysprefs_power_nap_disable passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_power_nap_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_power_nap_disable passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_power_nap_disable failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_power_nap_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_power_nap_disable failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) sysprefs_power_nap_disable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_power_nap_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_power_nap_disable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_power_nap_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_power_nap_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_printer_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_printer_sharing_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/sbin/cupsctl | /usr/bin/grep -c "_share_printers=0"
)
    # expected result {'boolean': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_printer_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_printer_sharing_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) sysprefs_printer_sharing_disable passed (Result: $result_value, Expected: "{'boolean': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_printer_sharing_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_printer_sharing_disable passed (Result: $result_value, Expected: "{'boolean': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_printer_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_printer_sharing_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_printer_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 1}")"
        else
            /bin/echo "$(date -u) sysprefs_printer_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_printer_sharing_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_printer_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_printer_sharing_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_printer_sharing_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_rae_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_rae_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"com.apple.AEServer" => true'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_rae_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_rae_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) sysprefs_rae_disable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_rae_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_rae_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_rae_disable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_rae_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_rae_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) sysprefs_rae_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_rae_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_rae_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_rae_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_rae_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_remote_management_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_remote_management_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/libexec/mdmclient QuerySecurityInfo | /usr/bin/grep -c "RemoteDesktopEnabled = 0"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_remote_management_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_remote_management_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) sysprefs_remote_management_disable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_remote_management_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_remote_management_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_remote_management_disable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_remote_management_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_remote_management_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) sysprefs_remote_management_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_remote_management_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_remote_management_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_remote_management_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_remote_management_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_screen_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_screen_sharing_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"com.apple.screensharing" => true'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_screen_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_screen_sharing_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) sysprefs_screen_sharing_disable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_screen_sharing_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_screen_sharing_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_screen_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_screen_sharing_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_screen_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) sysprefs_screen_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_screen_sharing_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_screen_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_screen_sharing_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_screen_sharing_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_screensaver_ask_for_password_delay_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_screensaver_ask_for_password_delay_enforce ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let delay = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.screensaver')\
.objectForKey('askForPasswordDelay'))
  if ( delay <= 5 ) {
    return("true")
  } else {
    return("false")
  }
}
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_screensaver_ask_for_password_delay_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_screensaver_ask_for_password_delay_enforce'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_screensaver_ask_for_password_delay_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_screensaver_ask_for_password_delay_enforce -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_screensaver_ask_for_password_delay_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_screensaver_ask_for_password_delay_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_screensaver_ask_for_password_delay_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_screensaver_ask_for_password_delay_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_screensaver_ask_for_password_delay_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_screensaver_ask_for_password_delay_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_screensaver_ask_for_password_delay_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_screensaver_ask_for_password_delay_enforce does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_screensaver_ask_for_password_delay_enforce -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_screensaver_password_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_screensaver_password_enforce ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.screensaver')\
.objectForKey('askForPassword').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_screensaver_password_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_screensaver_password_enforce'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_screensaver_password_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_screensaver_password_enforce -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_screensaver_password_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_screensaver_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_screensaver_password_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_screensaver_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_screensaver_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_screensaver_password_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_screensaver_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_screensaver_password_enforce does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_screensaver_password_enforce -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_screensaver_timeout_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-11
# * IA-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_screensaver_timeout_enforce ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let timeout = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.screensaver')\
.objectForKey('idleTime'))
  if ( timeout <= 1200 ) {
    return("true")
  } else {
    return("false")
  }
}
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_screensaver_timeout_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_screensaver_timeout_enforce'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_screensaver_timeout_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_screensaver_timeout_enforce -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_screensaver_timeout_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_screensaver_timeout_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_screensaver_timeout_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_screensaver_timeout_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_screensaver_timeout_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_screensaver_timeout_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_screensaver_timeout_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_screensaver_timeout_enforce does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_screensaver_timeout_enforce -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_smbd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_smbd_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"com.apple.smbd" => true'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_smbd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_smbd_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) sysprefs_smbd_disable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_smbd_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_smbd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_smbd_disable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_smbd_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_smbd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) sysprefs_smbd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_smbd_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_smbd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_smbd_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_smbd_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_software_update_app_update_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_software_update_app_update_enforce ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SoftwareUpdate')\
.objectForKey('AutomaticallyInstallAppUpdates').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_software_update_app_update_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_software_update_app_update_enforce'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_software_update_app_update_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_software_update_app_update_enforce -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_software_update_app_update_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_software_update_app_update_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_software_update_app_update_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_software_update_app_update_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_software_update_app_update_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_software_update_app_update_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_software_update_app_update_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_software_update_app_update_enforce does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_software_update_app_update_enforce -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_software_update_download_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_software_update_download_enforce ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SoftwareUpdate')\
.objectForKey('AutomaticDownload').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_software_update_download_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_software_update_download_enforce'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_software_update_download_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_software_update_download_enforce -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_software_update_download_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_software_update_download_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_software_update_download_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_software_update_download_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_software_update_download_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_software_update_download_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_software_update_download_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_software_update_download_enforce does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_software_update_download_enforce -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_software_update_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-2(5)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_software_update_enforce ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SoftwareUpdate')\
.objectForKey('AutomaticCheckEnabled').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_software_update_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_software_update_enforce'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_software_update_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_software_update_enforce -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_software_update_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_software_update_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_software_update_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_software_update_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_software_update_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_software_update_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_software_update_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_software_update_enforce does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_software_update_enforce -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_softwareupdate_current -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_softwareupdate_current ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(softwareupdate_date_epoch=$(/bin/date -j -f "%Y-%m-%d" "$(/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist LastFullSuccessfulDate | /usr/bin/awk '{print $1}')" "+%s")
thirty_days_epoch=$(/bin/date -v -30d "+%s")
if [[ $softwareupdate_date_epoch -lt $thirty_days_epoch ]]; then
  /bin/echo "0"
else
  /bin/echo "1"
fi
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_softwareupdate_current'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_softwareupdate_current'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) sysprefs_softwareupdate_current passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_softwareupdate_current -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_softwareupdate_current passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_softwareupdate_current failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_softwareupdate_current -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_softwareupdate_current failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) sysprefs_softwareupdate_current failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_softwareupdate_current -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_softwareupdate_current failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_softwareupdate_current does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_softwareupdate_current -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_ssh_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_ssh_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"com.openssh.sshd" => true'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_ssh_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_ssh_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) sysprefs_ssh_disable passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_ssh_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_ssh_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_ssh_disable failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_ssh_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_ssh_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) sysprefs_ssh_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_ssh_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_ssh_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_ssh_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_ssh_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_system_wide_preferences_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-6, AC-6(1), AC-6(2)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_system_wide_preferences_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/security authorizationdb read system.preferences 2> /dev/null |  /usr/bin/grep -A 1 "<key>shared</key>" | /usr/bin/grep -c "<false/>"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_system_wide_preferences_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_system_wide_preferences_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "1" ]]; then
        /bin/echo "$(date -u) sysprefs_system_wide_preferences_configure passed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_system_wide_preferences_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_system_wide_preferences_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_system_wide_preferences_configure failed (Result: $result_value, Expected: "{'integer': 1}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_system_wide_preferences_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_system_wide_preferences_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            /bin/echo "$(date -u) sysprefs_system_wide_preferences_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_system_wide_preferences_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_system_wide_preferences_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_system_wide_preferences_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_system_wide_preferences_configure -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_time_server_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-12(1)
# * SC-45(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_time_server_configure ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.MCX')\
.objectForKey('timeServer').js
EOS
)
    # expected result {'string': 'time.apple.com'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_time_server_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_time_server_configure'))["exempt_reason"]
EOS
)

    if [[ $result_value == "time.apple.com" ]]; then
        /bin/echo "$(date -u) sysprefs_time_server_configure passed (Result: $result_value, Expected: "{'string': 'time.apple.com'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_time_server_configure -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_time_server_configure passed (Result: $result_value, Expected: "{'string': 'time.apple.com'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_time_server_configure failed (Result: $result_value, Expected: "{'string': 'time.apple.com'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_time_server_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_time_server_configure failed (Result: $result_value, Expected: "{'string': 'time.apple.com'}")"
        else
            /bin/echo "$(date -u) sysprefs_time_server_configure failed (Result: $result_value, Expected: "{'string': 'time.apple.com'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_time_server_configure -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_time_server_configure failed (Result: $result_value, Expected: "{'string': 'time.apple.com'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_time_server_configure does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_time_server_configure -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_time_server_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-12(1)
# * SC-45(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_time_server_enforce ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.timed')\
.objectForKey('TMAutomaticTimeOnlyEnabled').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_time_server_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_time_server_enforce'))["exempt_reason"]
EOS
)

    if [[ $result_value == "true" ]]; then
        /bin/echo "$(date -u) sysprefs_time_server_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_time_server_enforce -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_time_server_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_time_server_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_time_server_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_time_server_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            /bin/echo "$(date -u) sysprefs_time_server_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_time_server_enforce -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_time_server_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_time_server_enforce does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_time_server_enforce -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_wake_network_access_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_wake_network_access_disable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/pmset -g custom | /usr/bin/awk '/womp/{print $2}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_wake_network_access_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_wake_network_access_disable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "0" ]]; then
        /bin/echo "$(date -u) sysprefs_wake_network_access_disable passed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_wake_network_access_disable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_wake_network_access_disable passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_wake_network_access_disable failed (Result: $result_value, Expected: "{'integer': 0}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_wake_network_access_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_wake_network_access_disable failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            /bin/echo "$(date -u) sysprefs_wake_network_access_disable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_wake_network_access_disable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_wake_network_access_disable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_wake_network_access_disable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_wake_network_access_disable -dict-add finding -bool NO
fi
    
#####----- Rule: sysprefs_wifi_menu_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    #echo 'Running the command to check the settings for: sysprefs_wifi_menu_enable ...' | tee -a "$audit_log"
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.controlcenter')\
.objectForKey('WiFi').js
EOS
)
    # expected result {'integer': 18}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_wifi_menu_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_wifi_menu_enable'))["exempt_reason"]
EOS
)

    if [[ $result_value == "18" ]]; then
        /bin/echo "$(date -u) sysprefs_wifi_menu_enable passed (Result: $result_value, Expected: "{'integer': 18}")" | /usr/bin/tee -a "$audit_log"
        /usr/bin/defaults write "$audit_plist" sysprefs_wifi_menu_enable -dict-add finding -bool NO
        /usr/bin/logger "mSCP: giant-eagle - sysprefs_wifi_menu_enable passed (Result: $result_value, Expected: "{'integer': 18}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            /bin/echo "$(date -u) sysprefs_wifi_menu_enable failed (Result: $result_value, Expected: "{'integer': 18}")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_wifi_menu_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_wifi_menu_enable failed (Result: $result_value, Expected: "{'integer': 18}")"
        else
            /bin/echo "$(date -u) sysprefs_wifi_menu_enable failed (Result: $result_value, Expected: "{'integer': 18}") - Exemption Allowed (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write "$audit_plist" sysprefs_wifi_menu_enable -dict-add finding -bool YES
            /usr/bin/logger "mSCP: giant-eagle - sysprefs_wifi_menu_enable failed (Result: $result_value, Expected: "{'integer': 18}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    /bin/echo "$(date -u) sysprefs_wifi_menu_enable does not apply to this architechture" | tee -a "$audit_log"
    /usr/bin/defaults write "$audit_plist" sysprefs_wifi_menu_enable -dict-add finding -bool NO
fi
    
lastComplianceScan=$(defaults read "$audit_plist" lastComplianceCheck)
/bin/echo "Results written to $audit_plist"

if [[ ! $check ]];then
    pause
fi

}

run_fix(){

if [[ ! -e "$audit_plist" ]]; then
    /bin/echo "Audit plist doesn't exist, please run Audit Check First" | tee -a "$audit_log"

    if [[ ! $fix ]]; then
        pause
        show_menus
        read_options
    else
        exit 1
    fi
fi

if [[ ! $fix ]]; then
    ask 'THE SOFTWARE IS PROVIDED "AS IS" WITHOUT ANY WARRANTY OF ANY KIND, EITHER EXPRESSED, IMPLIED, OR STATUTORY, INCLUDING, BUT NOT LIMITED TO, ANY WARRANTY THAT THE SOFTWARE WILL CONFORM TO SPECIFICATIONS, ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND FREEDOM FROM INFRINGEMENT, AND ANY WARRANTY THAT THE DOCUMENTATION WILL CONFORM TO THE SOFTWARE, OR ANY WARRANTY THAT THE SOFTWARE WILL BE ERROR FREE.  IN NO EVENT SHALL NIST BE LIABLE FOR ANY DAMAGES, INCLUDING, BUT NOT LIMITED TO, DIRECT, INDIRECT, SPECIAL OR CONSEQUENTIAL DAMAGES, ARISING OUT OF, RESULTING FROM, OR IN ANY WAY CONNECTED WITH THIS SOFTWARE, WHETHER OR NOT BASED UPON WARRANTY, CONTRACT, TORT, OR OTHERWISE, WHETHER OR NOT INJURY WAS SUSTAINED BY PERSONS OR PROPERTY OR OTHERWISE, AND WHETHER OR NOT LOSS WAS SUSTAINED FROM, OR AROSE OUT OF THE RESULTS OF, OR USE OF, THE SOFTWARE OR SERVICES PROVIDED HEREUNDER. WOULD YOU LIKE TO CONTINUE? ' N

    if [[ $? != 0 ]]; then
        show_menus
        read_options
    fi
fi

# append to existing logfile
/bin/echo "$(date -u) Beginning remediation of non-compliant settings" >> "$audit_log"

# run mcxrefresh
/usr/bin/mcxrefresh -u $CURR_USER_UID


    
#####----- Rule: audit_acls_files_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_acls_files_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_acls_files_configure'))["exempt_reason"]
EOS
)

audit_acls_files_configure_audit_score=$($plb -c "print audit_acls_files_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_acls_files_configure_audit_score == "true" ]]; then
        ask 'audit_acls_files_configure - Run the command(s)-> /bin/chmod -RN $(/usr/bin/awk -F: '"'"'/^dir/{print $2}'"'"' /etc/security/audit_control) ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_acls_files_configure ...' | /usr/bin/tee -a "$audit_log"
            /bin/chmod -RN $(/usr/bin/awk -F: '/^dir/{print $2}' /etc/security/audit_control)
        fi
    else
        /bin/echo 'Settings for: audit_acls_files_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_acls_files_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_acls_folders_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_acls_folders_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_acls_folders_configure'))["exempt_reason"]
EOS
)

audit_acls_folders_configure_audit_score=$($plb -c "print audit_acls_folders_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_acls_folders_configure_audit_score == "true" ]]; then
        ask 'audit_acls_folders_configure - Run the command(s)-> /bin/chmod -N $(/usr/bin/grep '"'"'^dir'"'"' /etc/security/audit_control | /usr/bin/awk -F: '"'"'{print $2}'"'"') ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_acls_folders_configure ...' | /usr/bin/tee -a "$audit_log"
            /bin/chmod -N $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}')
        fi
    else
        /bin/echo 'Settings for: audit_acls_folders_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_acls_folders_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_auditd_enabled -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-12, AU-12(1), AU-12(3)
# * AU-14(1)
# * AU-3, AU-3(1)
# * AU-8
# * CM-5(1)
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_auditd_enabled'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_auditd_enabled'))["exempt_reason"]
EOS
)

audit_auditd_enabled_audit_score=$($plb -c "print audit_auditd_enabled:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_auditd_enabled_audit_score == "true" ]]; then
        ask 'audit_auditd_enabled - Run the command(s)-> /bin/launchctl load -w /System/Library/LaunchDaemons/com.apple.auditd.plist ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_auditd_enabled ...' | /usr/bin/tee -a "$audit_log"
            /bin/launchctl load -w /System/Library/LaunchDaemons/com.apple.auditd.plist
        fi
    else
        /bin/echo 'Settings for: audit_auditd_enabled already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_auditd_enabled has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_control_acls_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_acls_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_acls_configure'))["exempt_reason"]
EOS
)

audit_control_acls_configure_audit_score=$($plb -c "print audit_control_acls_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_control_acls_configure_audit_score == "true" ]]; then
        ask 'audit_control_acls_configure - Run the command(s)-> /bin/chmod -N /etc/security/audit_control ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_control_acls_configure ...' | /usr/bin/tee -a "$audit_log"
            /bin/chmod -N /etc/security/audit_control
        fi
    else
        /bin/echo 'Settings for: audit_control_acls_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_control_acls_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_control_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_group_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_group_configure'))["exempt_reason"]
EOS
)

audit_control_group_configure_audit_score=$($plb -c "print audit_control_group_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_control_group_configure_audit_score == "true" ]]; then
        ask 'audit_control_group_configure - Run the command(s)-> /usr/bin/chgrp wheel /etc/security/audit_control ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_control_group_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/chgrp wheel /etc/security/audit_control
        fi
    else
        /bin/echo 'Settings for: audit_control_group_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_control_group_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_control_mode_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_mode_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_mode_configure'))["exempt_reason"]
EOS
)

audit_control_mode_configure_audit_score=$($plb -c "print audit_control_mode_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_control_mode_configure_audit_score == "true" ]]; then
        ask 'audit_control_mode_configure - Run the command(s)-> /bin/chmod 440 /etc/security/audit_control ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_control_mode_configure ...' | /usr/bin/tee -a "$audit_log"
            /bin/chmod 440 /etc/security/audit_control
        fi
    else
        /bin/echo 'Settings for: audit_control_mode_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_control_mode_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_control_owner_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_owner_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_control_owner_configure'))["exempt_reason"]
EOS
)

audit_control_owner_configure_audit_score=$($plb -c "print audit_control_owner_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_control_owner_configure_audit_score == "true" ]]; then
        ask 'audit_control_owner_configure - Run the command(s)-> /usr/sbin/chown root /etc/security/audit_control ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_control_owner_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/sbin/chown root /etc/security/audit_control
        fi
    else
        /bin/echo 'Settings for: audit_control_owner_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_control_owner_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_files_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_files_group_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_files_group_configure'))["exempt_reason"]
EOS
)

audit_files_group_configure_audit_score=$($plb -c "print audit_files_group_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_files_group_configure_audit_score == "true" ]]; then
        ask 'audit_files_group_configure - Run the command(s)-> /usr/bin/chgrp -R wheel $(/usr/bin/grep '"'"'^dir'"'"' /etc/security/audit_control | /usr/bin/awk -F: '"'"'{print $2}'"'"')/* ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_files_group_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/chgrp -R wheel $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}')/*
        fi
    else
        /bin/echo 'Settings for: audit_files_group_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_files_group_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_files_mode_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_files_mode_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_files_mode_configure'))["exempt_reason"]
EOS
)

audit_files_mode_configure_audit_score=$($plb -c "print audit_files_mode_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_files_mode_configure_audit_score == "true" ]]; then
        ask 'audit_files_mode_configure - Run the command(s)-> /bin/chmod 440 $(/usr/bin/grep '"'"'^dir'"'"' /etc/security/audit_control | /usr/bin/awk -F: '"'"'{print $2}'"'"')/* ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_files_mode_configure ...' | /usr/bin/tee -a "$audit_log"
            /bin/chmod 440 $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}')/*
        fi
    else
        /bin/echo 'Settings for: audit_files_mode_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_files_mode_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_files_owner_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_files_owner_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_files_owner_configure'))["exempt_reason"]
EOS
)

audit_files_owner_configure_audit_score=$($plb -c "print audit_files_owner_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_files_owner_configure_audit_score == "true" ]]; then
        ask 'audit_files_owner_configure - Run the command(s)-> /usr/sbin/chown -R root $(/usr/bin/grep '"'"'^dir'"'"' /etc/security/audit_control | /usr/bin/awk -F: '"'"'{print $2}'"'"')/* ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_files_owner_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/sbin/chown -R root $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}')/*
        fi
    else
        /bin/echo 'Settings for: audit_files_owner_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_files_owner_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_flags_aa_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * CM-5(1)
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_aa_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_aa_configure'))["exempt_reason"]
EOS
)

audit_flags_aa_configure_audit_score=$($plb -c "print audit_flags_aa_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_aa_configure_audit_score == "true" ]]; then
        ask 'audit_flags_aa_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*[^-]aa" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,aa/'"'"' /etc/security/audit_control; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_flags_aa_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/grep -qE "^flags.*[^-]aa" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,aa/' /etc/security/audit_control; /usr/sbin/audit -s
        fi
    else
        /bin/echo 'Settings for: audit_flags_aa_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_flags_aa_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_flags_ad_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12), AC-2(4)
# * AC-6(9)
# * AU-12
# * AU-2
# * CM-5(1)
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_ad_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_ad_configure'))["exempt_reason"]
EOS
)

audit_flags_ad_configure_audit_score=$($plb -c "print audit_flags_ad_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_ad_configure_audit_score == "true" ]]; then
        ask 'audit_flags_ad_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*[^-]ad" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,ad/'"'"' /etc/security/audit_control; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_flags_ad_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/grep -qE "^flags.*[^-]ad" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,ad/' /etc/security/audit_control; /usr/sbin/audit -s
        fi
    else
        /bin/echo 'Settings for: audit_flags_ad_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_flags_ad_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_flags_ex_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * CM-5(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_ex_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_ex_configure'))["exempt_reason"]
EOS
)

audit_flags_ex_configure_audit_score=$($plb -c "print audit_flags_ex_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_ex_configure_audit_score == "true" ]]; then
        ask 'audit_flags_ex_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*-ex" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,-ex/'"'"' /etc/security/audit_control; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_flags_ex_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/grep -qE "^flags.*-ex" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,-ex/' /etc/security/audit_control; /usr/sbin/audit -s
        fi
    else
        /bin/echo 'Settings for: audit_flags_ex_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_flags_ex_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_flags_fm_failed_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_fm_failed_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_fm_failed_configure'))["exempt_reason"]
EOS
)

audit_flags_fm_failed_configure_audit_score=$($plb -c "print audit_flags_fm_failed_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_fm_failed_configure_audit_score == "true" ]]; then
        ask 'audit_flags_fm_failed_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*-fm" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,-fm/'"'"' /etc/security/audit_control;/usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_flags_fm_failed_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/grep -qE "^flags.*-fm" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,-fm/' /etc/security/audit_control;/usr/sbin/audit -s
        fi
    else
        /bin/echo 'Settings for: audit_flags_fm_failed_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_flags_fm_failed_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_flags_fr_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_fr_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_fr_configure'))["exempt_reason"]
EOS
)

audit_flags_fr_configure_audit_score=$($plb -c "print audit_flags_fr_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_fr_configure_audit_score == "true" ]]; then
        ask 'audit_flags_fr_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*-fr" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,-fr/'"'"' /etc/security/audit_control;/usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_flags_fr_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/grep -qE "^flags.*-fr" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,-fr/' /etc/security/audit_control;/usr/sbin/audit -s
        fi
    else
        /bin/echo 'Settings for: audit_flags_fr_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_flags_fr_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_flags_fw_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_fw_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_fw_configure'))["exempt_reason"]
EOS
)

audit_flags_fw_configure_audit_score=$($plb -c "print audit_flags_fw_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_fw_configure_audit_score == "true" ]]; then
        ask 'audit_flags_fw_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*-fw" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,-fw/'"'"' /etc/security/audit_control;/usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_flags_fw_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/grep -qE "^flags.*-fw" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,-fw/' /etc/security/audit_control;/usr/sbin/audit -s
        fi
    else
        /bin/echo 'Settings for: audit_flags_fw_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_flags_fw_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_flags_lo_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17(1)
# * AC-2(12)
# * AU-12
# * AU-2
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_lo_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_flags_lo_configure'))["exempt_reason"]
EOS
)

audit_flags_lo_configure_audit_score=$($plb -c "print audit_flags_lo_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_lo_configure_audit_score == "true" ]]; then
        ask 'audit_flags_lo_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*[^-]lo" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,lo/'"'"' /etc/security/audit_control; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_flags_lo_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/grep -qE "^flags.*[^-]lo" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,lo/' /etc/security/audit_control; /usr/sbin/audit -s
        fi
    else
        /bin/echo 'Settings for: audit_flags_lo_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_flags_lo_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_folder_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_folder_group_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_folder_group_configure'))["exempt_reason"]
EOS
)

audit_folder_group_configure_audit_score=$($plb -c "print audit_folder_group_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_folder_group_configure_audit_score == "true" ]]; then
        ask 'audit_folder_group_configure - Run the command(s)-> /usr/bin/chgrp wheel $(/usr/bin/awk -F : '"'"'/^dir/{print $2}'"'"' /etc/security/audit_control) ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_folder_group_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/chgrp wheel $(/usr/bin/awk -F : '/^dir/{print $2}' /etc/security/audit_control)
        fi
    else
        /bin/echo 'Settings for: audit_folder_group_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_folder_group_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_folder_owner_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_folder_owner_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_folder_owner_configure'))["exempt_reason"]
EOS
)

audit_folder_owner_configure_audit_score=$($plb -c "print audit_folder_owner_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_folder_owner_configure_audit_score == "true" ]]; then
        ask 'audit_folder_owner_configure - Run the command(s)-> /usr/sbin/chown root $(/usr/bin/awk -F : '"'"'/^dir/{print $2}'"'"' /etc/security/audit_control) ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_folder_owner_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/sbin/chown root $(/usr/bin/awk -F : '/^dir/{print $2}' /etc/security/audit_control)
        fi
    else
        /bin/echo 'Settings for: audit_folder_owner_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_folder_owner_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_folders_mode_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_folders_mode_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_folders_mode_configure'))["exempt_reason"]
EOS
)

audit_folders_mode_configure_audit_score=$($plb -c "print audit_folders_mode_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_folders_mode_configure_audit_score == "true" ]]; then
        ask 'audit_folders_mode_configure - Run the command(s)-> /bin/chmod 700 $(/usr/bin/grep '"'"'^dir'"'"' /etc/security/audit_control | /usr/bin/awk -F: '"'"'{print $2}'"'"') ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_folders_mode_configure ...' | /usr/bin/tee -a "$audit_log"
            /bin/chmod 700 $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}')
        fi
    else
        /bin/echo 'Settings for: audit_folders_mode_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_folders_mode_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: audit_retention_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-11
# * AU-4

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_retention_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('audit_retention_configure'))["exempt_reason"]
EOS
)

audit_retention_configure_audit_score=$($plb -c "print audit_retention_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_retention_configure_audit_score == "true" ]]; then
        ask 'audit_retention_configure - Run the command(s)-> /usr/bin/sed -i.bak '"'"'s/^expire-after.*/expire-after:60d OR 1G/'"'"' /etc/security/audit_control; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: audit_retention_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/sed -i.bak 's/^expire-after.*/expire-after:60d OR 1G/' /etc/security/audit_control; /usr/sbin/audit -s
        fi
    else
        /bin/echo 'Settings for: audit_retention_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) audit_retention_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_authenticated_root_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-3
# * CM-5
# * MA-4(1)
# * SC-34
# * SI-7, SI-7(6)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_authenticated_root_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_authenticated_root_enable'))["exempt_reason"]
EOS
)

os_authenticated_root_enable_audit_score=$($plb -c "print os_authenticated_root_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_authenticated_root_enable_audit_score == "true" ]]; then
        ask 'os_authenticated_root_enable - Run the command(s)-> /usr/bin/csrutil authenticated-root enable ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_authenticated_root_enable ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/csrutil authenticated-root enable
        fi
    else
        /bin/echo 'Settings for: os_authenticated_root_enable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_authenticated_root_enable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_gatekeeper_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-14
# * CM-5
# * SI-3
# * SI-7(1), SI-7(15)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_gatekeeper_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_gatekeeper_enable'))["exempt_reason"]
EOS
)

os_gatekeeper_enable_audit_score=$($plb -c "print os_gatekeeper_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_gatekeeper_enable_audit_score == "true" ]]; then
        ask 'os_gatekeeper_enable - Run the command(s)-> /usr/sbin/spctl --global-enable ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_gatekeeper_enable ...' | /usr/bin/tee -a "$audit_log"
            /usr/sbin/spctl --global-enable
        fi
    else
        /bin/echo 'Settings for: os_gatekeeper_enable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_gatekeeper_enable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_guest_folder_removed -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_guest_folder_removed'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_guest_folder_removed'))["exempt_reason"]
EOS
)

os_guest_folder_removed_audit_score=$($plb -c "print os_guest_folder_removed:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_guest_folder_removed_audit_score == "true" ]]; then
        ask 'os_guest_folder_removed - Run the command(s)-> /bin/rm -Rf /Users/Guest ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_guest_folder_removed ...' | /usr/bin/tee -a "$audit_log"
            /bin/rm -Rf /Users/Guest
        fi
    else
        /bin/echo 'Settings for: os_guest_folder_removed already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_guest_folder_removed has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_hibernate_mode_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_hibernate_mode_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_hibernate_mode_enable'))["exempt_reason"]
EOS
)

os_hibernate_mode_enable_audit_score=$($plb -c "print os_hibernate_mode_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_hibernate_mode_enable_audit_score == "true" ]]; then
        ask 'os_hibernate_mode_enable - Run the command(s)-> if [[ "$(/usr/sbin/sysctl -n machdep.cpu.brand_string)" =~ "Intel" ]]; then
  /usr/bin/pmset -a standbydelayhigh 600
  /usr/bin/pmset -a standbydelaylow 600
  /usr/bin/pmset -a highstandbythreshold 90
else
  /usr/bin/pmset -a standbydelay 900
fi ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_hibernate_mode_enable ...' | /usr/bin/tee -a "$audit_log"
            if [[ "$(/usr/sbin/sysctl -n machdep.cpu.brand_string)" =~ "Intel" ]]; then
  /usr/bin/pmset -a standbydelayhigh 600
  /usr/bin/pmset -a standbydelaylow 600
  /usr/bin/pmset -a highstandbythreshold 90
else
  /usr/bin/pmset -a standbydelay 900
fi
        fi
    else
        /bin/echo 'Settings for: os_hibernate_mode_enable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_hibernate_mode_enable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_home_folders_secure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-6

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_home_folders_secure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_home_folders_secure'))["exempt_reason"]
EOS
)

os_home_folders_secure_audit_score=$($plb -c "print os_home_folders_secure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_home_folders_secure_audit_score == "true" ]]; then
        ask 'os_home_folders_secure - Run the command(s)-> IFS=$'"'"'
'"'"'
for userDirs in $( /usr/bin/find /System/Volumes/Data/Users -mindepth 1 -maxdepth 1 -type d -perm -1 | /usr/bin/grep -v "Shared" | /usr/bin/grep -v "Guest" ); do
  /bin/chmod og-rwx "$userDirs"
done
unset IFS ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_home_folders_secure ...' | /usr/bin/tee -a "$audit_log"
            IFS=$'
'
for userDirs in $( /usr/bin/find /System/Volumes/Data/Users -mindepth 1 -maxdepth 1 -type d -perm -1 | /usr/bin/grep -v "Shared" | /usr/bin/grep -v "Guest" ); do
  /bin/chmod og-rwx "$userDirs"
done
unset IFS
        fi
    else
        /bin/echo 'Settings for: os_home_folders_secure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_home_folders_secure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_httpd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_httpd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_httpd_disable'))["exempt_reason"]
EOS
)

os_httpd_disable_audit_score=$($plb -c "print os_httpd_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_httpd_disable_audit_score == "true" ]]; then
        ask 'os_httpd_disable - Run the command(s)-> /bin/launchctl disable system/org.apache.httpd ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_httpd_disable ...' | /usr/bin/tee -a "$audit_log"
            /bin/launchctl disable system/org.apache.httpd
        fi
    else
        /bin/echo 'Settings for: os_httpd_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_httpd_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_install_log_retention_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-11
# * AU-4

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_install_log_retention_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_install_log_retention_configure'))["exempt_reason"]
EOS
)

os_install_log_retention_configure_audit_score=$($plb -c "print os_install_log_retention_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_install_log_retention_configure_audit_score == "true" ]]; then
        ask 'os_install_log_retention_configure - Run the command(s)-> /usr/bin/sed -i '"'"''"'"' "s/\* file \/var\/log\/install.log.*/\* file \/var\/log\/install.log format='"'"'\$\(\(Time\)\(JZ\)\) \$Host \$\(Sender\)\[\$\(PID\)\]: \$Message'"'"' rotate=utc compress file_max=50M size_only ttl=365/g" /etc/asl/com.apple.install ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_install_log_retention_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/sed -i '' "s/\* file \/var\/log\/install.log.*/\* file \/var\/log\/install.log format='\$\(\(Time\)\(JZ\)\) \$Host \$\(Sender\)\[\$\(PID\)\]: \$Message' rotate=utc compress file_max=50M size_only ttl=365/g" /etc/asl/com.apple.install
        fi
    else
        /bin/echo 'Settings for: os_install_log_retention_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_install_log_retention_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_mobile_file_integrity_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_mobile_file_integrity_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_mobile_file_integrity_enable'))["exempt_reason"]
EOS
)

os_mobile_file_integrity_enable_audit_score=$($plb -c "print os_mobile_file_integrity_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_mobile_file_integrity_enable_audit_score == "true" ]]; then
        ask 'os_mobile_file_integrity_enable - Run the command(s)-> /usr/sbin/nvram boot-args="" ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_mobile_file_integrity_enable ...' | /usr/bin/tee -a "$audit_log"
            /usr/sbin/nvram boot-args=""
        fi
    else
        /bin/echo 'Settings for: os_mobile_file_integrity_enable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_mobile_file_integrity_enable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_nfsd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_nfsd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_nfsd_disable'))["exempt_reason"]
EOS
)

os_nfsd_disable_audit_score=$($plb -c "print os_nfsd_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_nfsd_disable_audit_score == "true" ]]; then
        ask 'os_nfsd_disable - Run the command(s)-> /bin/launchctl disable system/com.apple.nfsd ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_nfsd_disable ...' | /usr/bin/tee -a "$audit_log"
            /bin/launchctl disable system/com.apple.nfsd
        fi
    else
        /bin/echo 'Settings for: os_nfsd_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_nfsd_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_password_hint_remove -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-6

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_password_hint_remove'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_password_hint_remove'))["exempt_reason"]
EOS
)

os_password_hint_remove_audit_score=$($plb -c "print os_password_hint_remove:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_password_hint_remove_audit_score == "true" ]]; then
        ask 'os_password_hint_remove - Run the command(s)-> for u in $(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '"'"'$2 > 500 {print $1}'"'"'); do 
  /usr/bin/dscl . -delete /Users/$u hint
done ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_password_hint_remove ...' | /usr/bin/tee -a "$audit_log"
            for u in $(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '$2 > 500 {print $1}'); do 
  /usr/bin/dscl . -delete /Users/$u hint
done
        fi
    else
        /bin/echo 'Settings for: os_password_hint_remove already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_password_hint_remove has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_root_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(5)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_root_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_root_disable'))["exempt_reason"]
EOS
)

os_root_disable_audit_score=$($plb -c "print os_root_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_root_disable_audit_score == "true" ]]; then
        ask 'os_root_disable - Run the command(s)-> /usr/bin/dscl . -create /Users/root UserShell /usr/bin/false ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_root_disable ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/dscl . -create /Users/root UserShell /usr/bin/false
        fi
    else
        /bin/echo 'Settings for: os_root_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_root_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_show_filename_extensions_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_show_filename_extensions_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_show_filename_extensions_enable'))["exempt_reason"]
EOS
)

os_show_filename_extensions_enable_audit_score=$($plb -c "print os_show_filename_extensions_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_show_filename_extensions_enable_audit_score == "true" ]]; then
        ask 'os_show_filename_extensions_enable - Run the command(s)-> /usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults write /Users/"$CURRENT_USER"/Library/Preferences/.GlobalPreferences AppleShowAllExtensions -bool true ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_show_filename_extensions_enable ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults write /Users/"$CURRENT_USER"/Library/Preferences/.GlobalPreferences AppleShowAllExtensions -bool true
        fi
    else
        /bin/echo 'Settings for: os_show_filename_extensions_enable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_show_filename_extensions_enable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_sip_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-3
# * AU-9, AU-9(3)
# * CM-5, CM-5(6)
# * SC-4
# * SI-2
# * SI-7

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_sip_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_sip_enable'))["exempt_reason"]
EOS
)

os_sip_enable_audit_score=$($plb -c "print os_sip_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_sip_enable_audit_score == "true" ]]; then
        ask 'os_sip_enable - Run the command(s)-> /usr/bin/csrutil enable ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_sip_enable ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/csrutil enable
        fi
    else
        /bin/echo 'Settings for: os_sip_enable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_sip_enable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_sudo_timeout_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_sudo_timeout_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_sudo_timeout_configure'))["exempt_reason"]
EOS
)

os_sudo_timeout_configure_audit_score=$($plb -c "print os_sudo_timeout_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_sudo_timeout_configure_audit_score == "true" ]]; then
        ask 'os_sudo_timeout_configure - Run the command(s)-> /usr/bin/find /etc/sudoers* -type f -exec sed -i '"'"''"'"' '"'"'/timestamp_timeout/d'"'"' '"'"'{}'"'"' \;
/bin/echo "Defaults timestamp_timeout=0" >> /etc/sudoers.d/mscp ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_sudo_timeout_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/find /etc/sudoers* -type f -exec sed -i '' '/timestamp_timeout/d' '{}' \;
/bin/echo "Defaults timestamp_timeout=0" >> /etc/sudoers.d/mscp
        fi
    else
        /bin/echo 'Settings for: os_sudo_timeout_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_sudo_timeout_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_sudoers_timestamp_type_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-5(1)
# * IA-11

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_sudoers_timestamp_type_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_sudoers_timestamp_type_configure'))["exempt_reason"]
EOS
)

os_sudoers_timestamp_type_configure_audit_score=$($plb -c "print os_sudoers_timestamp_type_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_sudoers_timestamp_type_configure_audit_score == "true" ]]; then
        ask 'os_sudoers_timestamp_type_configure - Run the command(s)-> /usr/bin/find /etc/sudoers* -type f -exec sed -i '"'"''"'"' '"'"'/timestamp_type/d; /!tty_tickets/d'"'"' '"'"'{}'"'"' \; ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_sudoers_timestamp_type_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/find /etc/sudoers* -type f -exec sed -i '' '/timestamp_type/d; /!tty_tickets/d' '{}' \;
        fi
    else
        /bin/echo 'Settings for: os_sudoers_timestamp_type_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_sudoers_timestamp_type_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_system_wide_applications_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_system_wide_applications_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_system_wide_applications_configure'))["exempt_reason"]
EOS
)

os_system_wide_applications_configure_audit_score=$($plb -c "print os_system_wide_applications_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_system_wide_applications_configure_audit_score == "true" ]]; then
        ask 'os_system_wide_applications_configure - Run the command(s)-> IFS=$'"'"'
'"'"'
for apps in $( /usr/bin/find /Applications -iname "*\.app" -type d -perm -2 ); do
  /bin/chmod -R o-w "$apps"
done ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_system_wide_applications_configure ...' | /usr/bin/tee -a "$audit_log"
            IFS=$'
'
for apps in $( /usr/bin/find /Applications -iname "*\.app" -type d -perm -2 ); do
  /bin/chmod -R o-w "$apps"
done
        fi
    else
        /bin/echo 'Settings for: os_system_wide_applications_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_system_wide_applications_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_time_offset_limit_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_time_offset_limit_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_time_offset_limit_configure'))["exempt_reason"]
EOS
)

os_time_offset_limit_configure_audit_score=$($plb -c "print os_time_offset_limit_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_time_offset_limit_configure_audit_score == "true" ]]; then
        ask 'os_time_offset_limit_configure - Run the command(s)-> /usr/bin/sntp -Ss $(/usr/sbin/systemsetup -getnetworktimeserver | /usr/bin/awk '"'"'{print $4}'"'"') ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_time_offset_limit_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/sntp -Ss $(/usr/sbin/systemsetup -getnetworktimeserver | /usr/bin/awk '{print $4}')
        fi
    else
        /bin/echo 'Settings for: os_time_offset_limit_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_time_offset_limit_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_unlock_active_user_session_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(5)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt_reason"]
EOS
)

os_unlock_active_user_session_disable_audit_score=$($plb -c "print os_unlock_active_user_session_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_unlock_active_user_session_disable_audit_score == "true" ]]; then
        ask 'os_unlock_active_user_session_disable - Run the command(s)-> /usr/bin/security authorizationdb write system.login.screensaver "use-login-window-ui" ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_unlock_active_user_session_disable ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/security authorizationdb write system.login.screensaver "use-login-window-ui"
        fi
    else
        /bin/echo 'Settings for: os_unlock_active_user_session_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_unlock_active_user_session_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_world_writable_library_folder_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_world_writable_library_folder_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_world_writable_library_folder_configure'))["exempt_reason"]
EOS
)

os_world_writable_library_folder_configure_audit_score=$($plb -c "print os_world_writable_library_folder_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_world_writable_library_folder_configure_audit_score == "true" ]]; then
        ask 'os_world_writable_library_folder_configure - Run the command(s)-> IFS=$'"'"'
'"'"'
for libPermissions in $( /usr/bin/find /System/Volumes/Data/Library -type d -perm -2 | /usr/bin/grep -v Caches | /usr/bin/grep -v /Preferences/Audio/Data ); do
  /bin/chmod -R o-w "$libPermissions"
done ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_world_writable_library_folder_configure ...' | /usr/bin/tee -a "$audit_log"
            IFS=$'
'
for libPermissions in $( /usr/bin/find /System/Volumes/Data/Library -type d -perm -2 | /usr/bin/grep -v Caches | /usr/bin/grep -v /Preferences/Audio/Data ); do
  /bin/chmod -R o-w "$libPermissions"
done
        fi
    else
        /bin/echo 'Settings for: os_world_writable_library_folder_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_world_writable_library_folder_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: os_world_writable_system_folder_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_world_writable_system_folder_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('os_world_writable_system_folder_configure'))["exempt_reason"]
EOS
)

os_world_writable_system_folder_configure_audit_score=$($plb -c "print os_world_writable_system_folder_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_world_writable_system_folder_configure_audit_score == "true" ]]; then
        ask 'os_world_writable_system_folder_configure - Run the command(s)-> IFS=$'"'"'
'"'"'
for sysPermissions in $( /usr/bin/find /System/Volumes/Data/System -type d -perm -2 | /usr/bin/grep -v "Drop Box" ); do
  /bin/chmod -R o-w "$sysPermissions"
done ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: os_world_writable_system_folder_configure ...' | /usr/bin/tee -a "$audit_log"
            IFS=$'
'
for sysPermissions in $( /usr/bin/find /System/Volumes/Data/System -type d -perm -2 | /usr/bin/grep -v "Drop Box" ); do
  /bin/chmod -R o-w "$sysPermissions"
done
        fi
    else
        /bin/echo 'Settings for: os_world_writable_system_folder_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) os_world_writable_system_folder_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_bluetooth_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-18(4)
# * AC-3
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_bluetooth_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_bluetooth_sharing_disable'))["exempt_reason"]
EOS
)

sysprefs_bluetooth_sharing_disable_audit_score=$($plb -c "print sysprefs_bluetooth_sharing_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_bluetooth_sharing_disable_audit_score == "true" ]]; then
        ask 'sysprefs_bluetooth_sharing_disable - Run the command(s)-> /usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool false ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_bluetooth_sharing_disable ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool false
        fi
    else
        /bin/echo 'Settings for: sysprefs_bluetooth_sharing_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_bluetooth_sharing_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_cd_dvd_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_cd_dvd_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_cd_dvd_sharing_disable'))["exempt_reason"]
EOS
)

sysprefs_cd_dvd_sharing_disable_audit_score=$($plb -c "print sysprefs_cd_dvd_sharing_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_cd_dvd_sharing_disable_audit_score == "true" ]]; then
        ask 'sysprefs_cd_dvd_sharing_disable - Run the command(s)-> /bin/launchctl unload /System/Library/LaunchDaemons/com.apple.ODSAgent.plist ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_cd_dvd_sharing_disable ...' | /usr/bin/tee -a "$audit_log"
            /bin/launchctl unload /System/Library/LaunchDaemons/com.apple.ODSAgent.plist
        fi
    else
        /bin/echo 'Settings for: sysprefs_cd_dvd_sharing_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_cd_dvd_sharing_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_guest_access_smb_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2, AC-2(9)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_guest_access_smb_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_guest_access_smb_disable'))["exempt_reason"]
EOS
)

sysprefs_guest_access_smb_disable_audit_score=$($plb -c "print sysprefs_guest_access_smb_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_guest_access_smb_disable_audit_score == "true" ]]; then
        ask 'sysprefs_guest_access_smb_disable - Run the command(s)-> /usr/sbin/sysadminctl -smbGuestAccess off ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_guest_access_smb_disable ...' | /usr/bin/tee -a "$audit_log"
            /usr/sbin/sysadminctl -smbGuestAccess off
        fi
    else
        /bin/echo 'Settings for: sysprefs_guest_access_smb_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_guest_access_smb_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_hot_corners_secure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-11(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_hot_corners_secure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_hot_corners_secure'))["exempt_reason"]
EOS
)

sysprefs_hot_corners_secure_audit_score=$($plb -c "print sysprefs_hot_corners_secure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_hot_corners_secure_audit_score == "true" ]]; then
        ask 'sysprefs_hot_corners_secure - Run the command(s)-> /usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults delete /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-bl-corner 2>/dev/null
/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults delete /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-tl-corner 2>/dev/null
/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults delete /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-tr-corner 2>/dev/null
/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults delete /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-br-corner 2>/dev/null ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_hot_corners_secure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults delete /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-bl-corner 2>/dev/null
/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults delete /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-tl-corner 2>/dev/null
/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults delete /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-tr-corner 2>/dev/null
/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults delete /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-br-corner 2>/dev/null
        fi
    else
        /bin/echo 'Settings for: sysprefs_hot_corners_secure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_hot_corners_secure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_location_services_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_location_services_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_location_services_enable'))["exempt_reason"]
EOS
)

sysprefs_location_services_enable_audit_score=$($plb -c "print sysprefs_location_services_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_location_services_enable_audit_score == "true" ]]; then
        ask 'sysprefs_location_services_enable - Run the command(s)-> /usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -bool true; /bin/launchctl kickstart -k system/com.apple.locationd ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_location_services_enable ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -bool true; /bin/launchctl kickstart -k system/com.apple.locationd
        fi
    else
        /bin/echo 'Settings for: sysprefs_location_services_enable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_location_services_enable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_power_nap_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_power_nap_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_power_nap_disable'))["exempt_reason"]
EOS
)

sysprefs_power_nap_disable_audit_score=$($plb -c "print sysprefs_power_nap_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_power_nap_disable_audit_score == "true" ]]; then
        ask 'sysprefs_power_nap_disable - Run the command(s)-> /usr/bin/pmset -a powernap 0 ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_power_nap_disable ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/pmset -a powernap 0
        fi
    else
        /bin/echo 'Settings for: sysprefs_power_nap_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_power_nap_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_printer_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_printer_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_printer_sharing_disable'))["exempt_reason"]
EOS
)

sysprefs_printer_sharing_disable_audit_score=$($plb -c "print sysprefs_printer_sharing_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_printer_sharing_disable_audit_score == "true" ]]; then
        ask 'sysprefs_printer_sharing_disable - Run the command(s)-> /usr/sbin/cupsctl --no-share-printers
/usr/bin/lpstat -p | awk '"'"'{print $2}'"'"'| /usr/bin/xargs -I{} lpadmin -p {} -o printer-is-shared=false ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_printer_sharing_disable ...' | /usr/bin/tee -a "$audit_log"
            /usr/sbin/cupsctl --no-share-printers
/usr/bin/lpstat -p | awk '{print $2}'| /usr/bin/xargs -I{} lpadmin -p {} -o printer-is-shared=false
        fi
    else
        /bin/echo 'Settings for: sysprefs_printer_sharing_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_printer_sharing_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_rae_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_rae_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_rae_disable'))["exempt_reason"]
EOS
)

sysprefs_rae_disable_audit_score=$($plb -c "print sysprefs_rae_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_rae_disable_audit_score == "true" ]]; then
        ask 'sysprefs_rae_disable - Run the command(s)-> /usr/sbin/systemsetup -setremoteappleevents off
/bin/launchctl disable system/com.apple.AEServer ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_rae_disable ...' | /usr/bin/tee -a "$audit_log"
            /usr/sbin/systemsetup -setremoteappleevents off
/bin/launchctl disable system/com.apple.AEServer
        fi
    else
        /bin/echo 'Settings for: sysprefs_rae_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_rae_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_remote_management_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_remote_management_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_remote_management_disable'))["exempt_reason"]
EOS
)

sysprefs_remote_management_disable_audit_score=$($plb -c "print sysprefs_remote_management_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_remote_management_disable_audit_score == "true" ]]; then
        ask 'sysprefs_remote_management_disable - Run the command(s)-> /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_remote_management_disable ...' | /usr/bin/tee -a "$audit_log"
            /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop
        fi
    else
        /bin/echo 'Settings for: sysprefs_remote_management_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_remote_management_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_screen_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_screen_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_screen_sharing_disable'))["exempt_reason"]
EOS
)

sysprefs_screen_sharing_disable_audit_score=$($plb -c "print sysprefs_screen_sharing_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_screen_sharing_disable_audit_score == "true" ]]; then
        ask 'sysprefs_screen_sharing_disable - Run the command(s)-> /bin/launchctl disable system/com.apple.screensharing ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_screen_sharing_disable ...' | /usr/bin/tee -a "$audit_log"
            /bin/launchctl disable system/com.apple.screensharing
        fi
    else
        /bin/echo 'Settings for: sysprefs_screen_sharing_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_screen_sharing_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_smbd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_smbd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_smbd_disable'))["exempt_reason"]
EOS
)

sysprefs_smbd_disable_audit_score=$($plb -c "print sysprefs_smbd_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_smbd_disable_audit_score == "true" ]]; then
        ask 'sysprefs_smbd_disable - Run the command(s)-> /bin/launchctl disable system/com.apple.smbd ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_smbd_disable ...' | /usr/bin/tee -a "$audit_log"
            /bin/launchctl disable system/com.apple.smbd
        fi
    else
        /bin/echo 'Settings for: sysprefs_smbd_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_smbd_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_softwareupdate_current -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_softwareupdate_current'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_softwareupdate_current'))["exempt_reason"]
EOS
)

sysprefs_softwareupdate_current_audit_score=$($plb -c "print sysprefs_softwareupdate_current:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_softwareupdate_current_audit_score == "true" ]]; then
        ask 'sysprefs_softwareupdate_current - Run the command(s)-> /usr/sbin/softwareupdate -i -a -R ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_softwareupdate_current ...' | /usr/bin/tee -a "$audit_log"
            /usr/sbin/softwareupdate -i -a -R
        fi
    else
        /bin/echo 'Settings for: sysprefs_softwareupdate_current already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_softwareupdate_current has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_ssh_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_ssh_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_ssh_disable'))["exempt_reason"]
EOS
)

sysprefs_ssh_disable_audit_score=$($plb -c "print sysprefs_ssh_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_ssh_disable_audit_score == "true" ]]; then
        ask 'sysprefs_ssh_disable - Run the command(s)-> /usr/sbin/systemsetup -f -setremotelogin off >/dev/null
/bin/launchctl disable system/com.openssh.sshd ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_ssh_disable ...' | /usr/bin/tee -a "$audit_log"
            /usr/sbin/systemsetup -f -setremotelogin off >/dev/null
/bin/launchctl disable system/com.openssh.sshd
        fi
    else
        /bin/echo 'Settings for: sysprefs_ssh_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_ssh_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_system_wide_preferences_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-6, AC-6(1), AC-6(2)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_system_wide_preferences_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_system_wide_preferences_configure'))["exempt_reason"]
EOS
)

sysprefs_system_wide_preferences_configure_audit_score=$($plb -c "print sysprefs_system_wide_preferences_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_system_wide_preferences_configure_audit_score == "true" ]]; then
        ask 'sysprefs_system_wide_preferences_configure - Run the command(s)-> /usr/bin/security authorizationdb read system.preferences > /tmp/system.preferences.plist
key_value=$(/usr/libexec/PlistBuddy -c "Print :shared" /tmp/system.preferences.plist 2>&1)
if [[ "$key_value" == *"Does Not Exist"* ]]; then
  /usr/libexec/PlistBuddy -c "Add :shared bool false" /tmp/system.preferences.plist
else
  /usr/libexec/PlistBuddy -c "Set :shared false" /tmp/system.preferences.plist
fi
/usr/bin/security authorizationdb write system.preferences < /tmp/system.preferences.plist ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_system_wide_preferences_configure ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/security authorizationdb read system.preferences > /tmp/system.preferences.plist
key_value=$(/usr/libexec/PlistBuddy -c "Print :shared" /tmp/system.preferences.plist 2>&1)
if [[ "$key_value" == *"Does Not Exist"* ]]; then
  /usr/libexec/PlistBuddy -c "Add :shared bool false" /tmp/system.preferences.plist
else
  /usr/libexec/PlistBuddy -c "Set :shared false" /tmp/system.preferences.plist
fi
/usr/bin/security authorizationdb write system.preferences < /tmp/system.preferences.plist
        fi
    else
        /bin/echo 'Settings for: sysprefs_system_wide_preferences_configure already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_system_wide_preferences_configure has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
#####----- Rule: sysprefs_wake_network_access_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_wake_network_access_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.giant-eagle.audit').objectForKey('sysprefs_wake_network_access_disable'))["exempt_reason"]
EOS
)

sysprefs_wake_network_access_disable_audit_score=$($plb -c "print sysprefs_wake_network_access_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $sysprefs_wake_network_access_disable_audit_score == "true" ]]; then
        ask 'sysprefs_wake_network_access_disable - Run the command(s)-> /usr/bin/pmset -a womp 0 ' N
        if [[ $? == 0 ]]; then
            /bin/echo 'Running the command to configure the settings for: sysprefs_wake_network_access_disable ...' | /usr/bin/tee -a "$audit_log"
            /usr/bin/pmset -a womp 0
        fi
    else
        /bin/echo 'Settings for: sysprefs_wake_network_access_disable already configured, continuing...' | /usr/bin/tee -a "$audit_log"
    fi
elif [[ ! -z "$exempt_reason" ]];then
    /bin/echo "$(date -u) sysprefs_wake_network_access_disable has an exemption, remediation skipped (Reason: "$exempt_reason")" | /usr/bin/tee -a "$audit_log"
fi
    
/bin/echo "$(date -u) Remediation complete" >> "$audit_log"

}

zparseopts -D -E -check=check -fix=fix -stats=stats -compliant=compliant_opt -non_compliant=non_compliant_opt -reset=reset

if [[ $reset ]]; then reset_plist; fi

if [[ $check ]] || [[ $fix ]] || [[ $stats ]] || [[ $compliant_opt ]] || [[ $non_compliant_opt ]]; then
    if [[ $fix ]]; then run_fix; fi
    if [[ $check ]]; then run_scan; fi
    if [[ $stats ]];then generate_stats; fi
    if [[ $compliant_opt ]];then compliance_count "compliant"; fi
    if [[ $non_compliant_opt ]];then compliance_count "non-compliant"; fi
else
    while true; do
        show_menus
        read_options
    done
fi
