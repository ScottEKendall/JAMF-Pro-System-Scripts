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

if [[ $6 == "" ]]; then
    MinVersion="-1"
else
    MinVersion=$6
fi
if [[ $7 == "" ]]; then
    KeyToSearch="CFBundleVersion"
else
    KeyToSearch=$7
fi


######################################################################################################
# FUNCTIONS
######################################################################################################

function logMe () {
	echo "${1}"
	echo "$(/bin/date) -- ${1}" >> "${logFile}"
}

######################################################################################################
# PRECHECK & SETUP
######################################################################################################

function create_log_directory ()
{
    # Ensure that the log directory and the log files exist. If they
    # do not then create them and set the permissions.
    #
    # RETURN: None

	# If the log directory doesnt exist - create it and set the permissions
	if [[ ! -d "${logDir}" ]]; then
		/bin/mkdir -p "${logDir}"
		/bin/chmod 755 "${logDir}"
	fi

	# If the log file does not exist - create it and set the permissions
	if [[ ! -f "${logFile}" ]]; then
		/usr/bin/touch "${logFile}"
		/bin/chmod 644 "${logFile}"
	fi
}

######################################################################################################
# MAIN SCRIPT
######################################################################################################
 
create_log_directory
#
# Check to make sure the file exists
#
if [ -e "${InstalledApp}" ]; then
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
else
    # 
    # file doesn't exist, so exit with error
    #
    logMe "Application '"${InstalledApp}"' was not found!  No action taken."

    exit 1
fi

exit 0
