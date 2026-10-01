#!/bin/bash

# Make sure only one instance of this is running.
LOCKFILE="/tmp/00-prepare-site-index.lock"
exec 600>"$LOCKFILE"
flock -n 600 || {
        echo "An instance of this script is already running." 
        logger "00-prepare-site-index.sh - An instance of this script is already running."
        exit 2
}

./01-site-mapper.sh
retVal=$?
if [ $retVal ]; then
	./02-validate-cache.sh
	retVal=$?
	if [ $retVal ]; then
		./03-search-crawler.sh
		$retVal=$?
		if [ $retVal ]; then
			: # Do nothing, we're good.
		else
			echo "03-search-crawler.sh failed with error code [$retVal]."
			exit 3
		fi
	else
		echo "02-validate-cache.sh failed with error code [$retVal]."
		exit 4
	fi
else
	echo "01-site-mapper.sh failed with error code [$retVal]."
	exit 5
fi

# $SECONDS is a special bash variable which times how long the script has run.
logger "00-prepare-site-index.sh - Ran for $SECONDS seconds."
echo "Ran for $SECONDS seconds."
#echo "Ran for $SECONDS seconds." >> $CRAWL_LOG
exit 0
