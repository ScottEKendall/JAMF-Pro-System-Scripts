#!/bin/zsh
#
# Purpose: download file via curl to users machine
#
# PARMS: $4 - URL path to install from (exclude filename)
#        $5 - filename to download
#        $6 - destination location
#        $7 - run installer after download (Y/N)
#        $8 - file to run after install
#
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
USER_DIR=$( dscl . -read /Users/${LOGGED_IN_USER} NFSHomeDirectory | awk '{ print $2 }' )

SUPPORT_DIR="/Library/Application Support/GiantEagle"
LOG_FILE="${SUPPORT_DIR}/Download_Internet_File.log"

##################################################
#
# Passed in variables
# 
#################################################

#Format the incoming files so that it has a trailing / at the end
urlPath=$(echo $4 | sed 's/\/*$//g')"/"
DestPath=$(echo $6 | sed 's/\/*$//g')"/"
DestFile=$5
runInstaller="${7:-"N"}"
appToRun=$8
fileExtension=${DestFile:e}

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
    echo "$(/bin/date '+%Y-%m-%d %H:%M:%S'): ${1}" | tee -a "${LOG_FILE}" 1>&2
}

####################################################################################################
#
# Main Script
#
####################################################################################################

logMe "Retrieve file $DestFile from $urlPath"
/usr/bin/curl --silent -o "/tmp/${DestFile}" "${urlPath}${DestFile}"
if [[ $? -gt 0 ]]; then
    logMe "An error has occurred while downloading the file"
    exit 1
fi
logMe "Successful download...proceeding"

# if they opted to not run the installer, then exit
[[ $runInstaller == 'N' ]] && exit 0

# If the file is a .pkg then run the installer
logMe "Running the installer located at /tmp/${DestFile}"
if [[ $fileExtension == 'pkg' ]]; then
    installer -pkg "/tmp/${DestFile}" -target "${DestPath}"
fi
# run the file if requested
[[ ! -z "${appToRun}" ]] && logMe "Launching Application: ${appToRun}" ; /usr/bin/open "${appToRun}"
exit 0
