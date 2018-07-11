#!/bin/bash


# NOTES

AWS_ID_SOURCE_ACCOUNT=123456789 ### Live Acoount
AWS_ID_DESTINATION_ACCOUNT=987654321 ### Backup Account

SOURCE_GROUP=Live_Account # AWSCLI profile name
DESTINATION_GROUP=Backups_Account # AWSCLI profile name
DESTINATION_GROUP_REGION=eu-central-1

RDS_DB=("db1" "db2" "db3" "db4")

DATE=$(date --date="7 days ago" +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d-%_H-%M)

DQT='"' # Added double quote AWS Id Account

function CHECK {
if [[ "$?" == "0" ]]
	then
        echo "OK...!!!"
	else
	echo "Error... Please investigate....!!!!"	
fi
}

for DB in ${RDS_DB[*]}; do

	echo "Create $DB Snapshot"
	aws --profile $SOURCE_GROUP rds create-db-snapshot --db-snapshot-identifier $DB-shapshot --db-instance-identifier $DB &> /dev/null
	CHECK
	
	SNAPSHOT_STATUS=""

	while [ "$SNAPSHOT_STATUS" != "available" ]
	do
		sleep 15
		SNAPSHOT_STATUS=$(aws --profile $SOURCE_GROUP rds describe-db-snapshots --db-snapshot-identifier $DB-shapshot | grep "Status" | awk -F '"' '{print $4}')
		if [ "$SNAPSHOT_STATUS" == "" ]; then break ; fi
	done
	
	echo "Share $DB Snapshot across accounts"

	aws --profile $SOURCE_GROUP rds modify-db-snapshot-attribute --db-snapshot-identifier $DB-shapshot --attribute-name restore --values-to-add [$DQT$AWS_ID_SOURCE_ACCOUNT$DQT,$DQT$AWS_ID_DESTINATION_ACCOUNT$DQT] &> /dev/null
	CHECK
	sleep 5

	echo "Restore $DB Shapshot"
	aws rds --profile $DESTINATION_GROUP restore-db-instance-from-db-snapshot --db-instance-identifier $DB --db-snapshot-identifier arn:aws:rds:eu-west-1:$AWS_ID_SOURCE_ACCOUNT:snapshot:$DB-shapshot --db-instance-class db.t2.micro &> /dev/null
	CHECK
	sleep 10

        INSTANCE_STATUS=""

	### echo "Check Instance status"
	while [ "$INSTANCE_STATUS" != "available" ]
	do
		INSTANCE_STATUS=$(aws --profile $DESTINATION_GROUP rds describe-db-instances --db-instance-identifier $DB | grep "DBInstanceStatus" | awk -F '"' '{print $4}')
		sleep 15
		if [ "$INSTANCE_STATUS" == "" ]; then break ; fi
	done

	echo "Copy $DB Shapshot across regions"
	aws --profile $DESTINATION_GROUP --region $DESTINATION_GROUP_REGION rds copy-db-snapshot --source-db-snapshot-identifier arn:aws:rds:eu-west-1:$AWS_ID_SOURCE_ACCOUNT:snapshot:$DB-shapshot --target-db-snapshot-identifier $DB-$TODAY&> /dev/null
	CHECK
	sleep 10

	SNAPSHOT_STATUS=""

	### echo "Check Snapshot status"
	while [ "$SNAPSHOT_STATUS" != "available" ]
	do
		SNAPSHOT_STATUS=$(aws --profile $DESTINATION_GROUP --region $DESTINATION_GROUP_REGION rds describe-db-snapshots --db-snapshot-identifier $DB-$TODAY | grep "Status" | awk -F '"' '{print $4}')
		sleep 15
		if [ "$SNAPSHOT_STATUS" == "" ]; then break ; fi
	done

	echo "Delete RDS $DB Instace"
	aws --profile $DESTINATION_GROUP rds delete-db-instance --db-instance-identifier $DB --skip-final-snapshot &> /dev/null
	CHECK

	echo "Delete RDS $DB Snapshot"
	aws --profile $SOURCE_GROUP rds delete-db-snapshot --db-snapshot-identifier $DB-shapshot &> /dev/null
	CHECK

	### Clean old Snapshots
	SNAPSHOTS=$(aws --profile $DESTINATION_GROUP --region $DESTINATION_GROUP_REGION rds describe-db-snapshots | grep DBSnapshotIdentifier | awk -F '"' '{print $4}' | grep $DATE)
	if [ ! -z "$SNAPSHOTS" ]; then
        for SNAPSHOT in $SNAPSHOTS
        do
        echo "Delere RDS $SNAPSHOT"
		aws --profile $DESTINATION_GROUP --region $DESTINATION_GROUP_REGION rds delete-db-snapshot --db-snapshot-identifier $SNAPSHOT &> /dev/null
		CHECK
        done
	fi
done
