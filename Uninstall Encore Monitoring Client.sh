#!/bin/bash
if [[ -e /Library/MonitoringClient/RunClient ]]; then
	/Library/MonitoringClient/RunClient -F --remove
fi
exit 0
