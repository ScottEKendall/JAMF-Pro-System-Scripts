#!/bin/zsh
#
# Applicaiton Removal Script
# Last Modified: Scott E. Kendall
# Last Modified Date: 09/09/2024
#
#Paran #1-3 is reserved for JAMF sytems script
#Param #4 - Application Name
#Param #5 - Application Path
#Param #6 - Version # to keep (if -1 is passed, then delete the app regardless of verison #)
#Param #7 - Key to search agains (Default: CFBundleVersion)


#
# do some variable cleanup so we start with correclty formmated parameters
#
InstalledAppName=$(echo $4 | sed 's/.app//')
InstalledAppPath=$(echo $5 | sed 's/\/*$//g')"/"

# Construct the application path

InstalledApp=${InstalledAppPath}${InstalledAppName}".app"
logDir="/Library/Application Support/GiantEagle/logs"
logFile="${logDir}/JAMFAppRemoval.log"

[[ $6 == "" ]] && MinVersion="-1" || MinVersion=$6
[[ $7 == "" ]] && KeyToSearch="CFBundleVersion" || KeyToSearch=$7

######################################################################################################
#
# FUNCTIONS
#
######################################################################################################

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
    echo "${1}" 1>&2
    echo "$(/bin/date '+%Y-%m-%d %H:%M:%S'): ${1}" | tee -a "${LOG_FILE}"
}

######################################################################################################
#
# MAIN SCRIPT
#
######################################################################################################
 
create_log_directory

InstalledAppVersion=$(defaults read "${InstalledApp}/Contents/Info.plist" ${KeyToSearch})


# Check to make sure the file exists

if [[ ! -e "${InstalledApp}" ]]; then
    logMe "Application '"${InstalledApp}"' was not found!  No action taken."
    exit 1
fi

# App was found so lets check the version #

if [[ ${InstalledAppVersion} -ge ${MinVersion} ]]
    logMe "Application '"${InstalledApp}"' is already current with version ${InstalledAppVersion}."
    exit 0
fi

# Fill exists and is less than the required version, so it can be removed

if [[ ${MinVersion} == "-1" ]]; then
    # 
    # remove the app without checking version #
    #
    logMe "Application '"${InstalledApp}" will be removed without version # check"
else
    # 
    # check the version #
    #
    logMe "Application '"${InstalledApp}"' has version of ${InstalledAppVersion}" 
    logMe "Application '"${InstalledApp}"' is below minimum version of ("${MinVersion}"), and will be removed"
fi
# 
# if the app is currently running, then kill the process(es) if it is running before we delete it
#
if pgrep -i ${InstalledAppName} > /dev/null 2>&1; then
    logMe "Stop currently running processes"
    pkill -9 ${InstalledAppName}
    logMe "Sleep for 2 seconds to make sure processes have stopped"
    sleep 2
fi
# Delete the app

/bin/rm -rf "${InstalledApp}"
[[ $? == 0 ]] && logMe "Application '"${InstalledApp}"' has been removed"
exit 0
