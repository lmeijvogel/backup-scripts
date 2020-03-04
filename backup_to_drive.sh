. ./.env

export DUPLICACY_EXTERNAL_DRIVE_PASSWORD

duplicacy -log backup -storage external_drive
# duplicacy -log backup -dry-run -storage external_drive
