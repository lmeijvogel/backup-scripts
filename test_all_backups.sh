#!/bin/bash
echo -n "Testing energie backup file for today's date..."
last_insert_was_today=$(grep "INSERT INTO" /data/user_data/energie_dump.sql \
  | tail -n 1 \
  | ruby -r date  -e 'date = Date.parse($stdin.read.split("),").last.split(",")[1]); puts (date == Date.today || date == Date.today - 1)')

if [[ "$last_insert_was_today" == "true" ]]; then
  echo " OK"
else
  echo
  echo "!!!! ERROR: Energie backup file is outdated!"
  exit 1
fi

echo -n "Testing borg backup for most recent photos and random file integrity..."
export BACKEND=borg
borg_output=$(./test_backup.rb --test)

if [[ "$?" == "0" ]]; then
  echo " OK"
else
  echo
  echo "!!!! ERROR: Borg backup contains mismatches or is outdated"
  echo $borg_output
  exit 1
fi

echo -n "Testing B2 backup for most recent photos and random file integrity..."
export BACKEND=b2
b2_output=$(./test_backup.rb --test)

if [[ "$?" == "0" ]]; then
  echo " OK"
else
  echo
  echo "!!!! ERROR: B2 backup contains mismatches or is outdated"
  echo $borg_output
  exit 1
fi
