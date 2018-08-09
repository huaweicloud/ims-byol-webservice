#!/bin/bash
#
# BYOLWebSerice Script to configure internal Repositories

#set -x

#exit 0

### Some variables

REPOFILE_SERV=100.125.xx.xx
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
# Test for Inifiniband
unset INFINIBAND
FLAVOR=$(echo "$METADATA" | grep metering.resourcespeccode | sed 's/^[^:]*: //' | tr -d '"')
if [[ $FLAVOR = h2.* ]] || [[ $FLAVOR = hl1.* ]]; then INFINIBAND=1; fi
if lspci -n | cut -d " " -f2-3 | grep '0207: 15b3:' >/dev/null 2>&1; then INFINIBAND=1; fi

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

# only for tsi_ubuntu
# if no OTC_ defined, get image_name from metadata service
if [ ! $IMAGE_NAME ]; then
  IMAGE_NAME=`curl -s http://169.254.169.254/openstack/latest/meta_data.json | tr "," "\n" |grep -w image_name |awk -F ':' '{print $2}' |tr -d '", '`
  if [[ $IMAGE_NAME != *"Community_Ubuntu_"*"TSI"* ]]; then IMAGE_NAME=""; fi
fi

echo "...for Image $IMAGE_NAME ($FLAVOR)" |tee -a $LOGF

# Install InfiniBand drivers from registered Mellanox repository
# Use ofed-guest metapackage and add a few selected pkgs from other selections (hpc)
# remove ev.thing relating to xen and trace kernels (and lock them), so they don't get pulled in
suse_ib_inst()
{
	cd /tmp
	# Grab -guest metapackage
	wget http://xxxx-suse.xxxx-service.com/repo/RPMMD/linux.mellanox.com/public/repo/mlnx_ofed/$1/$2/x86_64/mlnx-ofed-guest-$1.noarch.rpm
	# Filter out unwanted kernel modules
	rpm -qpR mlnx-ofed-guest-$1.noarch.rpm | grep -v xen | grep -v trace | grep -v knem-mlnx > ofed-guest.pkglist
	# Add most addtl packages from -hpc metapackage
	echo -e "ibutils2\nar_mgr\ncc_mgr\nlibibprof\nmstflint\nopensm" >> ofed-guest.pkglist
	# Lock unwanted kernels and install
	zypper al kernel-xen-base kernel-trace-base
	time zypper --non-interactive --no-gpg-checks --quiet install --auto-agree-with-licenses $(cat ofed-guest.pkglist) | tee -a $LOGF 2>&1
	zypper rl kernel-xen-base kernel-trace-base
	# Cleanup
	rm mlnx-ofed-guest-$1.noarch.rpm
}

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

CENTOS7_IB_NEEDS_REBOOT=1
centos7_ibconfig()
{
	echo "Create network config" | tee -a $LOGF
	cat >/etc/sysconfig/network-scripts/ifcfg-ib0 <<EOT
DEVICE=ib0
BOOTPROTO=dhcp
ONBOOT=yes
TYPE=Infiniband
EOT
	if test "$CENTOS7_IB_NEEDS_REBOOT" == "1"; then
		echo "Reboot for IB" | tee -a $LOGF
		yum clean all
		echo "OTC vendordata script finished." | tee -a $LOGF
		sync; reboot
	else
		systemctl daemon-reload
		echo "Start IB services" | tee -a $LOGF
		/etc/init.d/ibacm restart
		/etc/init.d/openibd restart
		#modprobe ib_srp; /etc/init.d/srpd restart
		/bin/mlnx_interface_mgr.sh ib0 &
		echo "Starting IB services completed" | tee -a $LOGF
		sleep 1
		ip addr show | tee -a $LOGF
	fi
}

case $IMAGE_NAME in
   OTC_CentOS_6*)
      centos_6_REPOS
      yum clean all
    ;;
   OTC_CentOS_7*)
      tmp_ver=`cat /etc/centos-release | cut -d" " -f4 | cut -b 1,3`
      centos_7X_REPOS $tmp_ver
      # Install IB drivers if needed
      if test "$INFINIBAND" == "1"; then
	IBVER=4.3-3.0.2.1
	echo "Install IB $IBVER for CentOS$tmp_ver" | tee -a $LOGF
	rhel_7X_IB_REPOS $tmp_ver $IBVER
	yum -y install mlnx-ofed-guest ibutils2 ar_mgr cc_mgr libibprof mstflint opensm
	centos7_ibconfig
      fi
      if ! test -e /etc/yum/pluginconf.d/priorities.conf; then
	yum -y install yum-plugin-priorities >/dev/null 2>&1
	true
      fi
      yum clean all
      centos7_rmv_hvcconsole
    ;;
   OTC_EulerOS_2*|CCE_EulerOS_2*)
      tmp_ver=`grep ^VERSION_ID /etc/os-release | cut -d '=' -f2 | tr -d '"'`
      sp_ver=`grep '^VERSION=' /etc/os-release | cut -d '=' -f2 | tr -d '"' | sed 's/^[^ ]* (\([^)]*\))/\1/'`
      euleros_2_REPOS $tmp_ver $sp_ver
      if test "$INFINIBAND" == "1"; then
	echo "Neither RHEL7.2 nor RHEL7.3 mellanox drivers are compatible with EulerOS kernel" 1>&2
	IBVER=4.2-1.0.0.0
	rhel_7X_IB_REPOS 7${sp_ver#SP} $IBVER
	yum -y install mlnx-ofed-guest ibutils2 ar_mgr cc_mgr libibprof mstflint opensm
	centos7_ibconfig
      fi
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
      if test "$INFINIBAND" == "1"; then
	IBVER=4.3-3.0.2.1
	rhel_7X_IB_REPOS $tmp_ver $IBVER
	yum -y install mlnx-ofed-guest ibutils2 ar_mgr cc_mgr libibprof mstflint opensm
	centos7_ibconfig
      fi
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
      if test "$INFINIBAND" == "1"; then
	IBVER=4.3-3.0.2.1
	rhel_7X_IB_REPOS $tmp_ver $IBVER
	yum -y install mlnx-ofed-guest ibutils2 ar_mgr cc_mgr libibprof mstflint opensm
	centos7_ibconfig
      fi
      centos7_rmv_hvcconsole
    ;;
   OTC_SLES11_SP*)
      tmp_ver=`grep -w PATCHLEVEL /etc/SuSE-release |awk '{print $NF}'`
      sles_11SPX_REPOS $tmp_ver

      ls /OTC_* |grep SAPHANA
      test $? = 0 && sles_11SPX_SAPHANA_REPOS $tmp_ver
      # Legacy: Support old SLES11_SP4_IB image
      ls /OTC_* |grep IB
      if test $? = 0; then
	sles_11SPX_IB_REPOS $tmp_ver 3.4-1.0.0.0
      # Future: We just use normal images and register repos and install pkgs on IB flavor
      elif test "$INFINIBAND" == "1"; then
	#IBVER=3.4-1.0.0.0
	IBVER=4.2-1.0.0.0
	sles_11SPX_IB_REPOS $tmp_ver $IBVER
	suse_ib_inst $IBVER sles11sp4
	/etc/init.d/ibacm start
	/etc/init.d/openibd start
      fi

    ;;
   OTC_SLES12_SP*)
      tmp_ver=`grep -w PATCHLEVEL /etc/SuSE-release |awk '{print $NF}'`
      sles_12SPX_REPOS $tmp_ver

      ls /OTC_* |grep SAP
      test $? = 0 && sles_12SPX_SAPHANA_REPOS $tmp_ver
      # Infiniband, new style, same as SLES11
      if test "$INFINIBAND" == "1"; then
	#IBVER=3.4-${tmp_ver}.0.0.0
	if test "$tmp_ver" == "1"; then
	  IBVER=4.1-1.0.2.0
	else
	  IBVER=4.2-1.0.0.0
	fi
	sles_12SPX_IB_REPOS $tmp_ver $IBVER
	suse_ib_inst $IBVER sles12sp${tmp_ver}
	/etc/init.d/ibacm start
	/etc/init.d/openibd start
      fi
      centos7_rmv_hvcconsole
    ;;

   OTC_openSUSE_42_JeOS*)
      tmp_ver=`grep -w VERSION /etc/SuSE-release |awk '{print $NF}'|cut -b 1,2,4`
      opensuse_42_jeos_REPOS $tmp_ver
      # Infiniband, new style, same as SLES12SP2
      if test "$INFINIBAND" == "1"; then
	sp_ver=${tmp_ver#42}
	#IBVER=3.4-2.0.0.0
	IBVER=4.2-1.0.0.0
	sles_12SPX_IB_REPOS $sp_ver $IBVER
	suse_ib_inst $IBVER sles12sp${sp_ver}
	/etc/init.d/ibacm start
	/etc/init.d/openibd start
      fi
      centos7_rmv_hvcconsole
    ;;
   OTC_openSUSE_42_Docker*)
      tmp_ver=`grep -w VERSION /etc/SuSE-release |awk '{print $NF}'|cut -b 1,2,4`
      opensuse_42_jeos_REPOS $tmp_ver
      opensuse_42_docker_REPOS $tmp_ver
      # Infiniband, new style, same as SLES12SP2
      if test "$INFINIBAND" == "1"; then
	sp_ver=${tmp_ver#42}
	#IBVER=3.4-2.0.0.0
	IBVER=4.2-1.0.0.0
	sles_12SPX_IB_REPOS $sp_ver $IBVER
	suse_ib_inst $IBVER sles12sp${sp_ver}
	/etc/init.d/ibacm start
	/etc/init.d/openibd start
      fi
      centos7_rmv_hvcconsole
    ;;
   *Community_Ubuntu_1?.04_TSI_*|*Standard_Ubuntu_1?.04_*|OTC_Ubuntu_1?_04*)
      tmp_ver=`grep ^VERSION_ID /etc/os-release | cut -d '=' -f2 | tr -d '"'`
      ubuntu_REPOS $tmp_ver
    ;;
   *)
     echo "Unknown image! Please check/configure your repositories!" |tee -a $LOGF
    ;;
esac

echo "OTC vendordata script finished." |tee -a $LOGF

exit 0
