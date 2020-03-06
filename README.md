# MSP360-CloudBerry-Backup-Report

## What This Does

Throw this script in your crontab and get easy-to-understand reports from CloudBerry/MSP360 about all of your backups. No need to log into mspbackups.com and manually check your backups like an animal anymore.
You'll know what backup plans failed, what succeeded, and what needs attention (warning). Reports are sent to a Telegram group of your choosing (you need to make a Telegram bot first)

## Example Output
This is a (redacted) Telegram message received from this script:

```
.:: SUMMARY ::.
----------------------------------------
There are 9 plans in good standing
There are 1 plans in BAD standing.

.:: FAILED PLANS ::.
----------------------------------------
Company Name: ABC Company, LLC
Computer Name: XYZ-PC
Plan Name: Consistency check plan for Cloudberry
Last Run: 2020-03-02 @ 02:00:01 (108 hours ago)
Plan Type: ConsistencyCheck
Plan Status: Error

.:: WARNING BACKUPS ::.
----------------------------------------
FOO-SERVER (Foobar, Inc)
   - 22054 files scanned
   - 32 files to backup
   - 30 files copied
   - 2 files failed
```

## Disclaimer

This script was built to meet the needs of my business, [BoPag Computer Services, LLC](https://bopag.com/). You must understand that multiple assumptions are made in this script (only one daily file backup per computer, failed restores are ignored, etc), so you will likely need to modify this script to fit your needs. Pull requests are welcome, of course.
