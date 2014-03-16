#!/bin/bash
EC2_DEIVCE_URL="http://169.254.169.254/latest/meta-data/block-device-mapping/"
DEBUG="$@"
[[ -z "$DEBUG" ]]
exit $?
run() {
  if [[ -z "$DEBUG" ]]
  then
    sudo "$@"
  else
    echo run "$@"
  fi
}
# ensure sudo works
if ! sudo id >/dev/null
then
  echo "Cannot execute sudo" 1>&2
  exit 1
fi

# Check drives
numEbs=$(curl -s $EC2_DEIVCE_URL | egrep -c "^ebs")
numEphemeral=$(curl -s $EC2_DEIVCE_URL | egrep -c "^ephemeral")
if [[ $numEphemeral -ne 4 ]] && [[ $numEphemeral -ne 24 ]]
then
  echo "This script expects either 4 or 24 ephemeral drives" 1>&2
  exit 1
fi

if false && [[ $numEbs -ne 2 ]]
then
  echo "This script expects 2 EBS drives for /var/log and/opt/cloudera" 1>&2
  exit 1
fi

# Disable SELinux
run setenforce 0
run sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

# Turn off some services
run chkconfig iptables off
run chkconfig ip6tables off
run chkconfig cups off
run chkconfig postfix off

# Set clock and turn on ntpd
run service ntpd stop
run ntpdate pool.ntp.org
run service ntpd start
run chkconfig ntpd on

# Format all storage volumes except the root volume
run mkfs -t ext4 /dev/xvdf
run mkfs -t ext4 /dev/xvdg
data_devices=$(lsblk | egrep '^xvd[a-z]+ ' | awk '!$7 {print $1}' | egrep -v 'xvdf|xvdg')
for dev in $data_devices
do
  run mkfs -t ext4 -m 1 -T largefile -O dir_index,extent,sparse_super $dev
done

# Rename existing /var/log dir
run mv /var/log /var/log-old

# Create new directories
run mkdir /var/log /opt/cloudera /data0 /data1 /data2 /data3

# Backup fstab
run cp /etc/fstab /etc/fstab.bak

# Add entries to /etc/fstab
run sed -i '$ a/dev/xvdf /var/log ext4 defaults 0 0' /etc/fstab
run sed -i '$ a/dev/xvdg /opt/cloudera ext4 defaults 0 0' /etc/fstab
count=0
for dev in $data_devices
do
  run sed -i '$ a/dev/'$dev' /data'$count' ext4 defaults,noatime 0 0' /etc/fstab
done
