#!/bin/bash
DEBUG="$@"
run() {
  if [[ -z "$DEBUG" ]]
  then
    sudo "$@"
  else
    echo sudo "$@"
  fi
}
# ensure sudo works
if ! sudo id >/dev/null
then
  echo "Cannot execute sudo" 1>&2
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

# tune
run sh -c 'echo -e "\nvm.swappiness=1" >> /etc/sysctl.conf'

# Set clock and turn on ntpd
run service ntpd stop
run ntpdate pool.ntp.org
run service ntpd start
run chkconfig ntpd on

# Format all storage volumes except the root volume
tmpdir=/tmp/mkfs-$(date +%s)
mkdir -p $tmpdir
run mkfs -t ext4 /dev/xvdf 1>$tmpdir/xvdf.out 2>$tmpdir/xvdf.err </dev/null &
run mkfs -t ext4 /dev/xvdg 1>$tmpdir/xvdg.out 2>$tmpdir/xvdg.err </dev/null &
data_devices=$(lsblk | egrep '^xvd[a-z]+ ' | awk '!$7 {print $1}' | egrep -v 'xvdf|xvdg')
for dev in $data_devices
do
  run mkfs -t ext4 -m 1 -T largefile -O dir_index,extent,sparse_super /dev/$dev  1>$tmpdir/$dev.out 2>$tmpdir/$dev.err </dev/null &
done

wait

for file in $tmpdir/*
do
  echo "***** mkfs output " ${file##*/} "*******"
  cat $file
done

# Rename existing /var/log dir
run mv /var/log /var/log-old-$(date +%s)

# Backup fstab
run cp /etc/fstab /etc/fstab-$(date +%s)

# Add entries to /etc/fstab
add_device() {
  dev=$1
  mp=$2
  run mkdir -p $mp
  if [[ -n "$DEBUG" ]] || ! grep -Eq "^$dev" /etc/fstab
  then
    run sed -i '$ a'$dev' '$mp' ext4 defaults,noatime 0 0' /etc/fstab
  fi
  if [[ -n "$DEBUG" ]] || [[ -z "$(awk '{print $2}' /proc/mounts | grep $mp)" ]]
  then
    run mount $mp
  fi
}
add_device /dev/xvdf /var/log
add_device /dev/xvdg /opt/cloudera
count=0
for dev in $data_devices
do
  add_device "/dev/$dev" "/data$count"
  ((count++))
done
exit 0
