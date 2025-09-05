#!/bin/zsh

# Writen by: Scott E. Kendall
# Last Revision: 01/10/2025
#
# Execute Superman script with passed parameters from JAMF
# Options include Allow on minor updates, install major updates (speicific versions) and donwload only
# 
# Parm #4 - Update Type (Major, Minor, Download, Defer, Reset)
# Parm #5 - Force OS Version
# Parm #6 - Deferral Time (in minutes)
# Parm #7 - Deferral Count
# Parm #8 - Deadline Date
# Parm #9- Icon path
# Parm #10- Test Mode On/Off
#

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin
LoggedInUser=$(echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
UserDir=$(dscl . -read /Users/${LoggedInUser} NFSHomeDirectory | awk '{ print $2 }' )

JAMFClientID="2a23ec74-d3b0-408b-8db4-67c087034de1"
JAMFSecret="3A3gsIp1fCInS9dWqBH_eh1X6iMvCdDoCC0KtERMAOpHVhf4Rkec6k4w_ndrphOc"
osInstallType="${4:-"minor"}"
osForceVersion="${5:-""}"
DeferralTime="${6:-"5,30,60,120"}"
DeferralCount="${7:-"5"}"
DeadlineDate="${8:-""}"
IconPath=${9}
TestMode="${10:-"--test-mode-on"}"
VerboseMode="${11:-"--verbose-mode-off"}"

DeferralCountSoft=$(( DeferralCount+1 ))

# Add 1 day for the "soft" deadline
[[ "${DeadlineDate}" == "" ]] && DeadlineDate=$(date "+%Y-%m-%d")
DeadLineSoftDate=$(date -j -v +1d -f "%Y-%m-%d" "${DeadlineDate}" +%Y-%m-%d)
#DeadLineSoftDate=$(date -j -f "%Y-%m-%d" "${DeadlineDate}" +%Y-%m-%d)


####################
# "Global" variables
####################

platform=$(uname -p)
logDir="/Library/Application Support/GiantEagle/logs"
logStamp=$(echo $(date +%Y%m%d))
logFile="${logDir}/Superman_OS_Install_${logStamp} (${platform}).log"
JAMFPolicy="install_superman"
JAMFIconPolicy="install_superman_icons"
CommandString=" ${TestMode}"

###########
# Functions
###########

function create_log_directory ()
{
    # Ensure that the log directory and the log files exist. If they
    # do not then create them and set the permissions.
    #
    # RETURN: None

	# If the log directory doesnt exist - create it and set the permissions
	[[ ! -d "${logDir}" ]] && mkdir -p "${logDir}"
    chmod 775 "${logDir}"

	# If the log file does not exist - create it and set the permissions
	[[ ! -f "${logFile}" ]] && touch "${logFile}"
	chmod 644 "${logFile}"
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
    echo "$(date '+%Y-%m-%d %H:%M:%S'): ${1}" | tee -a "${logFile}"
}

function check_superman_install ()
{
    # Make sure Superman is installed first

    if [[ ! -e /usr/local/bin/super ]]; then
        logMe "S.U.P.E.R.M.A.N. is not installed...installing now"
        jamf policy -trigger ${JAMFPolicy}
        sleep 5
        super --test-mode-off --workflow-disable-relaunch
    fi
}

function check_superman_icons ()
{
    # Make sure that the icons are loaded first
    [[ ! -z "${IconPath}" ]] && [[ ! -e "${IconPath}" ]] && jamf policy -trigger $JAMFIconPolicy
}

function build_superman_parm_string ()
{
    # Build the super command string
    if [[ "${osInstallType:l}" != "download" ]]; then
        #CommandString+=" --workflow-reset-super-after-completion"
        CommandString+=" --auth-jamf-client=${JAMFClientID}"
        CommandString+=" --auth-jamf-secret=${JAMFSecret}"
    fi

    CommandString+=" --display-icon-file='${IconPath}'"
    CommandString+=" "${VerboseMode}

    case "${osInstallType:l}" in
        "download" )
            logMe "Download only of OS (${osForceVersion}) for prestage purposes"
            CommandString+=" --workflow-only-download"
            CommandString+=" --install-macos-major-upgrades"
            [[ ! -z "${osForceVersion}" ]] && CommandString+=" --install-macos-major-version-target="${osForceVersion}
            ;;

        "minor" )
            logMe "Installing minor updates immediately"
            CommandString+=" --install-non-system-updates-without-restarting"
            CommandString+=" --workflow-disable-update-check-off"
            CommandString+=" --install-macos-major-upgrades"
            [[ ! -z "${osForceVersion}" ]] && CommandString+=" --install-macos-major-version-target="${osForceVersion}
            CommandString+=" --workflow-only-download-off"
            CommandString+=" --workflow-install-now"
            ;;

        "major" )
            logMe "Installing Major OS update immediately"
            CommandString+=" --workflow-only-download-off"
            CommandString+=" --schedule-zero-date-release"
            CommandString+=" --install-macos-major-upgrades"
            CommandString+=" --workflow-install-now"
            CommandString+=" --workflow-disable-update-check-off"
            CommandString+=" --workflow-reset-super-after-completion"
            #[[ ! -z "${osForceVersion}" ]] && CommandString+=" --install-macos-major-version-target="${osForceVersion}
            CommandString+=" --install-macos-major-version-target=X"
            CommandString+=" --deadline-count-focus="${DeferralCount}
            CommandString+=" --deadline-count-soft="${DeferralCount}
            ;;

        "defer-major" )
            logMe "Performing Major Deferral installation"
            CommandString+=" --deferral-timer-menu="${DeferralTime}
            CommandString+=" --deferral-timer-focus=15"
            CommandString+=" --deadline-date-soft="${DeadLineSoftDate}
            CommandString+=" --deadline-count-soft="${DeferralCountSoft}
            CommandString+=" --deadline-date-focus="${DeadlineDate}
            CommandString+=" --deadline-count-focus="${DeferralCount}
            CommandString+=" --workflow-disable-update-check-off"
            CommandString+=" --install-macos-major-upgrades"
            CommandString+=" --workflow-install-now-off"
            CommandString+=" --scheduled-install-user-choice"
            CommandString+=" --scheduled-install-reminder=120,60,5"
            [[ ! -z "${osForceVersion}" ]] && CommandString+=" --install-macos-major-version-target="${osForceVersion}

            ;;
            
        "defer-minor" )
            logMe "Performing Minor Deferral installation"
            CommandString+=" --deferral-timer-menu="${DeferralTime}
            CommandString+=" --deferral-timer-focus=15"
            CommandString+=" --deadline-date-soft="${DeadLineSoftDate}
            CommandString+=" --deadline-count-soft="${DeferralCountSoft}
            CommandString+=" --deadline-date-focus="${DeadlineDate}
            CommandString+=" --deadline-count-focus="${DeferralCount}
            CommandString+=" --install-macos-major-upgrades-off"
            [[ ! -z "${osForceVersion}" ]] && CommandString+=" --install-macos-major-version-target="${osForceVersion}
            CommandString+=" --workflow-install-now-off"
            CommandString+=" --workflow-disable-update-check-off"
            #CommandString+=" --workflow-only-download-off"
            CommandString+=" --scheduled-install-user-choice"
            CommandString+=" --scheduled-install-reminder=120,60,5"
            ;;
        
        "reset" )
            logMe "Resetting Superman back to default settings"
            CommandString=" --reset-super --workflow-disable-update-check-off"
            ;;
         
        "disable" )
            logMe "Disabling Superman from doing update checks"
            CommandString=" --reset-super --workflow-disable-update-check"
            ;;
    esac
}

###################
# Main Script
###################
create_log_directory
check_superman_install
check_superman_icons
build_superman_parm_string

# execute the command
logMe "Executing S.U.P.E.R.M.A.N. with the following string: ${CommandString}"
eval "super ${CommandString}"
exit 0
