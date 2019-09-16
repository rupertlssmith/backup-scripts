#!/bin/bash
# ----------------------------------------------------------------------
# mikes handy rotating-filesystem-snapshot utility
# ----------------------------------------------------------------------
# this needs to be a lot more general, but the basic idea is it makes
# rotating backup-snapshots of /home whenever called
# ----------------------------------------------------------------------

VOLUME_NAME=$1
BACKUP_VG=$2
SOURCE_VG=$3
ROOT_FOLDER=$4

display_usage() { 
    echo "\nUsage:\nmake_snapsho.sh <volume_name> <backup_vg> <source_vg> <root_folder> \n" 
}

if [[ -z $VOLUME_NAME || -z $BACKUP_VG || -z $SOURCE_VG || -z $ROOT_FOLDER ]]; then
    display_usage ;
    exit 1 ;
fi

echo VOLUME_NAME=$VOLUME_NAME
echo BACKUP_VG=$BACKUP_VG
echo SOURCE_VG=$SOURCE_VG
echo ROOT_FOLDER=$ROOT_FOLDER

unset PATH	# suggestion from H. Milz: avoid accidental use of $PATH


# ------------- system commands used by this script --------------------
ID=/usr/bin/id;
ECHO=/bin/echo;

MOUNT=/bin/mount;
UMOUNT=/bin/umount;
RM=/bin/rm;
MV=/bin/mv;
CP=/bin/cp;
TOUCH=/bin/touch;
MKDIR=/bin/mkdir;
LVCREATE=/sbin/lvcreate;
LVREMOVE=/sbin/lvremove;

RSYNC=/usr/bin/rsync;

# ------------- file locations -----------------------------------------

SNAPSHOT_VOLUME_NAME="$VOLUME_NAME"_snapshot

BACKUP_DEVICE="$BACKUP_VG"/"$VOLUME_NAME"_backup;
SNAPSHOT_DEVICE="$SOURCE_VG"/"$VOLUME_NAME"_snapshot
SOURCE_DEVICE="$SOURCE_VG"/"$VOLUME_NAME"

BACKUP_RW=/mnt/"$VOLUME_NAME"_backup;
SNAPSHOT=/mnt/"$VOLUME_NAME"_snapshot;
EXCLUDES=/etc/backup_scripts/backup_exclude_"$VOLUME_NAME";

# ------------- the script itself --------------------------------------

# make sure we're running as root
if (( `$ID -u` != 0 )); then { $ECHO "Sorry, must be root.  Exiting..."; exit; } fi

# attempt to remount the RW mount point as RW; else abort
$MKDIR -p $BACKUP_RW
$MOUNT -o remount,rw $BACKUP_DEVICE $BACKUP_RW ;
if (( $? )); then
{
	$ECHO "snapshot: could not remount $BACKUP_RW readwrite";
	exit;
}
fi;


# step 1: delete the oldest snapshot, if it exists:
if [ -d $BACKUP_RW/$ROOT_FOLDER/daily.3 ] ; then			\
$RM -rf $BACKUP_RW/$ROOT_FOLDER/daily.3 ;				\
fi ;

# step 2: shift the middle snapshots(s) back by one, if they exist
if [ -d $BACKUP_RW/$ROOT_FOLDER/daily.2 ] ; then			\
$MV $BACKUP_RW/$ROOT_FOLDER/daily.2 $BACKUP_RW/$ROOT_FOLDER/daily.3 ;	\
fi;
if [ -d $BACKUP_RW/$ROOT_FOLDER/daily.1 ] ; then			\
$MV $BACKUP_RW/$ROOT_FOLDER/daily.1 $BACKUP_RW/$ROOT_FOLDER/daily.2 ;	\
fi;

# step 3: make a hard-link-only (except for dirs) copy of the latest snapshot,
# if that exists
if [ -d $BACKUP_RW/$ROOT_FOLDER/daily.0 ] ; then			\
$CP -al $BACKUP_RW/$ROOT_FOLDER/daily.0 $BACKUP_RW/$ROOT_FOLDER/daily.1 ;	\
fi;

# Create an LVM snapshot of the volume to back up
$LVCREATE -s $SOURCE_DEVICE -n$SNAPSHOT_VOLUME_NAME -L5G
$MKDIR -p $SNAPSHOT
$MOUNT -o ro $SNAPSHOT_DEVICE $SNAPSHOT
								
# step 5: rsync from the system into the latest snapshot (notice that
# rsync behaves like cp --remove-destination by default, so the destination
# is unlinked first.  If it were not so, this would copy over the other
# snapshot(s) too!
$MKDIR -p $BACKUP_RW/$ROOT_FOLDER

$RSYNC								\
	-va -x --delete --delete-excluded				\
	--exclude-from="$EXCLUDES"				\
	$SNAPSHOT/ $BACKUP_RW/$ROOT_FOLDER/daily.0 ;

# step 5: update the mtime of daily.0 to reflect the snapshot time
$TOUCH $BACKUP_RW/$ROOT_FOLDER/daily.0 ;

# now remount the RW snapshot mountpoint as readonly

$MOUNT -o remount,ro $BACKUP_DEVICE $BACKUP_RW ;
if (( $? )); then
{
	$ECHO "snapshot: could not remount $BACKUP_RW readonly";
	exit;
} fi;

# Remove the LVM snapshot
$UMOUNT $SNAPSHOT
$LVREMOVE -f $SNAPSHOT_DEVICE
