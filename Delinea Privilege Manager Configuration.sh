#!/bin/bash

/bin/mkdir -p /Library/Application\ Support/Delinea/Agent/

/bin/cat << EOF > /Library/Application\ Support/Delinea/Agent/agentconfig.json
{
      "tmsBaseUrl": "https://gianteagleinc.privilegemanagercloud.com/Tms/",
      "installCode": "W7EN-NO4H-6GG0",
      "loginProcessingDelayS": 30, 
      "validateServerCertificate": 0
}
EOF
