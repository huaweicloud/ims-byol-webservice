#!/bin/bash
#
# BYOLWebSerice Script to configure internal Repositories

#set -x

#exit 0

### Some variables

REPOFILE_SERV=100.125.xxx.xxx
TMP_REPO=/var/tmp/otc-repos.in
LOGF=/var/log/otc-vendordata.log

### Main

# Exit, if user is already existing
USER1=`getent passwd linux`
USER2=`getent passwd ubuntu`

if ( test "$1" != "--force" && test -n "$USER1" -o -n "$USER2" ); then
  if ( test "$1" != "--forceall" ); then
    echo "Existing VM, exit 0"
    exit 0
  fi
fi


# Check, if logfile exists
if test -e $LOGF && test "$1" != "--forceall"; then
   date | tee -a $LOGF
   echo "vendordata script was executed before. Exit" |tee -a $LOGF
   exit 0
else
   date > $LOGF; chmod 640 $LOGF
fi

# Check if BYOL or not
METADATA=$(curl -s http://169.254.169.254/openstack/latest/meta_data.json | tr "," "\n")
echo "$METADATA" | grep metering.resourcespeccode | grep byol
BYOL=$?

if test "$BYOL" = 0; then
   echo "BYOL, nothing to do. Exit" |tee -a $LOGF
   # Future: Enable public repos here?
   # FIXME: do centos7_rmv_hvcconsole here for RHEL7 family also for BYOL
   exit 0
fi

# Check if private or public image
#curl -s http://169.254.169.254/openstack/latest/meta_data.json | tr "," "\n" |grep metering.imagetype |grep private
#RC=$?
#
#if test "$RC" = 0; then
#   echo "Private Image, nothing to do. Exit" |tee -a $LOGF
#   exit 0
#fi


### Start config for Public/Private Image

echo "Public/Private Image, start the configuration..." | tee -a $LOGF

# Source the repo file
THISDIR=`dirname "$0"`
if test -e $THISDIR/otc-repos.in -a "$1" == "--forceall"; then
   source $THISDIR/otc-repos.in
else
   curl -sSLk https://$REPOFILE_SERV/repo/tools/otc-repos.in > $TMP_REPO
   source $TMP_REPO
   rm $TMP_REPO
fi

# Get the image name
#IMAGE_NAME=`curl -s http://169.254.169.254/openstack/latest/meta_data.json | tr "," "\n" |grep -w image_name |awk -F ':' '{print $2}' |tr -d '", ' |awk -F '_' '{print $1"_"$2"_"$3}'`

IMAGE_NAME=`ls / |grep OTC_`
if test -z "$IMAGE_NAME"; then IMAGE_NAME=`ls / |grep CCE_`; fi

echo "...for Image $IMAGE_NAME ($FLAVOR)" |tee -a $LOGF


# Remove console=hvc console=tty appended by kiwi VMX template on xen (344985)
# Works on RHEL7 family as well as SLES12 family
centos7_rmv_hvcconsole()
{
	grep "console=hvc" /etc/sysconfig/bootloader >/dev/null 2>&1 && echo "remove console=hvc from boot config" | tee -a $LOGF
	sed -i 's/console=hvc console=tty //' /etc/sysconfig/bootloader
	# No /etc/sysconfig/grub on SUSE
	test -e /etc/sysconfig/grub && sed -i 's/console=hvc console=tty //' /etc/sysconfig/grub
	sed -i 's/console=hvc console=tty //' /boot/grub2/grub.cfg
}

case $IMAGE_NAME in
   OTC_CentOS_6*)
      centos_6_REPOS
      yum clean all
    ;;
   OTC_CentOS_7*)
      tmp_ver=`cat /etc/centos-release | cut -d" " -f4 | cut -b 1,3`
      centos_7X_REPOS $tmp_ver
      yum clean all
      centos7_rmv_hvcconsole
    ;;
   OTC_EulerOS_2*|CCE_EulerOS_2*)
      tmp_ver=`grep ^VERSION_ID /etc/os-release | cut -d '=' -f2 | tr -d '"'`
      sp_ver=`grep '^VERSION=' /etc/os-release | cut -d '=' -f2 | tr -d '"' | sed 's/^[^ ]* (\([^)]*\))/\1/'`
      euleros_2_REPOS $tmp_ver $sp_ver
      yum clean all
      centos7_rmv_hvcconsole
    ;;
    OTC_Debian_8*)
      debian_8_REPOS
    ;;
    OTC_Debian_9*)
      debian_9_REPOS
    ;;
   OTC_Fedora_2*)
      tmp_ver=`lsb_release -r |awk '{print $NF}'`
      fedora_XX_REPOS $tmp_ver
      dnf clean all
    ;;
   OTC_OEL_6*)
      tmp_ver=`cat /etc/oracle-release | cut -d" " -f5 | cut -b 1,3`
      oel_6_REPOS $tmp_ver
      yum clean all
    ;;
   OTC_OEL_7*)
      tmp_ver=`cat /etc/oracle-release | cut -d" " -f5 | cut -b 1,3`
      oel_7_REPOS $tmp_ver
      yum clean all
      centos7_rmv_hvcconsole
    ;;
   OTC_RHEL_6*)
      rhel_6_REPOS
      yum -y install rhui-rhel6-repos
    ;;
   OTC_RHEL_7*)
      tmp_ver=`cat /etc/redhat-release | cut -d" " -f7 | cut -b 1,3`
      rhel_7_REPOS
      yum -y install rhui-rhel7-repos
      centos7_rmv_hvcconsole
    ;;
   OTC_SLES11_SP*)
      tmp_ver=`grep -w PATCHLEVEL /etc/SuSE-release |awk '{print $NF}'`
      sles_11SPX_REPOS $tmp_ver
    ;;
   OTC_SLES12_SP*)
      tmp_ver=`grep -w PATCHLEVEL /etc/SuSE-release |awk '{print $NF}'`
      sles_12SPX_REPOS $tmp_ver
      centos7_rmv_hvcconsole
    ;;

   OTC_openSUSE_42_JeOS*)
      tmp_ver=`grep -w VERSION /etc/SuSE-release |awk '{print $NF}'|cut -b 1,2,4`
      opensuse_42_jeos_REPOS $tmp_ver
      centos7_rmv_hvcconsole
    ;;
   OTC_openSUSE_42_Docker*)
      tmp_ver=`grep -w VERSION /etc/SuSE-release |awk '{print $NF}'|cut -b 1,2,4`
      opensuse_42_jeos_REPOS $tmp_ver
      opensuse_42_docker_REPOS $tmp_ver
      centos7_rmv_hvcconsole
    ;;
    )
     echo "Unknown image! Please check/configure your repositories!" |tee -a $LOGF
    ;;
esac

echo "BYOLWebSerice Script finished." |tee -a $LOGF

exit 0
