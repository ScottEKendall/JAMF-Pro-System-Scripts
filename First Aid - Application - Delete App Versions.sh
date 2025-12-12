#!/bin/zsh
#
# Application Removal Script
# Last Modified: Scott E. Kendall
# Last Modified Date: 12/12/2025
#
#Param #1-3 is reserved for JAMF systems script
#Param #4 - Application Name
#Param #5 - Application Path
#Param #6 - Version # to keep (if -1 is passed, then delete the app regardless of version #)
#Param #7 - Key to search against (Default: CFBundleVersion)

######################################################################################################
# SETUP
######################################################################################################

#
# do some variable cleanup so we start with correclty formmated parameters
#
InstalledAppName=$(echo $4 | sed 's/.app//')
InstalledAppPath=$(echo $5 | sed 's/\/*$//g')"/"

# Construct the application path

InstalledApp=${InstalledAppPath}${InstalledAppName}".app"
logDir="/Library/Application Support/GiantEagle/logs"
logFile="${logDir}/JAMFAppRemoval.log"

minVersion=${6:-"-1"} 
KeyToSearch=${7:-"CFBundleVersion"}

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

	# If the log directory doesn't exist - create it and set the permissions (using zsh parameter expansion to get directory)
	LOG_DIR=${LOG_FILE%/*}
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

######################################################################################################
# MAIN SCRIPT
######################################################################################################
 
create_log_directory
#
# Check to make sure the file exists
#
if [ ! -e "${InstalledApp}" ]; then
    logMe "Application '"${InstalledApp}"' was not found!  No action taken."
    exit 1
fi

# 
# The application was found, so lets see what version it is
#
InstalledAppVersion=$(defaults read "${InstalledApp}/Contents/Info.plist" ${KeyToSearch})

if [[ ${InstalledAppVersion} < ${MinVersion} ]] || [[ ${MinVersion} == "-1" ]]; then
    # 
    # App version is less then the min, so delete it
    #
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
        logMe "Application '"${InstalledApp}"' is below minimum version of ("${MinVersion}"), and has been removed"
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
else
    logMe "Application '"${InstalledApp}"' is already current with version ${InstalledAppVersion}."
fi
exit 0
