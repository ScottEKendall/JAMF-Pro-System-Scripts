 file_Array=(
 "/Applications/Adobe*"
 "/Applications/Utilities/Adobe*"
 "/Library/Application\ Support/Adobe"
 "/Library/Preferences/com.adobe.*"
 "/Library/PrivilegedHelperTools/com.adobe.*"
 "/private/var/db/receipts/com.adobe.*"
 "~/Library/Application\ Support/Adobe*"
 "~/Library/Application\ Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.adobe*"
 "~/Library/Application\ Support/CrashReporter/Adobe*"
 "~/Library/Caches/Adobe"
 "~/Library/Caches/com.Adobe.*"
 "~/Library/Caches/com.adobe.*"
 "~/Library/Cookies/com.adobe.*"
 "~/Library/Logs/Adobe*"
 "~/Library/PhotoshopCrashes"
 "~/Library/Preferences/Adobe*"
 "~/Library/Preferences/com.adobe.*"
 "~/Library/Preferences/Macromedia*"
 "~/Library/Saved\ Application\ State/com.adobe.*"
 )

 for i in "${file_Array[@]}"; do
    [[ ! -e $i ]] && continue
    echo "Deleting file $i"
    /bin/rm -rf "$i"
  fi
done
