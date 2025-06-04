#!/bin/zsh
#
# Purpose: donwload file via curl to users machine
#
# PARMS: $4 - macOS Version to download (ie 15.4)
#        $5 - destination location
#        $6 - run installer after download (Y/N)
#        $7 - Install file to run 
#
LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
USER_DIR=$( dscl . -read /Users/${LOGGED_IN_USER} NFSHomeDirectory | awk '{ print $2 }' )

SUPPORT_DIR="/Library/Application Support/GiantEagle"
LOG_STAMP=$(echo $(/bin/date +%Y%m%d))
LOG_FILE="${SUPPORT_DIR}/Download_Internet_File.log"

##################################################
#
# Passed in variables
# 
#################################################

mistVersion=$4
destPath="${5:-"/Applications"}"
runInstaller="${6:-"N"}"
InstallFile=$7
appName="Install %NAME% ${mistVersion}.app"

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

####################################################################################################
#
# Main Script
#
####################################################################################################

logMe "Downloading application MacOS Install v${mistVersion}"
/usr/local/bin/mist download installer "${mistVersion}" application -q -o "${destPath}" --application-name "Install %NAME% %VERSION%.app"
echo $?
if [[ $? -gt 0 ]]; then
    logMe "An error has occured while downloading the file"
    exit 1
fi
logMe "Successfull download..."
logMe "Clearing the Quarantine flag"
xattr -d -r com.apple.quarantine "${destPath}/${InstallFile}" 2> /dev/null
# Perform the new Gatekeeper scan if on Sonoma or higher
logMe "Performing Gatekeeper Scan"
gktool scan "${destPath}/${InstallFile}"

# run the file if requested
[[ "${runInstaller:l}" == "y" ]] && logMe "Launching Application: ${destPath}/${InstallFile}" ; /usr/bin/open "${destPath}/${InstallFile}"
exit 0
