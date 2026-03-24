#!/bin/zsh
CiscoApp="/opt/cisco/secureclient/bin/vpn"
results="Error"
if [[ -e "${CiscoApp}" ]]; then
	results=$( ${CiscoApp} stats | grep "Client Address (IPv4)" | awk -F ":" '{print $2}' | xargs)
	[[ "${results}" == "Not Available" ]] && results="Idle"
fi
echo $results
