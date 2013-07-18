#!/bin/bash

# sitara, beaglebone
TARGET_TYPE=sitara
WORKSPACE=`pwd`
BUILD_NUMBER=001
BUILD_ID=`date +"%m-%d-%Y_%H-%M-%S"`

PACK_ONLY=false

# project sources
DRIVER_REF=origin/mc_internal_39
COMPAT_REF=origin/dt
COMPAT_WIRELESS_REF=origin/dt
HOSTAP_REF=origin/android_jb_mr1_39
TI_UTILS_REF=origin/mc_internal
WL18XX_FW_REF=origin/master
TARGET_SCRIPTS_REF=origin/sitara
GIT_REMOTE=origin


function set_linux_kernel ()
{
	if [ "${PACK_ONLY}" == "true" ] ; then
 	echo PACK_ONLY
	 return
	fi
    . ./setup-env
	echo
	echo ----------------------------------------------------
	echo adjusting kernel version
	echo ----------------------------------------------------
	echo

	if [ "${TARGET_TYPE}" == "sitara" ]
	then
		echo "settings sitara kernel"
		rm linux-am33x
		ln -s ${KERNEL_VERSIONTREE}/linux-am33x-sitara linux-am33x
	elif [ "${TARGET_TYPE}" == "beaglebone" ]
	then
		echo "settings beaglebone kernel"
 		rm linux-am33x
		ln -s ${KERNEL_VERSIONTREE}/linux-am33x-beaglebone linux-am33x
	else
 		echo "BOARD_TYPE unrecognized"
 		exit 2
	fi
}

function package_dir_exists()
{
	if [ -d "$1" ]
	then
		echo "YANIV Package $2 already downloaded at: $1"
		return 1
	fi
    echo "YANIV Package not already downloaded at: $1"
	return 0
}

function download_all ()
{

	echo
	echo ----------------------------------------------------
	echo Downloading packages for first time !!
    echo This can take some time..
	echo ----------------------------------------------------
	echo

	. ./setup-env
	    
	./wl18xx_build.sh download-all
	
    echo
	echo ----------------------------------------------------
	echo Finished downloading  
	echo ----------------------------------------------------
	echo
}
function update_git ()
{
	git_project=$1
	git_ref=$2

    if [ ! -d $git_project ] 
    then  
        download_all
    fi
        echo
        echo ----------------------------------------------------
        echo reset $git_project to $git_ref
        echo ----------------------------------------------------
        echo

        cd $git_project
        git fetch $GIT_REMOTE
        git fetch $GIT_REMOTE --tags
       	git reset --hard $git_ref

        export ret_val=$?
        if [ ! "$ret_val" == "0" ] ; then
                echo "$git_ref was not found in the git repository, did you fill in the correct value?" ;
                exit -1 ;
        fi

	git log HEAD^..HEAD --oneline
	cd ..
}


function update_project ()
{
        if [ "${PACK_ONLY}" == "true" ] ; then
                echo PACK_ONLY
                return
        fi        
        #if we got a version tag         
        if [ ! -z "$1" -a "head" != "$1" ]; then
            git_tag=$1
            echo "Updating version to" $git_tag            
            update_git wl18xx $git_tag
            update_git compat $git_tag
            update_git compat-wireless $git_tag            
            update_git 18xx-ti-utils $git_tag
            update_git wl18xx_fw $git_tag      
            update_git hostap $git_tag            
        else
            echo "Updating version to HEAD^" 
            update_git wl18xx $DRIVER_REF
            update_git compat $COMPAT_REF
            update_git compat-wireless $COMPAT_WIRELESS_REF            
            update_git 18xx-ti-utils $TI_UTILS_REF
            update_git wl18xx_fw $WL18XX_FW_REF
            update_git hostap $HOSTAP_REF
        fi 

        if [ -e fw.bin ] ; then
                echo "user FW file is providedi, update from user"
        	rm -f wl18xx_fw/wl18xx-fw-mc.bin
        	mv fw.bin wl18xx_fw/wl18xx-fw-mc.bin
                return
        fi
}

function build_all ()
{

	echo
	echo ----------------------------------------------------
	echo building everything...
	echo ----------------------------------------------------
	echo

	. ./setup-env

#	echo "update pm firmware into kernel"
#	cp am33x-cm3/bin/am335x-pm-firmware.bin linux-am33x/firmware

	#echo "building kernel"
	#make -C linux-am33x ARCH=arm CROSS_COMPILE=arm-arago-linux-gnueabi- -j$(egrep '^processor' /proc/cpuinfo | wc -l) uImage

	#echo "coping kernel image to boot folder"
	#cp linux-am33x/arch/arm/boot/uImage ./boot/uImage

	echo "building wlan components"
	./wl18xx_build.sh all

}

function create_package ()
{
	echo
	echo ----------------------------------------------------
	echo preparing fresh package...
	echo ----------------------------------------------------
	echo
	. ./setup-env
	echo "Clean out directory"
	mkdir -p out
	
    if [ -d ./out/boot ] ; then
		rm -rf ./out/boot
	fi	
    echo "Copying boot"
    cp -r ${BASE_BOOT_DIR} ./out
    
	if [ -d ./out/rootfs ] ; then
		rm -rf ./out/rootfs
	fi
    echo "Copying rootfs"
	mkdir -p ./out/rootfs
	cp -r ${BASE_ROOTFS_DIR}/* ./out/rootfs
    cp -r ${ROOTFS}/* ./out/rootfs

	echo "Copying addons"
	for addon_dir in `ls ${BASE_ADDONS_DIR}`
	do
		echo "     Copying everything from ${addon_dir} to rootfs directory"
		cp -rf ${BASE_ADDONS_DIR}/${addon_dir}/* ./out/rootfs
	done

	echo "Copying scripts"
	for script_dir in `ls ${BASE_SCRIPTS_DIR}/share`
	do
		echo "Copying everything from ${script_dir} to /home/root directory"
		mkdir -p ./out/rootfs/usr/share/wl18xx
		cp -rf ${BASE_SCRIPTS_DIR}/share/${script_dir}/* ./out/rootfs/usr/share/wl18xx
	done

	echo
	echo ----------------------------------------------------
	echo packing everything for the SD card...
	echo ----------------------------------------------------
	echo

	echo ${JOB_NAME} build \#${BUILD_NUMBER} details: > ./out/rootfs/build-info.txt
	echo built @ ${BUILD_ID} >> ./out/rootfs/build-info.txt
	echo build path ${WORKSPACE}
	echo wl18xx HEAD            `cd wl18xx ; git log HEAD^..HEAD --oneline` >> ./out/rootfs/build-info.txt
	echo compat HEAD            `cd compat ; git log HEAD^..HEAD --oneline` >> ./out/rootfs/build-info.txt
	echo compat-wireless HEAD   `cd compat-wireless ; git log HEAD^..HEAD --oneline` >> ./out/rootfs/build-info.txt
	echo hostap HEAD            `cd hostap ; git log HEAD^..HEAD --oneline` >> ./out/rootfs/build-info.txt
	echo 18xx-ti-utils HEAD     `cd 18xx-ti-utils ; git log HEAD^..HEAD --oneline` >> ./out/rootfs/build-info.txt
	echo wl18xx_fw HEAD         `cd wl18xx_fw  ; git log HEAD^..HEAD --oneline` >> ./out/rootfs/build-info.txt
	echo >> ./out/rootfs/build-info.txt
	echo >> ./out/rootfs/build-info.txt
	echo ENV >> ./out/rootfs/build-info.txt
	env >> ./out/rootfs/build-info.txt

	cd out
	echo "Creating the tarball"
	tar cjf ${TARGET_TYPE}-sd-build-${BUILD_NUMBER}.tar.bz2 rootfs boot
	cd ../
}


############################# MAIN ##############################################

#action=all

argc=$#
echo "Arguments $argc"
#if [ $argc -eq 1 ]
#then
        action=$1
#fi


echo "Performing $action ..."
case $action in
	all)        
		set_linux_kernel
		update_project head
		build_all
		create_package
		;;
	build)
                echo "action BUILD"
                set_linux_kernel
                build_all
                create_package
		;;
    update)
                echo "action UPDATE "
                if [ $argc -eq 2 ] ; then
                    git_tag=$2                    
                else
                    echo "Please insert release/tag name ( i.e. sdk_build.sh update <relese_name> )"
                    echo "Please use 'head' to update to HEAD"
                    exit 1
                fi
                update_project $git_tag
		;;    
	pack)
                create_package
                ;;
	*)
		echo "Invalid action $action"
		echo "Usage: parameters all, build or pack:"
		echo "      all - update project git-s, build and create rootfs & boot tar file"
        echo "      build - build and create rootfs & boot tar file"
        echo "      update- set project to a specific release (TAG) "
        echo "      pack - create rootfs & boot tar file"                
		exit 1
		;;
esac

############################# END OF MAIN #######################################





