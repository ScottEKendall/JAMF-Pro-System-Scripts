#!/bin/zsh
falconApp="/opt/cisco/anyconnect/bin/vpn"
results="Error"
if [[ -e "${falconApp}" ]]; then
	results=$( ${falconApp} stats | grep 'Network Status:' | awk -F ":" '{print $2}' | xargs)
	[[ "${results}" == "Available" ]] && results="Running"
fi
echo $results
