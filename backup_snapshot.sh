#!/bin/bash
INSTANCE_ID=$(curl "http://169.254.169.254/latest/meta-data/instance-id")

LOGFILE="/var/log/regular_snapshot.log"
MAX_NO_OF_LINES="500"

RETENTION_TIME="30"

INSTANCE_ID=$(wget -q -O- http://169.254.169.254/latest/meta-data/instance-id)

#To get the region from the availability-zone we form a regex group containing just the digits
#representing the region and replace the whole AZ with that regex group
REGION=$(wget -q -O- http://169.254.169.254/latest/meta-data/placement/availability-zone | \
	sed -e 's/\([1-9]\).$/\1/g')

RETENTION_TIME_IN_SECONDS=$(date +%s --date "$RETENTION_TIME seconds ago")


# Function Declarations #
# Function: Setup LOGFILE and redirect stdout/stderr.
log_setup() {
    # Check if LOGFILE exists and is writable.
    ( [ -e "$LOGFILE" ] || touch "$LOGFILE" ) && [ ! -w "$LOGFILE" ] \
	&& echo "ERROR: Cannot write to $LOGFILE. Check permissions or sudo access." && exit 1

    TMPLOG=$(tail -n $MAX_NO_OF_LINES $LOGFILE 2>>errors.log) && echo "${TMPLOG}" > $LOGFILE
    exec > >(tee -a $LOGFILE)
    exec 2>&1
}

# Function: Log an event.
log() {
    echo "[$(date +"%Y-%m-%d"+"%T")]: $*"
}

# Function: SNAPSHOT all volumes attached to this instance.
snapshot_volumes() {
	for VOLUME_ID in "${VOLUME_LIST[@]}; do
		log "Volume ID is $VOLUME_ID"

		# Get the attched device name to add to the description so we can easily tell which volume this is.
		DEVICE_NAME=$(aws ec2 describe-volumes \
			--region $REGION \
			--volume-ids $VOLUME_ID \
			--query 'Volumes[0].{Devices:Attachments[0].Device}' \
			--output text)

		# Take a SNAPSHOT of the current volume, and capture the resulting SNAPSHOT ID
		SNAPSHOT_DESCRIPTION="$(hostname)-$DEVICE_NAME-backup-$(date +%Y-%m-%d)"
		SNAPSHOT_ID=$(aws ec2 create-snapshot \
				--region $REGION \
				--description $SNAPSHOT_DESCRIPTION \
				--volume-id $VOLUME_ID \
				--query SnapshotId \
				--output text)
		log "New SNAPSHOT is $SNAPSHOT_ID"
	done
}

## Execute functions and commands##
log_setup

VOLUME_LIST=( $(aws ec2 describe-volumes \
		--region $REGION \
		--filters Name=attachment.instance-id,Values=$INSTANCE_ID \
		--query Volumes[].VolumeId \
		--output text) )

snapshot_volumes
