#!/bin/bash

#set -euo pipefail

# Make sure only one instance of this is running.
LOCKFILE="/tmp/03-search-crawler.lock"
exec 603>"$LOCKFILE"
flock -n 603 || {
	echo "An instance of this script is already running." 
	logger "03-search-crawler.sh - An instance of this script is already running."
	exit 2
}
	
OUTFILE="url-list.txt"
MAXCONTENTSIZE=102400
CACHEDIR="crawler-cache/"
if [ ${CACHEDIR: -1} != '/' ]; then
	echo "CACHEDIR variable must end in a forward slash."
	exit 3
fi

if [ ! -f $OUTFILE ]; then
	echo $OUTFILE" does not exist.  Run the crawler first."
	exit 1
fi

OUTJSON="index.json"
rm -f $OUTJSON
echo "[" > $OUTJSON

# Initialize Logging
CRAWL_LOG="03-crawler.log"
rm -f $CRAWL_LOG

counter=0
FIRST=true

#while IFS= read -r wholeLine && (( counter < 10 )); do
while IFS= read -r wholeLine; do
	echo "" >> $CRAWL_LOG   
	echo "File No. $counter" >> $CRAWL_LOG

	#echo $wholeLine
	line=`echo $wholeLine | awk -F'|' '{ print $2 }'`
	fileMdatetime=`echo $wholeLine | awk -F'|' '{ print $1 }'`
	echo "URL is [$line]" >> $CRAWL_LOG
	echo "MDateTime is [$fileMdatetime]" >> $CRAWL_LOG

	id=$(echo -n "$line" | sha256sum | awk '{print $1}')
	echo "Id is [$id]" >> $CRAWL_LOG

	CACHEFILEPATH="$CACHEDIR""$id"".txt"

	# If the cache file exists and it contains the fileMdatetime value, just grab the JSON from there and use it.
	# Otherwise, fully process the file.

	CACHEFILEEXISTS=false
	CACHEFILEMATCHES=false
	if [ -e "$CACHEFILEPATH" ]; then
		#echo "Cache file [$CACHEFILEPATH] exists."
		CACHEFILEEXISTS=true
	fi
	if [ "$CACHEFILEEXISTS" == true ]; then
		grep -q -F "$fileMdatetime" "$CACHEFILEPATH" 
		if [ 0 == $? ]; then
			CACHEFILEMATCHES=true
		fi
		#echo "grep retval is [$CACHEFILEMATCHES]."
	fi

	if [ "$CACHEFILEEXISTS" == true ] && [ "$CACHEFILEMATCHES" == true ]; then
		echo "Cache file for [$line] exists and contains current modification datetime.  Will use that instead." >> $CRAWL_LOG
		if [ "$FIRST" = true ]; then
			FIRST=false
		else
			echo "," >> "$OUTJSON"
		fi
		cat $CACHEFILEPATH >> "$OUTJSON"
	else
		echo "Cache file for [$line] either does not exist or it has been updated.  Will need to process." >> $CRAWL_LOG

		TMP_HTML_FILE=$(mktemp)
		WGET_OUTPUT=$(mktemp)
		WGET_ERROR=$(mktemp)
		wget -O $TMP_HTML_FILE $line 1>$WGET_OUTPUT 2>$WGET_ERROR
		WGET_STATUS=$?
		echo "  wget status is [$WGET_STATUS]" >> $CRAWL_LOG
		if [ $WGET_STATUS ]; then
			echo "Need to process output." >> $CRAWL_LOG
			#head -n 10 $TMP_HTML_FILE
			extension="${line##*.}"
			extension=${extension,,}
			#echo "File extension is [$extension]"

			title=""
			content=""
                	host="${line#*://}"
                	host="${host%%/*}"
                	echo "Host is [$host]" >> $CRAWL_LOG
                	url=$line
                	site=$host

			# Create another temporary file for the main section of the page.
			TMP_HTML_MAIN_ONLY=$(mktemp)

			if [ "html" == $extension ]; then
				echo "Processing [$line] as html file." >> $CRAWL_LOG
				title=$(grep -i -m1 '<title[^>]*>' "$TMP_HTML_FILE" \
					| sed -E 's@.*<title[^>]*>(.*?)</title>.*@\1@i' \
					| tr -d '\r\n' \
					|| true )
				if [[ -z "$title" ]]; then
					title=$line
				fi
				echo "Title is [$title]" >> $CRAWL_LOG

				sed -n '/<main[ >]/,/<\/main>/p' $TMP_HTML_FILE > $TMP_HTML_MAIN_ONLY
				content=$(html2text $TMP_HTML_MAIN_ONLY | tr "\r\n" " " | tr "\n" " ")
				rm -f $TMP_HTML_MAIN_ONLY
				echo "Content is [${content:0:100}]" >> $CRAWL_LOG
			elif [ "pdf" == $extension ]; then
				echo "Processing [$line] as a PDF file." >> $CRAWL_LOG
				title=`basename "$line"`
				content=$(pdftotext "$TMP_HTML_FILE" - 2>> $CRAWL_LOG | tr "\r\n" " " | tr "\n" " ")
			fi # if [ "html" == $extension ]; then

			# Some pages are huge.  Cut them down
			content=${content:0:$MAXCONTENTSIZE}

			# Control characters will break XML.  Get rid of them.
			content=$(printf '%s' "$content" | tr '\000-\037' ' ')

			json=$(jq -n \
				--arg id "$id" \
				--arg title "$title" \
				--arg url "$url" \
				--arg site "$site" \
				--arg content "$content" \
				--arg extension "$extension" \
				--arg fileMdatetime "$fileMdatetime" \
				'{ id:$id, title:$title, url:$url, site:$site, content:$content, extension:$extension, fileMdatetime:$fileMdatetime }' 2>> $CRAWL_LOG)
			JQ_RETURN_VALUE=$?
			echo "Total content length is [${#content}]" >> $CRAWL_LOG
			echo "jq return value is [$JQ_RETURN_VALUE]" >> $CRAWL_LOG
			if [ $JQ_RETURN_VALUE ]; then
				if [ "$FIRST" = true ]; then
					FIRST=false
				else
					echo "," >> "$OUTJSON"
				fi
				echo "$json" >> "$OUTJSON"
				echo "$json" > $CACHEFILEPATH
			
			fi # if [ $JQ_RETURN_VALUE ]; then
		else # if [ $WGET_STATUS ]; then
			echo "Got an error:" >> $CRAWL_LOG
			cat $WGET_OUTPUT >> $CRAWL_LOG
			echo >> $CRAWL_LOG
			cat $WGET_ERROR >> $CRAWL_LOG
		fi   # if [ $WGET_STATUS ]; then

		# Clean up temporary files.
		rm -f $WGET_OUTPUT
		rm -f $WGET_ERROR
		rm -f $TMP_HTML_FILE
		rm -f $TMP_HTML_MAIN_ONLY
	fi # if [ "$CACHEFILEEXISTS" == true ] && [ "$CACHEFILEMATCHES" == true ]; then
	counter=$((counter+1))
done < "$OUTFILE"

echo ']' >> "$OUTJSON"

# Validate the file
jq empty $OUTJSON 2>> $CRAWL_LOG
JQ_RETURN_VALUE=$?
if [ $JQ_RETURN_VALUE ]; then
	echo "JSON File is valid."
	echo "JSON File is valid." >> $CRAWL_LOG
else
	echo "JSON File has errors - See log."
	echo "JSON File has errors - See above for more information." >> $CRAWL_LOG
fi

# $SECONDS is a special bash variable which times how long the script has run.
logger "03-search-crawler.sh - Processed $counter URLs in $SECONDS seconds."
echo "Processed $counter URLs in $SECONDS seconds."
echo "Processed $counter URLs in $SECONDS seconds." >> $CRAWL_LOG
exit 0
