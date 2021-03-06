#! /bin/sh
#
# $Id: mkliveimage-zaurus.sh,v 1.2 2012/02/10 14:24:53 tsutsui Exp tsutsui $
#
# Copyright (c) 2009, 2010, 2011, 2012, 2019 Izumi Tsutsui.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

REVISION=20200223

DISKNAME=TeokureLiveImage
IMAGEHOSTNAME=zaurus
TIMEZONE=Japan

#MACHINE=hpcarm
#MACHINE=hpcmips
MACHINE=zaurus

err()
{
	echo $1 failed!
	exit 1
}

#if [ -z ${MACHINE} ]; then
#	if [ \( -z "$1" \) -o \( ! -z "$2" \) ]; then
#		echo "usage: $0 MACHINE"
#		echo "supported MACHINE:" \
#		     "hpcarm hpcmips zaurus"
#		exit 1
#	fi
#	MACHINE=$1
#fi

HAVE_EXPANDFS_SCRIPT=yes	# put a script to expand image fssize
EXPANDFS_SH=expand-image-fssize.sh

#
# target dependent info
#
if [ "${MACHINE}" = "zaurus" ]; then
 MACHINE_ARCH=arm
 MACHINE_GNU_PLATFORM=arm--netbsdelf-eabi		# for fdisk(8)
 TARGET_ENDIAN=le
 KERN_SET=kern-GENERIC
 EXTRA_SETS= # nothing
 USE_MBR=yes
 BOOTDISK=ld0		# for SD
 OMIT_SWAPIMG=yes
 #RTC_LOCALTIME=no	# Linux also uses UTC
 #PRIMARY_BOOT=		# nothing
 #SECONDARY_BOOT=	# nothing
 #SECONDARY_BOOT_ARG=	# nothing
fi

if [ -z ${MACHINE_ARCH} ]; then
	echo "Unsupported MACHINE (${MACHINE})"
	exit 1
fi

CURDIR=`pwd`
# assume proper symlinks are prepared in ${CURDIR}
NETBSDSRCDIR=${CURDIR}/src
OBJDIR=${CURDIR}
if [ -e ${CURDIR}/obj ]; then
	OBJDIR=${CURDIR}/obj
fi

#
# tooldir settings
#
if [ -z ${TOOLDIR} ]; then
	_HOST_OSNAME=`uname -s`
	_HOST_OSREL=`uname -r`
	_HOST_ARCH=`uname -p 2> /dev/null || uname -m`
	TOOLDIRNAME=tooldir.${_HOST_OSNAME}-${_HOST_OSREL}-${_HOST_ARCH}
	TOOLDIR=${NETBSDSRCDIR}/obj.${MACHINE}/${TOOLDIRNAME}
	if [ ! -d ${TOOLDIR} ]; then
		TOOLDIR=${NETBSDSRCDIR}/${TOOLDIRNAME}
	fi
fi

if [ ! -d ${TOOLDIR} ]; then
	echo 'set TOOLDIR first'; exit 1
fi
if [ ! -x ${TOOLDIR}/bin/nbmake-${MACHINE} ]; then
	echo 'build tools in ${TOOLDIR} first'; exit 1
fi

#
# info about ftp to get binary sets
#
#FTPHOST=ftp.NetBSD.org
#FTPHOST=ftp.jp.NetBSD.org
#FTPHOST=ftp7.jp.NetBSD.org
FTPHOST=cdn.NetBSD.org
#FTPHOST=nyftp.NetBSD.org
RELEASE=9.0
RELEASEDIR=pub/NetBSD/NetBSD-${RELEASE}
#RELEASEDIR=pub/NetBSD-daily/HEAD/201910202250Z

#
# misc build settings
#

# tools binaries
TOOL_DISKLABEL=${TOOLDIR}/bin/nbdisklabel
TOOL_FDISK=${TOOLDIR}/bin/${MACHINE_GNU_PLATFORM}-fdisk
TOOL_INSTALLBOOT=${TOOLDIR}/bin/nbinstallboot
TOOL_MAKEFS=${TOOLDIR}/bin/nbmakefs
TOOL_SED=${TOOLDIR}/bin/nbsed
TOOL_SUNLABEL=${TOOLDIR}/bin/nbsunlabel

# host binaries
AWK=/usr/pkg/bin/gawk	# GNU awk is necessary for "%'d" format
CAT=cat
CP=cp
DD=dd
FTP=ftp
#FTP=tnftp
FTP_OPTIONS=-V
GZIP=gzip
MD5=/usr/bin/md5
#MD5=/usr/bin/md5sum
MKDIR=mkdir
RM=rm
SH=sh
TAR=tar
WC=wc

TARGETROOTDIR=${OBJDIR}/targetroot.${MACHINE}
TARGETFATDIR=${OBJDIR}/targetfat.${MACHINE}
DOWNLOADDIR=download.${RELEASE}.${MACHINE}
WORKDIR=${OBJDIR}/work.${MACHINE}
IMAGE=liveimage-${MACHINE}-${REVISION}.img
IMAGEDIR=${CURDIR}/images/${REVISION}-${MACHINE}

#
# target image size settings
#
FATMB=32			# to store bootloader and kernels
IMAGEMB=948			# for "1GB" SD (mine has only 994,050,048 B)
SWAPMB=64			# 64MB
FATSECTORS=$((${FATMB} * 1024 * 1024 / 512))
FATSIZE=$((${FATSECTORS} * 512))
IMAGESECTORS=$((${IMAGEMB} * 1024 * 1024 / 512))
SWAPSECTORS=$((${SWAPMB} * 1024 * 1024 / 512))

LABELSECTORS=0
if [ "${USE_MBR}" = "yes" ]; then
#	LABELSECTORS=63		# historical
#	LABELSECTORS=32		# aligned
	LABELSECTORS=2048	# align 1MiB for modern flash
fi

FATOFFSET=$((${LABELSECTORS}))
# swap is allocated out of BSD partition as fdisk LNXSWAP
BSDPARTSECTORS=$((${IMAGESECTORS} - ${LABELSECTORS} - ${FATSECTORS} - ${SWAPSECTORS}))
FSSECTORS=${BSDPARTSECTORS}	
FSOFFSET=$((${LABELSECTORS} + ${FATSECTORS}))
SWAPOFFSET=$((${LABELSECTORS} + ${FATSECTORS} + ${FSSECTORS}))
FSSIZE=$((${FSSECTORS} * 512))
HEADS=64
SECTORS=32
CYLINDERS=$((${IMAGESECTORS} / ( ${HEADS} * ${SECTORS} ) ))
FSCYLINDERS=$((${FSSECTORS} / ( ${HEADS} * ${SECTORS} ) ))
SWAPCYLINDERS=$((${SWAPSECTORS} / ( ${HEADS} * ${SECTORS} ) ))

# fdisk(8) parameters
MBRSECTORS=63
MBRHEADS=255
MBRCYLINDERS=$((${IMAGESECTORS} / ( ${MBRHEADS} * ${MBRSECTORS} ) ))
MBRFAT=6	# 16-bit FAT, more than 32M
MBRNETBSD=169
MBRLNXSWAP=130

# makefs(8) parameters
BLOCKSIZE=16384
FRAGSIZE=4096
DENSITY=8192

#
# get binary sets
#
URL_SETS=http://${FTPHOST}/${RELEASEDIR}/${MACHINE}/binary/sets
URL_INST=http://${FTPHOST}/${RELEASEDIR}/${MACHINE}/installation
#SETS="${KERN_SET} modules base rescue etc comp games man misc tests text xbase xcomp xetc xfont xserver ${EXTRA_SETS}"
SETS="${KERN_SET} base rescue etc misc text xbase xetc xfont xserver ${EXTRA_SETS}"
INSTKERNEL="netbsd-INSTALL netbsd-INSTALL_C700"
#SETS="${KERN_SET} base etc comp ${EXTRA_SETS}"
${MKDIR} -p ${DOWNLOADDIR}
for set in ${SETS}; do
	if [ ! -f ${DOWNLOADDIR}/${set}.tgz ]; then
		echo Fetching ${set}.tgz...
		${FTP} ${FTP_OPTIONS} \
		    -o ${DOWNLOADDIR}/${set}.tgz ${URL_SETS}/${set}.tgz \
		    || err ${FTP}-${set}.tgz
	fi
done
for instkernel in ${INSTKERNEL}; do
	if [ ! -f ${DOWNLOADDIR}/${instkernel} ]; then
		echo Fetching ${instkernel}...
		${FTP} ${FTP_OPTIONS} \
		    -o ${DOWNLOADDIR}/${instkernel} \
		    ${URL_INST}/kernel/${instkernel} \
		    || err ${FTP}-${instkernel}
	fi
done
KERN_C700=kern-C700.tgz
if [ ! -f ${DOWNLOADDIR}/${KERN_C700} ]; then
	echo Fetching ${KERN_C700}...
	${FTP} ${FTP_OPTIONS} \
	    -o ${DOWNLOADDIR}/${KERN_C700} \
	    ${URL_SETS}/${KERN_C700} \
	    || err ${FTP}-${KERN_C700}
fi

#
# create targetroot
#
echo Removing ${TARGETROOTDIR}...
${RM} -rf ${TARGETROOTDIR}
${MKDIR} -p ${TARGETROOTDIR}
for set in ${SETS}; do
	echo Extracting ${set}...
	${TAR} -C ${TARGETROOTDIR} -zxf ${DOWNLOADDIR}/${set}.tgz \
	    || err ${TAR}
done
# XXX /var/spool/ftp/hidden is unreadable
chmod u+r ${TARGETROOTDIR}/var/spool/ftp/hidden

# copy secondary boot for bootstrap
# XXX probabry more machine dependent
if [ ! -z ${SECONDARY_BOOT} ]; then
	echo Copying secondary boot...
	${CP} ${TARGETROOTDIR}/usr/mdec/${SECONDARY_BOOT} ${TARGETROOTDIR}
fi

#
# create target fs
#
echo Removing ${WORKDIR}...
${RM} -rf ${WORKDIR}
${MKDIR} -p ${WORKDIR}

echo Preparing /etc/fstab...
${CAT} > ${WORKDIR}/fstab <<EOF
ROOT.a		/		ffs	rw,log		1 1
ROOT.b		none		none	sw		0 0
ROOT.e		/dos		msdos	rw		0 0
ptyfs		/dev/pts	ptyfs	rw		0 0
kernfs		/kern		kernfs	rw		0 0
procfs		/proc		procfs	rw		0 0
#tmpfs		/tmp		tmpfs	rw,-m1777,-s=16M	0 0
tmpfs		/var/shm	tmpfs	rw,-m1777,-sram%25	0 0
EOF
${CP} ${WORKDIR}/fstab  ${TARGETROOTDIR}/etc

echo Setting liveimage specific configurations in /etc/rc.conf...
${CAT} ${TARGETROOTDIR}/etc/rc.conf | \
    ${TOOL_SED} -e 's/rc_configured=NO/rc_configured=YES/' > ${WORKDIR}/rc.conf
echo hostname=${IMAGEHOSTNAME}		>> ${WORKDIR}/rc.conf
echo \#dhcpcd=YES			>> ${WORKDIR}/rc.conf
${CP} ${WORKDIR}/rc.conf ${TARGETROOTDIR}/etc

echo Setting localtime...
ln -sf /usr/share/zoneinfo/${TIMEZONE} ${TARGETROOTDIR}/etc/localtime

echo Copying liveimage specific files...
#${CP} etc/${MACHINE}/ttys ${TARGETROOTDIR}/etc/ttys
${TAR} -C ${WORKDIR} -zxf ${DOWNLOADDIR}/${KERN_C700} \
    || err ${TAR}-${KERN_C700}
${CP} ${WORKDIR}/netbsd ${TARGETROOTDIR}/netbsd.c700

echo Preparing spec file for makefs...
${CAT} ${TARGETROOTDIR}/etc/mtree/* | \
	${TOOL_SED} -e 's/ size=[0-9]*//' > ${WORKDIR}/spec
${SH} ${TARGETROOTDIR}/dev/MAKEDEV -s all | \
	${TOOL_SED} -e '/^\. type=dir/d' -e 's,^\.,./dev,' >> ${WORKDIR}/spec
# spec for optional files/dirs
${CAT} >> ${WORKDIR}/spec <<EOF
./boot				type=file mode=0444
./dos				type=dir  mode=0755
./kern				type=dir  mode=0755
./netbsd			type=file mode=0755
./netbsd.c700			type=file mode=0755
./proc				type=dir  mode=0755
./tmp				type=dir  mode=1777
./etc/X11/xorg.conf		type=link mode=0755 link=xorg.conf.C7x0
EOF

if [ ${HAVE_EXPANDFS_SCRIPT}x = "yesx" ]; then
	echo Preparing ${EXPANDFS_SH} script...
	${TOOL_SED} 							\
		-e "s/@@BOOTDISK@@/${BOOTDISK}/"			\
		-e "s/@@DISKNAME@@/${DISKNAME}/"			\
		-e "s/@@IMAGEMB@@/${IMAGEMB}/"				\
		-e "s/@@MBRFAT@@/${MBRFAT}/"				\
		-e "s/@@FATMB@@/${FATMB}/"				\
		-e "s/@@FATOFFSET@@/${FATOFFSET}/"			\
		-e "s/@@MBRNETBSD@@/${MBRNETBSD}/"			\
		-e "s/@@BSDPARTSECTORS@@/${BSDPARTSECTORS}/"		\
		-e "s/@@MBRLNXSWAP@@/${MBRLNXSWAP}/"			\
		-e "s/@@SWAPMB@@/${SWAPMB}/"				\
		-e "s/@@HEADS@@/${HEADS}/"				\
		-e "s/@@SECTORS@@/${SECTORS}/"				\
		< ./${EXPANDFS_SH}.in > ${TARGETROOTDIR}/${EXPANDFS_SH} \
		|| err ${TOOL_SED}-expandfs
	echo ./${EXPANDFS_SH}   type=file mode=755 >> ${WORKDIR}/spec
fi

echo Creating rootfs...
${TOOL_MAKEFS} -M ${FSSIZE} -m ${FSSIZE} \
	-B ${TARGET_ENDIAN} \
	-F ${WORKDIR}/spec -N ${TARGETROOTDIR}/etc \
	-o bsize=${BLOCKSIZE},fsize=${FRAGSIZE},density=${DENSITY} \
	${WORKDIR}/rootfs ${TARGETROOTDIR} \
	|| err ${TOOL_MAKEFS}

if [ ${PRIMARY_BOOT}x != "x" ]; then
echo Installing bootstrap...
${TOOL_INSTALLBOOT} -v -m ${MACHINE} ${WORKDIR}/rootfs \
    ${TARGETROOTDIR}/usr/mdec/${PRIMARY_BOOT} ${SECONDARY_BOOT_ARG} \
    || err ${TOOL_INSTALLBOOT}
fi

if [ ${FATSECTORS} != 0 ]; then
# create target fat
	echo Removing ${TARGETFATDIR}...
	rm -rf ${TARGETFATDIR}
	${MKDIR} -p ${TARGETFATDIR}
	echo Copying ${MACHINE} bootstrap files to FAT partition...
	${CP} ${TARGETROOTDIR}/usr/mdec/zbsdmod.o ${TARGETFATDIR} \
	    || err ${CP}-zbsdmod.o
	${CP} ${TARGETROOTDIR}/usr/mdec/zboot ${TARGETFATDIR} \
	    || err ${CP}-zboot
	${CP} ${TARGETROOTDIR}/netbsd ${TARGETFATDIR} \
	    || err ${CP}-netbsd
	${CP} ${TARGETROOTDIR}/netbsd.c700 ${TARGETFATDIR} \
	    || err ${CP}-netbsd.c700
	${CP} ${DOWNLOADDIR}/netbsd-INSTALL ${TARGETFATDIR} \
	    || err ${CP}-netbsd-INSTALL
	${CP} ${DOWNLOADDIR}/netbsd-INSTALL_C700 ${TARGETFATDIR} \
	    || err ${CP}-netbsd-INSTALL_C700

	echo Creating msdosfs...
	${TOOL_MAKEFS} -t msdos \
	    -M ${FATSIZE} -m ${FATSIZE} \
	    ${WORKDIR}/fatfs ${TARGETFATDIR} \
	    || err ${TOOL_MAKEFS}-msdos
fi

if [ "${OMIT_SWAPIMG}x" != "yesx" ]; then
	echo Creating swap fs
	${DD} if=/dev/zero of=${WORKDIR}/swap \
	    seek=$((${SWAPSECTORS} - 1)) count=1 \
	    || err ${DD}-swap
fi

if [ ${LABELSECTORS} != 0 ]; then
	echo Creating MBR labels...
	${DD} if=/dev/zero of=${WORKDIR}/${IMAGE}.mbr count=1 \
	    seek=$((${IMAGESECTORS} - 1)) \
	    || err ${DD}-mbr
if [ "${MACHINE}" = "i386" -o "${MACHINE}" = "amd64" ]; then
	${TOOL_FDISK} -f -u -i \
	    -b ${MBRCYLINDERS}/${MBRHEADS}/${MBRSECTORS} \
	    -c ${TARGETROOTDIR}/usr/mdec/mbr \
	    -F ${WORKDIR}/${IMAGE}.mbr \
	    || err ${TOOL_FDISK}-1
else
	${TOOL_FDISK} -f -u -i \
	    -b ${MBRCYLINDERS}/${MBRHEADS}/${MBRSECTORS} \
	    -1 -a -s ${MBRNETBSD}/${FSOFFSET}/${BSDPARTSECTORS} \
	    -F ${WORKDIR}/${IMAGE}.mbr \
	    || err ${TOOL_FDISK}-1
fi
	# create FAT partition
	${TOOL_FDISK} -f -u \
	    -0 -s ${MBRFAT}/${FATOFFSET}/${FATSECTORS} \
	    -F ${WORKDIR}/${IMAGE}.mbr \
	    || err ${TOOL_FDISK}-0
	# create swap partition as Linux swap
	${TOOL_FDISK} -f -u \
	    -2 -s ${MBRLNXSWAP}/${SWAPOFFSET}/${SWAPSECTORS} \
	    -F ${WORKDIR}/${IMAGE}.mbr \
	    || err ${TOOL_FDISK}-2
	${DD} if=${WORKDIR}/${IMAGE}.mbr of=${WORKDIR}/mbrsectors count=${LABELSECTORS} \
	    || err ${DD}-mbrsectors
	${RM} -f ${WORKDIR}/${IMAGE}.mbr
	echo Copying target disk image...
	${CAT} ${WORKDIR}/mbrsectors > ${WORKDIR}/${IMAGE} \
	    || err ${CAT}-mbrsectors
	if [ ${FATSECTORS} != 0 ]; then
		${CAT} ${WORKDIR}/fatfs >> ${WORKDIR}/${IMAGE} \
		    || err ${CAT}-fatfs
	fi
	${CAT} ${WORKDIR}/rootfs >> ${WORKDIR}/${IMAGE}
	if [ "${OMIT_SWAPIMG}x" != "yesx" ]; then
		${CAT} ${WORKDIR}/swap >> ${WORKDIR}/${IMAGE} \
		    || err ${CAT}-swap
	fi
else
	echo Copying target disk image...
	${CP} ${WORKDIR}/rootfs ${WORKDIR}/${IMAGE} \
	    || err ${CP}
	if [ "${OMIT_SWAPIMG}x" != "yesx" ]; then
		${CAT} ${WORKDIR}/swap >> ${WORKDIR}/${IMAGE} \
		    || err ${CAT}
	fi
fi

if [ ! -z ${USE_SUNLABEL} ]; then
	echo Creating sun disklabel...
	printf 'V ncyl %d\nV nhead %d\nV nsect %d\na %d %d/0/0\nb %d %d/0/0\nW\n' \
	    ${CYLINDERS} ${HEADS} ${SECTORS} \
	    ${FSOFFSET} ${FSCYLINDERS} ${FSCYLINDERS} ${SWAPCYLINDERS} | \
	    ${TOOL_SUNLABEL} -nq ${WORKDIR}/${IMAGE} \
	    || err ${TOOL_SUNLABEL}
fi

echo Creating disklabel...
${CAT} > ${WORKDIR}/labelproto <<EOF
type: ESDI
disk: ${DISKNAME}
label: 
flags:
bytes/sector: 512
sectors/track: ${SECTORS}
tracks/cylinder: ${HEADS}
sectors/cylinder: $((${HEADS} * ${SECTORS}))
cylinders: ${CYLINDERS}
total sectors: ${IMAGESECTORS}
rpm: 10000
interleave: 1
trackskew: 0
cylinderskew: 0
headswitch: 0           # microseconds
track-to-track seek: 0  # microseconds
drivedata: 0 

8 partitions:
#        size    offset     fstype [fsize bsize cpg/sgs]
a:    ${FSSECTORS} ${FSOFFSET} 4.2BSD ${FRAGSIZE} ${BLOCKSIZE} 128
b:    ${SWAPSECTORS} ${SWAPOFFSET} swap
c:    ${BSDPARTSECTORS} ${FSOFFSET} unused 0 0
d:    ${IMAGESECTORS} 0 unused 0 0
e:    ${FATSECTORS} ${FATOFFSET} MSDOS
EOF

${TOOL_DISKLABEL} -R -F -M ${MACHINE} ${WORKDIR}/${IMAGE} ${WORKDIR}/labelproto \
    || err ${TOOL_DISKLABEL}

# XXX some ${MACHINE} needs disklabel for installboot
#${TOOL_INSTALLBOOT} -vm ${MACHINE} ${MACHINE}.img \
#    ${TARGETROOTDIR}/usr/mdec/${PRIMARY_BOOT}

# create release files
echo Compressing ${IMAGE}...
${MKDIR} -p ${IMAGEDIR}
${DD} if=${WORKDIR}/${IMAGE} count=$((${IMAGEMB} - ${SWAPMB})) bs=1m \
    | ${GZIP} -9c > ${IMAGEDIR}/${IMAGE}.gz

TARGET=distinfo

rm -f ${IMAGEDIR}/${TARGET}
touch ${IMAGEDIR}/${TARGET}

# Put MD5 and sizes of compressed images
echo Calculating distinfo...
echo ${IMAGE}
 (cd ${IMAGEDIR} && ${MD5} ${IMAGE}.gz >> ${TARGET})
 (cd ${IMAGEDIR} && ${WC} -c ${IMAGE}.gz | \
  LANG=ja_JP.UTF-8 ${AWK} '{printf "Size (%s) = %\047d bytes\n","'${IMAGE}.gz'",$1}' >> ${TARGET})

# put sizes of uncompressed images

echo >> ${IMAGEDIR}/${TARGET}
#  for ${IMG_AMD64_USB}
 (${GZIP} -cd ${IMAGEDIR}/${IMAGE}.gz | ${WC} -c | \
  LANG=ja_JP.UTF-8 ${AWK} '{printf "Size (%s) = %\047d bytes\n","'${IMAGE}'",$1 }' >> ${IMAGEDIR}/${TARGET})

echo Creating image \"${IMAGE}\" complete.
