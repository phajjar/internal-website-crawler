# internal-website-crawler
A series of shell scripts which create a list of website URLs based on the file structure of a site.  The scripts then browse each URL, extract the content, save these as JSON files, and then merge these files into a larger JSON file which can be used as the basis for a search engine. 

These scripts demonstrate the use of advisory file locking, automatic failure on error, calls to external commands and the reading of return codes and other other information.
