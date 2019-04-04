#!/usr/bin/env /bin/bash

# Ensure that the environment is loaded, otherwise, rubygems won't load
. ~/.bashrc

BACKUP_STATUS_FILE=./.backup_status
BACKUP_ERROR_LOG_FILE=./.backup_errors

echo -n "Testing energie backup file for today's date..."
last_insert_was_today=$(grep "INSERT INTO" /data/user_data/energie_dump.sql \
  | tail -n 1 \
  | ruby -r date  -e 'date = Date.parse($stdin.read.split("),").last.split(",")[1]); puts (date == Date.today || date == Date.today - 1)')

RUN_DATE=`date --iso-8601=seconds`
echo "date: $RUN_DATE" > $BACKUP_STATUS_FILE
echo "date: $RUN_DATE" > $BACKUP_ERROR_LOG_FILE

if [[ "$last_insert_was_today" == "true" ]]; then
  echo " OK"
  echo "energy_download: ok" >> $BACKUP_STATUS_FILE
else
  echo
  echo "!!!! ERROR: Energie backup file is outdated!"
  echo "energy_download: error" >> $BACKUP_STATUS_FILE
  exit 1
fi

echo -n "Testing borg backup for most recent photos and random file integrity..."
export BACKEND=borg
borg_output=$(./test_backup.rb --test)

BORG_STATUS=$?
echo -n "borg_status: " >> $BACKUP_STATUS_FILE

if [[ "$BORG_STATUS" == "0" ]]; then
  echo "OK"
  echo "ok" >> $BACKUP_STATUS_FILE
else
  echo
  echo "!!!! ERROR: Borg backup contains mismatches or is outdated"
  echo $borg_output
  echo "error" >> $BACKUP_STATUS_FILE
  echo "Borg errors:" > $BACKUP_ERROR_LOG_FILE
  echo $borg_output >> $BACKUP_ERROR_LOG_FILE
  exit 1
fi

echo -n "Testing B2 backup for most recent photos and random file integrity..."
export BACKEND=b2
b2_output=$(./test_backup.rb --test)

B2_STATUS=$?

echo -n "b2_status: " >> $BACKUP_STATUS_FILE

if [[ "$B2_STATUS" == "0" ]]; then
  echo "OK"
  echo "ok" >> $BACKUP_STATUS_FILE
else
  echo
  echo "!!!! ERROR: B2 backup contains mismatches or is outdated"
  echo $b2_output
  echo "error" >> $BACKUP_STATUS_FILE
  echo "B2 errors:" > $BACKUP_ERROR_LOG_FILE
  echo $b2_output >> $BACKUP_ERROR_LOG_FILE
  exit 1
fi
