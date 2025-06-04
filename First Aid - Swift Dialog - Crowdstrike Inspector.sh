#!/bin/zsh

####################################################################################################
#
# Variables
#
####################################################################################################


export PATH=/usr/bin:/bin:/usr/sbin:/sbin
LOGGED_IN_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
USER_DIR=$( dscl . -read /Users/${LOGGED_IN_USER} NFSHomeDirectory | awk '{ print $2 }' )
SW_DIALOG="/usr/local/bin/dialog"

anticipationDuration="${6:-"3"}"

SUPPORT_DIR="/Library/Application Support/GiantEagle"
OVERLAY_ICON="/Applications/Falcon.app"
SD_BANNER_IMAGE="${SUPPORT_DIR}/SupportFiles/GE_SD_BannerImage.png"

LOG_DIR="${SUPPORT_DIR}/logs"
LOG_FILE="${LOG_DIR}/AppDelete.log"
LOG_STAMP=$(echo $(/bin/date +%Y%m%d))

ICON_FILES="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/"

BANNER_TEXT_PADDING="      "
SD_WINDOW_TITLE="${BANNER_TEXT_PADDING}Crowdstrike Inspector"
DIALOG_COMMAND_FILE=$( mktemp /var/tmp/FalconInspector.XXXX )
chmod 644 ${DIALOG_COMMAND_FILE}
# Swift Dialog version requirements

[[ -e "${SW_DIALOG}" ]] && SD_VERSION=$( ${SW_DIALOG} --version) || SD_VERSION="0.0.0"
MIN_SD_REQUIRED_VERSION="2.3.3"
DIALOG_INSTALL_POLICY="install_SwiftDialog"
SUPPORT_FILE_INSTALL_POLICY="install_SymFiles"
FALCON_PATH="/Applications/Falcon.app/Contents/Resources/falconctl"

#icon="https://ics.services.jamfcloud.com/icon/hash_c9f81b098ecb0a2d527dd9fe464484892f1df5990d439fa680d54362023a5b5a"


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
	if [[ ! -d "${LOG_DIR}" ]]; then
		/bin/mkdir -p "${LOG_DIR}"
		/bin/chmod 755 "${LOG_DIR}"
	fi

	# If the log file does not exist - create it and set the permissions
	if [[ ! -f "${LOG_FILE}" ]]; then
		/usr/bin/touch "${LOG_FILE}"
		/bin/chmod 644 "${LOG_FILE}"
	fi
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
    echo "$(/bin/date '+%Y%m%d %H:%M:%S'): ${1}
" | tee -a "${LOG_FILE}"
}

function check_swift_dialog_install ()
{
    # Check to make sure that Swift Dialog is installed and functioning correctly
    # Will install process if missing or corrupted
    #
    # RETURN: None

    logMe "Ensuring that swiftDialog version is installed..."
    if [[ ! -x "${SW_DIALOG}" ]]; then
        logMe "Swift Dialog is missing or corrupted - Installing from JAMF"
        install_swift_dialog
        SD_VERSION=$( ${SW_DIALOG} --version)        
    fi

    if ! is-at-least "${MIN_SD_REQUIRED_VERSION}" "${SD_VERSION}"; then
        logMe "Swift Dialog is outdated - Installing version '${MIN_SD_REQUIRED_VERSION}' from JAMF..."
        install_swift_dialog
    else    
        logMe "Swift Dialog is currently running: ${SD_VERSION}"
    fi
}

function install_swift_dialog ()
{
    # Install Swift dialog From JAMF
    # PARMS Expected: DIALOG_INSTALL_POLICY - policy trigger from JAMF
    #
    # RETURN: None

	/usr/local/bin/jamf policy -trigger ${DIALOG_INSTALL_POLICY}
}

function check_support_files ()
{
    [[ -e "${SD_BANNER_IMAGE}" ]] && /usr/local/bin/jamf policy -trigger ${SUPPORT_FILE_INSTALL_POLICY}
}

function create_welcome_msg ()
{
     MainDialogBody="${SW_DIALOG} \
        --bannerimage \"${SD_BANNER_IMAGE}\" \
        --bannertitle \"${SD_WINDOW_TITLE}\" \
        --icon \"${OVERLAY_ICON}\" --iconsize 100 \
        --message \"This script analyzes the installation of CrowdStrike Falcon then reports the findings in this window.  

Please wait …\" \
        --iconsize 135 \
        --messagefont name=Arial,size=17 \
        --button1disabled \
        --progress \
        --progresstext \"$welcomeProgressText\" \
        --button1text \"Wait\" \
        --height 400 \
        --width 650 \
        --moveable \
        --commandfile \"$DIALOG_COMMAND_FILE\" "
}

function cleanup_and_exit ()
{
        logMe "Quitting …"
    updateWelcomeDialog "quit: "
	[[ -f ${JSON_OPTIONS} ]] && /bin/rm -rf ${JSON_OPTIONS}
	[[ -f ${TMP_FILE_STORAGE} ]] && /bin/rm -rf ${TMP_FILE_STORAGE}
    [[ -f ${DIALOG_COMMAND_FILE} ]] && /bin/rm -rf ${DIALOG_COMMAND_FILE}
	exit 0
}

function update_display_list ()
{
    # setopt -s nocasematch
    # This function updates the Swift Dialog list display with easy to implement parameter passing...
    # The Swift Dialog native structure is very strict with the command structure...this routine makes
    # it easier to implement
    #
    # Param list
    #
    # $1 - Action to be done ("Create", "Add", "Change", "Clear", "Info", "Show", "Done", "Update" "message")
    # ${2} - Affected item (2nd field in JSON Blob listitem entry)
    # ${3} - Icon status "wait, success, fail, error, pending or progress"
    # ${4} - Status Text
    # ${5} - Progress Text (shown below progress bar)
    # ${6} - Progress amount
            # increment - increments the progress by one
            # reset - resets the progress bar to 0
            # complete - maxes out the progress bar
            # If an integer value is sent, this will move the progress bar to that value of steps
    # the GLOB :l converts any inconing parameter into lowercase

    
    case "${1:l}" in
 
        "create" | "show" )
 
            # Display the Dialog prompt
            eval "${DYNAMIC_DIALOG_BASE_STRING}"
            ;;
     
        "add" )
  
            # Add an item to the list
            #
            # $2 name of item
            # $3 Icon status "wait, success, fail, error, pending or progress"
            # $4 Optional status text
  
            /bin/echo "listitem: add, title: ${2}, status: ${3}, statustext: ${4}" >> "${DIALOG_COMMAND_FILE}"
            ;;

        "buttonaction" )

            # Change button 1 action
            /bin/echo 'button1action: "'${2}'"' >> "${DIALOG_COMMAND_FILE}"
            ;;
  
        "buttonchange" )

            # change text of button 1
            /bin/echo "button1text: ${2}" >> "${DIALOG_COMMAND_FILE}"
            ;;

        "buttondisable" )

            # disable button 1
            /bin/echo "button1: disable" >> "${DIALOG_COMMAND_FILE}"
            ;;

        "buttonenable" )

            # Enable button 1
            /bin/echo "button1: enable" >> "${DIALOG_COMMAND_FILE}"
            ;;

        "change" )
          
            # Change the listitem Status
            # Increment the progress bar by static amount ($6)
            # Display the progress bar text ($5)
            if [[ ! -z $2 ]]; then 
                /bin/echo "listitem: title: ${2}, status: ${3}, statustext: ${4}" >> "${DIALOG_COMMAND_FILE}"
            fi
            if [[ ! -z $5 ]]; then
                /bin/echo "progresstext: $5" >> "${DIALOG_COMMAND_FILE}"
                /bin/echo "progress: $6" >> "${DIALOG_COMMAND_FILE}"
            fi
            ;;
  
        "clear" )
  
            # Clear the list and show an optional message  
            /bin/echo "list: clear" >> "${DIALOG_COMMAND_FILE}"
            /bin/echo "message: ${2}" >> "${DIALOG_COMMAND_FILE}"
            ;;
  
        "delete" )
  
            # Delete item from list  
            /bin/echo "listitem: delete, title: ${2}" >> "${DIALOG_COMMAND_FILE}"
            ;;
 
        "destroy" )
     
            # Kill the progress bar and clean up
            /bin/echo "quit:" >> "${DIALOG_COMMAND_FILE}"
            ;;

        "message" )
            # Change the displayed message
            /bin/echo "message: ${4}" >> "${DIALOG_COMMAND_FILE}"
            ;;
 
        "done" )
          
            # Complete the progress bar and clean up  
            /bin/echo "progress: complete" >> "${DIALOG_COMMAND_FILE}"
            /bin/echo "progresstext: $5" >> "${DIALOG_COMMAND_FILE}"
            ;;
          
        "icon" )
  
            # set / clear the icon, pass <nil> if you want to clear the icon  
            [[ -z ${2} ]] && /bin/echo "icon: none" >> "${DIALOG_COMMAND_FILE}" || /bin/echo "icon: ${2}" >> $"${DIALOG_COMMAND_FILE}"
            ;;
  
  
        "image" )
  
            # Display an image and show an optional message  
            /bin/echo "image: ${2}" >> "${DIALOG_COMMAND_FILE}"
            [[ ! -z ${3} ]] && /bin/echo "progresstext: $5" >> "${DIALOG_COMMAND_FILE}"
            ;;
  
        "infobox" )
  
            # Show text message  
            /bin/echo "infobox: ${2}" >> "${DIALOG_COMMAND_FILE}"
            ;;

        "infotext" )
  
            # Show text message  
            /bin/echo "infotext: ${2}" >> "${DIALOG_COMMAND_FILE}"
            ;;
  
        "show" )
  
            # Activate the dialog box
            /bin/echo "activate:" >> $"${DIALOG_COMMAND_FILE}"
            ;;
  
        "title" )
  
            # Set / Clear the title, pass <nil> to clear the title
            [[ -z ${2} ]] && /bin/echo "title: none:" >> "${DIALOG_COMMAND_FILE}" || /bin/echo "title: ${2}" >> "${DIALOG_COMMAND_FILE}"
            ;;
  
        "progress" )
  
            # Increment the progress bar by static amount ($6)
            # Display the progress bar text ($5)
            /bin/echo "progress: ${6}" >> "${DIALOG_COMMAND_FILE}"
            /bin/echo "progresstext: ${5}" >> "${DIALOG_COMMAND_FILE}"
            ;;
  
    esac
}

function check_falcon_install ()
{

    if [[ -e ${FALCON_PATH} ]]; then
        logMe "CrowdStrike Falcon installed; proceeding …"
    else
        logMe "CrowdStrike Falcon not installed; exiting"
        cleanup_and_exit
    fi
}

function get_falcon_stats ()
{
    logMe "Create Welcome Dialog …"

    eval "${MainDialogBody}" & sleep 0.3


    update_display_list "progress" "" "" "" "Inspecting..." "5"

    sleep "${anticipationDuration}"

    SECONDS="0"

    # CrowdStrike Falcon Inspection: Installation

    update_display_list "progress" "" "" "" "Installation..." "18"

    # CrowdStrike Falcon Inspection: Version

    falconVersion=$( ${FALCON_PATH} stats | awk '/version/ {print $2}' )
    update_display_list "progresss" "" "" "" "Version..." "36" 

    # CrowdStrike Falcon Inspection: System Extension List

    systemExtensionTest=$( systemextensionsctl list | awk '/com.crowdstrike.falcon.Agent/ {print $7,$8}' | wc -l )
    [[ "${systemExtensionTest}" -gt 0 ]] && systemExtensionStatus="Loaded" || systemExtensionStatus="Likely **not** running"
    update_display_list "progress" "" "" "" "System Extension..." "54" 

    # CrowdStrike Falcon Inspection: Agent ID

    falconAgentID=$( ${FALCON_PATH} stats | awk '/agentID/ {print $2}' | tr '[:upper:]' '[:lower:]' | sed 's/\-//g' )
    update_display_list "progress" "" "" "" "Agent ID..." "72"

    # CrowdStrike Falcon Inspection: Heartbeats

    falconHeartbeats6=$( ${FALCON_PATH} stats | awk '/SensorHeartbeatMacV4/ {print $4,$5,$6,$7,$8}' | sed 's/ /\ | /g' )
    update_display_list "progress" "" "" "" "Heartbeats..." "90"

    # Capture results to log
    logMe "Results for ${loggedInUser}"
    logMe "Installation Status: Installed"
    logMe "Version: ${falconVersion}"
    logMe "System Extension: ${systemExtensionStatus}"
    logMe "Agent ID: ${falconAgentID}"
    logMe "Heartbeats: ${falconHeartbeats6}"
    logMe "Elapsed Time: $(printf '%dh:%dm:%ds
' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)))"

    # Display results to user
    timestamp="$( date '+%Y-%m-%d-%H:%M:%S' )"
    update_display_list "progress" "" "" "" "Complete!" "100"
    update_display_list "message" "" "" "message: **Results for ${LOGGED_IN_USER} on ${timestamp}**<br><br>**Installation Status:** Installed<br>**Version:** ${falconVersion}<br>**System Extension:** ${systemExtensionStatus}<br>**Agent ID:** ${falconAgentID}<br>**Heartbeats:** ${falconHeartbeats6}"
    sleep "${anticipationDuration}"
    update_display_list "buttonchange" "Done"
    update_display_list "buttonenable"
    #updateWelcomeDialog "progresstext: Elapsed Time: $(printf '%dh:%dm:%ds
' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)))"

}
####################################################################################################
#
# Main Script
#
####################################################################################################

autoload 'is-at-least'

check_swift_dialog_install
check_support_files
check_falcon_install
create_welcome_msg
get_falcon_stats
exit 0
