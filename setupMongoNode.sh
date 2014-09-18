#!/bin/bash
# 
# Copyright (c) Microsoft.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#



#
# setupMongoNode.sh : MongoDB Node Configuration Script by Jeff Wilcox
#
# Target Image: OpenLogic CentOS, Azure IaaS VM
#
# A specialized script specific to Microsoft Azure for configuring a 
# MongoDB cluster (without sharding, and without anything fancy 
# like RAID disks).
#
# Helps setup a primary node, join an existing cluster, or setup an
# arbiter.
#
# Optionally supports prepping, mounting and storing MongoDB data on
# an attached empty Microsoft Azure disk. This is recommended as you
# should get additional dedicated IOPS for that extra disk.
#
# Per the available Azure performance whitepapers, it is not
# recommended to use RAID configurations for increasing IOPS or 
# availability. This differs some from the standard guidance for
# using MongoDB on some other cloud providers based in the Seattle
# area, so we'll need to revisit this as more people use MongoDB
# on IaaS VMs I assume. I'm no performance expert.
#
# This script doesn't do well with error handling or restarting, so
# be sure you're ready to run it when you get going. If you need to
# try again, just delete the /etc/mongod.conf file and stop the 
# mongod service if it has run before + blow away the db data.
#
# No warranties or anything implied by this script, but I do hope
# it helps!
#



echo Specialized MongoDB on Microsoft Azure configuration script
echo by Jeff Wilcox and contributors
echo



pushd /tmp > /dev/null



### PREREQ SOFTWARE

echo Installing Node.js...
wget --no-check-certificate https://raw.github.com/isaacs/nave/master/nave.sh > /tmp/naveNode.log 2>&1
chmod +x nave.sh
sudo ./nave.sh usemain 0.10.26  > /tmp/naveNodeUseMain.log 2>&1
# ./nave.sh install 0.10.26
# ./nave.sh use 0.10.26

nodeInstalled=$(node -v)
if [ "$nodeInstalled" != "v0.10.26" ]; then
        echo Node.js could not be installed.
        exit 1
fi

echo Installing Azure Node.js module...
npm install azure@0.8.1  > /tmp/nodeInstall.log 2>&1

echo Installing Azure storage utility...
wget --no-check-certificate https://raw.github.com/jeffwilcox/waz-updown/master/updown.js > /tmp/updownInstall.log 2>&1



### MONGODB

echo Adding MongoDB repos to the system...
cat > ./mongodb.repo << "YUM10GEN"
[mongodb]
name=MongoDB Repository
baseurl=http://downloads-distro.mongodb.org/repo/redhat/os/x86_64/
gpgcheck=0
enabled=1
YUM10GEN
 
sudo mv mongodb.repo /etc/yum.repos.d/
sudo yum install -y mongodb-org > /tmp/installingMongo.log


### AZURE STORAGE CONFIG

if [ -z "$AZURE_STORAGE_ACCOUNT" ]; then
	read -p "Azure storage account name? " storageAccount
	export AZURE_STORAGE_ACCOUNT=$storageAccount
	echo
fi

if [ -z "$AZURE_STORAGE_ACCESS_KEY" ]; then
	read -s -p "Account access key? " storageKey
	export AZURE_STORAGE_ACCESS_KEY=$storageKey
	echo
fi

: ${AZURE_STORAGE_ACCOUNT?"Need to set AZURE_STORAGE_ACCOUNT"}
: ${AZURE_STORAGE_ACCESS_KEY?"Need to set AZURE_STORAGE_ACCESS_KEY"}

# Awesome ask function by @davejamesmiller https://gist.github.com/davejamesmiller/1965569
function ask {
    while true; do
 
        if [ "${2:-}" = "Y" ]; then
            prompt="Y/n"
            default=Y
        elif [ "${2:-}" = "N" ]; then
            prompt="y/N"
            default=N
        else
            prompt="y/n"
            default=
        fi
 
        # Ask the question
        read -p "$1 [$prompt] " REPLY
 
        # Default?
        if [ -z "$REPLY" ]; then
            REPLY=$default
        fi
 
        # Check if the reply is valid
        case "$REPLY" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac
 
    done
}



### VARIABLES

isPrimary=true
isArbiter=false
isUsingDataDisk=true

mongoDataPath=/var/lib/mongo

primaryPasscode=
primaryHostname=$(hostname)



### CONFIGURATION

read -p "What is the name of the replica set? (Recommended: rs0) " replicaSetName

if [ -z "$replicaSetName" ]; then
	replicaSetName=rs0
fi

read -p "What is the mongod instance port? (Default: 27017) " mongodPort

if [ -z "$mongodPort" ]; then
	mongodPort=27017
fi

replicaSetKey=$replicaSetName.key

if ! ask "Is this the first node in the replica set? "; then
	isPrimary=false

	if ask "Is this an arbiter?"; then
		isArbiter=true
		isUsingDataDisk=false
	fi

	echo
	read -p "Primary node hostname? " primaryHostname
	read -p "Primary node cluster administrator password? " -s primaryPasscode
	echo
	echo
fi

if ! $isArbiter; then
	echo You may attach an empty data disk to this VM at any time now 
	echo if you would like to utilize the extra IOPS you get in such a 
	echo scenario. Recommended for a production instance, this is not 
	echo required.
	echo
	if ! ask "Would you like to use a data disk? "; then
		isUsingDataDisk=false
	fi
fi

if $isPrimary; then
	echo
	echo This primary VM has the hostname $primaryHostname - that will 
	echo be needed to bring online new nodes in the cluster.
	echo

	npm install node-uuid > /tmp/npm-temp.log 2>&1

	echo Time to set a password for the 'clusteradmin' user. This user will not 
	echo directly have access to data stored in the cluster, but it will be able
	echo to create and modify such credentials.
	echo
	echo Here is a suggested password that is a random UUID, in case you like 
	echo what you see:
	node -e "var uuid = require('node-uuid'); console.log(uuid.v4());"
	echo

	read -s -p "Please enter a new password for the 'clusteradmin' MongoDB user: " primaryPasscode
	echo
	read -s -p "Please confirm that awesome new password: " primaryPasscodeConfirmation
	echo

	if [ "$primaryPasscode" != "$primaryPasscodeConfirmation" ]; then
		echo The passwords did not match. Sorry. Goodbye.
		exit 1
	fi

fi

echo
echo MongoDB VM will be configured as:

echo - Replica set named $replicaSetName

if $isPrimary; then
	echo - Primary node in the replica set
	echo - New 'clusteradmin' user with a password you set.
fi

if $isArbiter; then
	echo - Replica set arbiter
	echo
	echo DISK NOTE:
	echo There is no need to attach a data disk to this VM.
fi

if ! $isPrimary && ! $isArbiter ; then
	echo - Additional node in the replica set
fi

if $isUsingDataDisk; then
	echo - Additional data disk that will mount to /mnt/data
fi

echo
echo
echo OK. Please sit back, relax, and enjoy the show...
echo



### DATA DISK

if $isUsingDataDisk; then

	mongoDataPath=/mnt/data

	echo Checking for attached Azure data disk...
	while [ ! -e /dev/sdc ]; do echo waiting for /dev/sdc empty disk to attach; sleep 20; done

	echo Partitioning...
	sudo fdisk /dev/sdc <<ENDPARTITION > /tmp/fdisk.log 2>&1
n
p
1
1

w
ENDPARTITION

	echo Formatting w/ext4...
	sudo mkfs.ext4 /dev/sdc1  > /tmp/format.log 2>&1

	echo Preparing permanent data disk mount point at /mnt/data...
	sudo mkdir /mnt/data
	echo '/dev/sdc1 /mnt/data ext4 defaults,auto,noatime,nodiratime,noexec 0 0' | sudo tee -a /etc/fstab

	echo Mounting the new disk...
	sudo mount /mnt/data
	sudo e2label /dev/sdc1 /mnt/data

fi



### MONGODB

echo Creating MongoDB folders on the disk owned by the mongod user in $mongoDataPath...
sudo mkdir $mongoDataPath/log
sudo mkdir $mongoDataPath/db
sudo chown -R mongod:mongod $mongoDataPath

# FYI: YAML syntax introduced in MongoDB 2.6
echo Configuring MongoDB 2.6...
sudo tee /etc/mongod.conf > /dev/null <<EOF
systemLog:
    destination: file
    path: "/var/log/mongodb/mongod.log"
    quiet: true
    logAppend: true
processManagement:
    fork: true
    pidFilePath: "/var/run/mongodb/mongod.pid"
net:
    port: $mongodPort
security:
    keyFile: "/etc/$replicaSetKey"
    authorization: "enabled"
storage:
    dbPath: "$mongoDataPath/db"
    directoryPerDB: true
    journal:
        enabled: true
replication:
    replSetName: "$replicaSetName"
EOF

if $isPrimary; then
	echo Generating replica set security key...
	openssl rand -base64 753 > $replicaSetKey
	echo Securely storing replica set key in Azure storage...
	node updown.js mongodb up $replicaSetKey
else
	echo Acquiring replica set security key from the cloud...
	node updown.js mongodb down $replicaSetKey
fi

echo Installing replica set key on the machine...

sudo chown mongod:mongod $replicaSetKey
sudo chmod 0600 $replicaSetKey
sudo mv $replicaSetKey /etc/$replicaSetKey

echo
echo About to bring online MongoDB.
echo This may take a few minutes as the initial journal is preallocated.
echo

echo Starting MongoDB service...
sudo service mongod start
sudo chkconfig mongod on

if $isPrimary; then

	echo Initializing the replica set...

	sleep 2

	cat <<EOF > /tmp/initializeReplicaSetPrimary.js
rsconfig = {_id: "$replicaSetName",members:[{_id:0,host:"$primaryHostname:$mongodPort"}]}
rs.initiate(rsconfig);
rs.conf();
EOF

	/usr/bin/mongo /tmp/initializeReplicaSetPrimary.js > /tmp/creatingMongoCluster.log 2>&1

	sleep 10
	
	echo Creating cluster administrator account...
	cat <<EOF > /tmp/initializeAuthentication.js
db = db.getSiblingDB('admin');
db.createUser({
  user: 'clusteradmin',
  pwd: '$primaryPasscode',
  roles: [
    'userAdminAnyDatabase',
    'clusterAdmin',
    { db: 'config', role: 'readWrite' },
    { db: 'local', role: 'read' }
  ]
});
EOF

	/usr/bin/mongo /tmp/initializeAuthentication.js --verbose > /tmp/creatingMongoClusterAdmin.log 2>&1	

	echo Authentication ready. Restarting MongoDB...
	sudo service mongod restart

	# remove credentials trace
	rm /tmp/initializeAuthentication.js

	echo
	echo So you now have a 'clusteradmin' user that can administer the replica set 
	echo and also add new users to databases. The password was set in this session.
	echo
	echo You should probably connect now and create databases, users on any new 
	echo databases, etc.
	echo
	echo Read up on this here:
	echo http://docs.mongodb.org/manual/tutorial/add-user-to-database/
	echo 
	echo To connect to a Mongo instance:
	echo   mongo MYDB -u Username -p
	echo

	if ask "Would you like to connect to MongoDB Shell now as 'clusteradmin' to do this? "; then
		/usr/bin/mongo admin -uclusteradmin -p$primaryPasscode
	fi

else

	ourHostname=$(hostname)

	if $isArbiter; then
		cat <<EOF > /tmp/joinCluster.js
rs.addArb('$ourHostname:$mongodPort');
rs.conf();
rs.status();
EOF

	else

		cat <<EOF > /tmp/joinCluster.js
rs.add('$ourHostname:$mongodPort');
rs.conf();
rs.status();
EOF

	fi

	echo Joining the MongoDB cluster...
	/usr/bin/mongo $primaryHostname/admin -uclusteradmin -p$primaryPasscode /tmp/joinCluster.js --verbose > /tmp/joinCluster.log 2>&1

	if ask "Would you like to view the replica set status? "; then
		/usr/bin/mongo $primaryHostname/admin -uclusteradmin -p$primaryPasscode << EOF
rs.status();
EOF
	fi

	if ask "Would you like to connect to the primary node to look around? "; then
		/usr/bin/mongo $primaryHostname/admin -uclusteradmin -p$primaryPasscode
	fi

fi

echo
echo Well, that looks like a wrap. Have a nice day!
echo

popd > /dev/null
