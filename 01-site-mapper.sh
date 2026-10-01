#!/bin/bash

# Quit on error, force variables to be set and die on any command failing.
# This may be too strict but it's a good starting point.
set -euo pipefail

# Make sure only one instance of this is running.
LOCKFILE="/tmp/01-site-mapper.lock"
exec 601>"$LOCKFILE"
flock -n 601 || {
        echo "An instance of this script is already running." 
        logger "01-site-mapper.sh - An instance of this script is already running."
        exit 2
}

# Write the list of URLs to the file below.  Make sure it exists and is empty.
OUTFILE="url-list.txt"
rm -f $OUTFILE
touch $OUTFILE

# Note that there are no commas separating array elements.
SITES=("https://www.example.xyz" "https://info.example.xyz" "https://library.example.xyz")
DIRS=("/var/www/html"            "/var/www/info_html"       "/var/www/library_html")

EXCLUDE_PATTERNS=("/google[A-Za-z0-9]" "/_resources/")
index=0
for webDir in "${DIRS[@]}"
do
	TMP_FILE=$(mktemp)
	site=${SITES[$index]}
	echo "[$webDir] [$site]"
	find $webDir -name "*.html" >> $TMP_FILE
	find $webDir -name "*.pdf" >> $TMP_FILE

	while IFS= read -r line;
	do
		needToSkip=false
		regexCount=${#EXCLUDE_PATTERNS[@]}
		regexIndex=0
		while [ $needToSkip == false ] && [ $regexIndex -lt $regexCount ]; do
			#echo "Found Pattern ["${EXCLUDE_PATTERNS[$regexIndex]}"]"
			#echo "Pattern=[${EXCLUDE_PATTERNS[$regexIndex]}]"
			#echo "Line=[$line]"
			if [[ "$line" =~ ${EXCLUDE_PATTERNS[$regexIndex]} ]]; then
				needToSkip=true
				#echo "  MATCH"
			else
				#echo "  NO MATCH"
				:
			fi
			regexIndex=$((regexIndex+1))
		done
		if [ $needToSkip == true ]; then
			#echo "Skipping line [$line]"
			: # Bash No-Op command.
		else
			filemdatetime=`stat -c %y $line 2>/dev/null`
			statReturnValue=$?
			if [ $statReturnValue ]; then
				#echo "Writing line [$line]"
				echo "$filemdatetime|"${line/${webDir}/${site}} >> $OUTFILE
			fi # if [ $statReturnValue ]; then
		fi
	done < $TMP_FILE
	rm $TMP_FILE

	index=$((index+1))
done

exit 0
