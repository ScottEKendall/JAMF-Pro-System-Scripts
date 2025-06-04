#!/bin/zsh

#
# This script will remove any old version of Teams Classic & Teams (work or school) if found on the users computer
#

logDir="/Library/Application Support/GiantEagle/logs"
logStamp=$(echo $(date +%Y%m%d))
logFile="${logDir}/TeamsRemoval.log"

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
	[[ ! -d "${logDir}" ]] &&mkdir -p "${logDir}"
    chmod 755 "${logDir}"

	# If the log file does not exist - create it and set the permissions
	[[ ! -f "${logFile}" ]] && touch "${logDir}"
    chmod 644 "${logDir}"
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
    echo "$(date '+%Y%m%d %H:%M:%S'): ${1}" | tee -a "${logFile}"
}

TeamsClassic="/Applications/Microsoft Teams Classic.app"
TeamsWork="/Applications/Microsoft Teams (work or school).app"
TeamsApp="/Applications/Microsoft Teams.app"
TeamsLocalized="/Applications/Microsoft Teams.localized/"

create_log_directory

# If the "real" teams apps exists, then see if we can erase the others as well

if [[ -e "${TeamsApp}" ]]; then
	logMe "Found Existing Microsoft Teams.app"
    [[ -e "${TeamsWork}" ]] && {/bin/rm -r "${TeamsWork}"; logMe "Erasing Microsoft Teams (work or school)"; }
    [[ -e "${TeamsClassic}" ]] && {/bin/rm -r "${TeamsClassic}"; logMe "Erasing Microsoft Teams Classic"; }
    [[ -e "${TeamsLocalized}" ]] && {/bin/rm -r "${TeamsLocalized}"; logMe "Erasing Microsoft Teams Localized"; }

else
    # Teams doesn't exist, so call the JAMF policy to install it
	logMe "No Microsoft Teams.app found...reinstalling from JAMF"
    sudo jamf policy -trigger install_teams

fi
exit 0
