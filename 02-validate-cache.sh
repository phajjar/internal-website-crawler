#!/bin/bash

#set -euo pipefail

# This script will loop through all the cache files and attempt to browse to the url contained within each.
# If the URL comes up 404 then the cache file is deleted.

# Make sure only one instance of this is running.
LOCKFILE="/tmp/02-validate-cache.lock"
exec 602>"$LOCKFILE"
flock -n 602 || {
	echo "An instance of this script is already running." 
	logger "02-validate-cache.sh - An instance of this script is already running."
	exit 2
}

CACHEDIR="crawler-cache"
# Unlike other scripts, the CACHEDIR must *not* end in a forward slash.
if [ ${CACHEDIR: -1} == '/' ]; then
	echo "CACHEDIR variable must end in a forward slash."
exit 3
fi

if [ -d "$CACHEDIR" ]; then
    :
else
    echo "$CACHEDIR doesn't exist."
    exit 4
fi

# Initialize Logging
CRAWL_LOG="02-validate-cache.log"
rm -f $CRAWL_LOG

# Initialize array of files to be deleted.  Do not delete files while we loop.
FILES_TO_DELETE=()

for FILE in "$CACHEDIR"/*; do
	# Process files only.
	[[ -f "$FILE" ]] || continue
	printf "\nProcessing file [%s]\n" $FILE >> $CRAWL_LOG
	URL=$(jq -r '.url' $FILE)
	printf "URL is [%s]\n" $URL >> $CRAWL_LOG
	# -f fail silently on server errors.
	# -s silent mode
	# -L if the URL hasm oved, curl retries with the new location
	# -o write output to file instead of stdout
	if curl -f -s -L -o /dev/null "$URL"; then
		# Do nothing on success
		:
	else
		# Add file path to files to be deleted.  Also it is ill-advised to delete files
		# in the same set of files we're looping though.
		FILES_TO_DELETE+=("$FILE")
		echo "Got non-2xx on [$URL].  Need to delete [$FILE]" >> $CRAWL_LOG
	fi
done

#echo "${FILES_TO_DELETE[@]}" >> $CRAWL_LOG

echo "Need to delete ${#FILES_TO_DELETE[@]} cache items." >> $CRAWL_LOG

for file_to_delete in "${FILES_TO_DELETE[@]}"
do
	echo "Deleting [$file_to_delete]." >> $CRAWL_LOG
	rm -f $file_to_delete
done

# $SECONDS is a special bash variable which times how long the script has run.
logger "02-validate-cache.sh - Ran for $SECONDS seconds."
echo "Ran for $SECONDS seconds."
echo "Ran for $SECONDS seconds." >> $CRAWL_LOG
exit 0
