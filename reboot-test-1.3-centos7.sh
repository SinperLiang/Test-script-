#!/bin/bash

##################################################################################################
# Because of the CentOS 6.7 & 7 have something different.
# Based on "reboot-test-1.2-centos7.sh" to modify the script for CentOS 6.7
# Sinper Laing, 2016/03/17
##################################################################################################
# Update: 2016/03/31 ... using whiptail to have screen output in CentOS 7

#
# known limitation :
# 1.) Heitz run "ipmitool fru" will stop the script.It need to analysis the FRU table?
#
# Some configuration before you start the script:
# 1.) remove the kernel parameter "rhgb quiet" and add "vga=775" in /etc/grub.conf
# 2.) add mingetty parameter "--autologin root" in /etc/init/tty.conf 
# 3.) Please make sure the dialog was intalled.
#
#--- Changed history---------------------------------------------------------------
# 4/14: change to 1.3
# 	- Check error sel log and compare hw info, parameter changed to "declare -a"
#	- finish & loop whiptail replace the msgbox by infobox to avoid the SUT hangs in script.
#	- STTG2/TTG2 will run some daemon after rc.loca, so change to put the script in root's .bashrc
#	- some project run "ipmitool fru" will stop the script, mark the fru table releated codes.
#
# 4/13: modify to CentOS 6.7
# The error stop seems not work, need to check the utility's different.
# And, the script run very slow in CentOS 6.7
#1.) there is no "lsscsi" command, replace by "df -h | grep sd"
#2.) Add the counter number for error detected.
#3.) check dialog command available or not???
#
# 4/11: 1.2
# 1.) Can stop the script in loop and finish.
# 2.) Add the script path in .bashrc and will remove after testing finish.
# 3.) Add stop test while hareware compare mismatch or SEL got error.
# 4.) tar add "k" parameter to avoid the same file overwrite issue.
#
# 4/6: 1.1
# 1.) Change to the "Multi-user.target" by command "systemctl set-default multi-user.target"
#	Change to multi-user mode by command "systemctl isolate multi-user.target"
#
# 2.) Configure SUT for auto login.
# edit /etc/systemd/system/getty@tty1.srevice
# add "--autologin root --noclear" in agetty parameter
# 
# 3.) add "sh /PATH/reboot-test-1.1-centos7.sh" in root's .bashrc
# 	#vi /root/.bashrc
#	add "sh /PATH/reboot-test-1.1-centos7.sh" in .bashrc file.
###################################################################################################
# Script start											  #
###################################################################################################
#--------------------------------------------------------------------------------------------------
# System information collection...
#--------------------------------------------------------------------------------------------------
Product=`dmidecode -t 1 | grep "Product Name" | awk '{print $3}'`
Os=`cat /etc/system-release`
CPUname=`lscpu | grep -i 'model name' | awk '{print $3" "$4" "$5" "$6" "$7" "$8" "$9}'`
Mem_Kb=`free | grep Mem | awk '{print $2}'`
Mem_Mb=`expr "$Mem_Kb" / 1024`
BiosVersion=`dmidecode -t 0 | grep "Version" | awk '{print $2}'`
BmcVersion=`ipmitool mc info | grep "Firmware Revision" | awk '{print $4}'`
DateTime=`date`
#
Check_Pass="Pass"
Check_Fail="Fail"
Check_OK="OK"
Check_NA="Not Available"
#
REBOOT_TEST_FOLDER=/var/log/reboot-test
REBOOT_TEST_FILE=/root/reboot-test-1.3-centos7.sh
#
trap sig_handler 15
trap 'trap - INT; kill -s HUP -- -$$' INT
set -e



function create_folder {

	if [ -d "$REBOOT_TEST_FOLDER" ]; then
		whiptail --msgbox "The folder already exist! $REBOOT_TEST_FOLDER" 30 70
	else
		`mkdir "$REBOOT_TEST_FOLDER"`
		`chmod 755 "$REBOOT_TEST_FOLDER"`
		#whiptail --msgbox "The "$REBOOT_TEST_FOLDER" created!" 30 70
	fi

	#export $REBOOT_TEST_FOLDER
	export PCI_info_file="$REBOOT_TEST_FOLDER"/pciinfo
	export CPU_info_file="$REBOOT_TEST_FOLDER"/cpuinfo
	export MEM_info_file="$REBOOT_TEST_FOLDER"/meminfo
	export HDD_info_file="$REBOOT_TEST_FOLDER"/hddinfo
	export USB_info_file="$REBOOT_TEST_FOLDER"/usbinfo
	export SMBIOS_file="$REBOOT_TEST_FOLDER"/smbios
	export SEL_detail="$REBOOT_TEST_FOLDER"/sel-detail
	export DateTime_file="$REBOOT_TEST_FOLDER"/datetime
	export DMESG_file="$REBOOT_TEST_FOLDER"/dmesg
	#export FRU_file="$REBOOT_TEST_FOLDER"/fru-table
	export TARGET_times_file="$REBOOT_TEST_FOLDER"/target_times
	export COUNTER_file="$REBOOT_TEST_FOLDER"/counter
	export WAIT_time_file="$REBOOT_TEST_FOLDER"/wait_time

}	


function reboot_init {
	
	if [ -d "$REBOOT_TEST_FOLDER" ]; then
		TARGET_RUN=$(whiptail --backtitle "Reboot test script init" --title "Enter Target for run" --inputbox "Enter how many times test you want" 30 70 500 --title "Target to run" 3>&1 1>&2 2>&3) 
		echo "$TARGET_RUN" > "$TARGET_times_file"

		WAIT_TIME=$(whiptail --backtitle "Reboot test script init" --title "Set waiting time(seconds)." --inputbox "Enter every time to wait SUT reboot.(seconds):" 30 70 30 --title "Wait time for every cycle" 3>&1 1>&2 2>&3)
		echo "$WAIT_TIME" > "$WAIT_time_file"

		if [ -f "$COUNTER_file" ]; then
			COUNTER=$(`cat "$COUNTER_file"`)
		else
			echo "0" > "$COUNTER_file"
			COUNTER=$((`cat "$COUNTER_file"`))
	 	fi

		lscpu | sed '15,16d' > "$REBOOT_TEST_FOLDER"/cpuinfo
		free | grep Mem | awk '{print $2}' > "$REBOOT_TEST_FOLDER"/meminfo
		lsscsi > "$REBOOT_TEST_FOLDER"/hddinfo
		lsusb > "$REBOOT_TEST_FOLDER"/usbinfo
		lspci > "$REBOOT_TEST_FOLDER"/pciinfo
		dmidecode > "$REBOOT_TEST_FOLDER"/smbios
		ipmitool sel elist > "$REBOOT_TEST_FOLDER"/sel-detail
		#ipmitool fru > "$REBOOT_TEST_FOLDER"/fru-table

		echo "0"
		#Check the files..
		test -f $PCI_info_file && Check_PCI_info_file="OK"  || Check_PCI_info_file="Fail"
		test -f $CPU_info_file && Check_CPU_info_file="OK"  || Check_CPU_info_file="Fail"
		test -f $MEM_info_file && Check_MEM_info_file="OK" || Check_MEM_info_file="Fail"
		test -f $HDD_info_file && Check_HDD_info_file="OK" || Check_HDD_info_file="Fail"
		test -f $USB_info_file && Check_USB_info_file="OK" || Check_USB_info_file="Fail"
		test -f $SMBIOS_file && Check_SMBIOS_file="OK" || Check_SMBIOS_file="Fail"
		test -f $SEL_detail && Check_SEL_detail="OK" || Check_SEL_detail="Fail"
		test -f $DMESG_file && Check_DMESG_file="OK" || Check_DMESG_file="Fail"
		test -f $FRU_file && Check_FRU_file="OK" || Check_FRU_file="Fail"
		test -f $TARGET_times_file && Check_TARGET_times_file="OK" || Check_TARGET_times_file="Fail"
		test -f $COUNTER_file && Check_COUNTER_file="OK" || Check_COUNTER_file=
		test -f $WAIT_time_file && Check_WAIT_time_file="OK" || Check_WAIT_time_file="Fail"


		echo "$REBOOT_TEST_FILE" >> /root/.bashrc
		
		whiptail --backtitle "Reboot test script init" --title "Check files" --msgbox "\n
		Check the files in "$REBOOT_TEST_FOLDER": \n
			CPU file: "$Check_CPU_info_file" \n
			MEM file: "$Check_MEM_info_file" \n
			HDD file: "$Check_HDD_info_file" \n
			USB file: "$Check_USB_info_file" \n
			PCI file: "$Check_PCI_info_file" \n
			SMBIOS  : "$Check_SMBIOS_file" \n
			SEL file: "$Check_SEL_detail" \n
			Counter : "$COUNTER" , File: "$COUNTER_file"\n
			Target  : "$TARGET_RUN", File: "$TARGET_times_file" \n
			WaitTime: "$WAIT_TIME", File: "$WAIT_time_file" \n\n
			" 40 80 

		whiptail --yes-button "Start to run" --no-button "Stop!" --yesno "Are you ready to start testing? Select Yes for start testing, select No to quit." 30 70
		if [ $? = 0 ] ; then
			COUNTER=$((`cat "$COUNTER_file"`))
			if [ "$COUNTER" = 0 ]; then
				COUNTER=$((`expr $COUNTER + 1`))
				echo "$COUNTER" > "$COUNTER_file"
			else
				echo "1" > "$COUNTER_file"
			fi			
			#reboot here for first.
			reboot
		else
			#whiptail --msgbox "you select cancel , STOP the script. " 30 70
			exit

		fi

	else

		whiptail --msgbox "The log folder Not found, "$REBOOT_TEST_FOLDER"." 30 70

	fi

}



if [ -d "$REBOOT_TEST_FOLDER" ]; then	

	PCI_info_file="$REBOOT_TEST_FOLDER"/pciinfo
	CPU_info_file="$REBOOT_TEST_FOLDER"/cpuinfo
	MEM_info_file="$REBOOT_TEST_FOLDER"/meminfo
	HDD_info_file="$REBOOT_TEST_FOLDER"/hddinfo
	USB_info_file="$REBOOT_TEST_FOLDER"/usbinfo
	SMBIOS_file="$REBOOT_TEST_FOLDER"/smbios
	SEL_detail="$REBOOT_TEST_FOLDER"/sel-detail
	DateTime_file="$REBOOT_TEST_FOLDER"/datetime
	DMESG_file="$REBOOT_TEST_FOLDER"/dmesg
	#FRU_file="$REBOOT_TEST_FOLDER"/fru-table
	TARGET_times_file="$REBOOT_TEST_FOLDER"/target_times
	COUNTER_file="$REBOOT_TEST_FOLDER"/counter
	WAIT_time_file="$REBOOT_TEST_FOLDER"/wait_time


	test -f $PCI_info_file && Check_PCI_info_file="OK"  || Check_PCI_info_file="Fail"
	test -f $CPU_info_file && Check_CPU_info_file="OK"  || Check_CPU_info_file="Fail"
	test -f $MEM_info_file && Check_MEM_info_file="OK" || Check_MEM_info_file="Fail"
	test -f $HDD_info_file && Check_HDD_info_file="OK" || Check_HDD_info_file="Fail"
	test -f $USB_info_file && Check_USB_info_file="OK" || Check_USB_info_file="Fail"
	test -f $SMBIOS_file && Check_SMBIOS_file="OK" || Check_SMBIOS_file="Fail"
	test -f $SEL_detail && Check_SEL_detail="OK" || Check_SEL_detail="Fail"
	test -f $DMESG_file && Check_DMESG_file="OK" || Check_DMESG_file="Fail"
	#test -f $FRU_file && Check_FRU_file="OK" || Check_FRU_file="Fail"
	test -f $TARGET_times_file && Check_TARGET_times_file="OK" || Check_TARGET_times_file="Fail"
	test -f $COUNTER_file && Check_COUNTER_file="OK" || Check_COUNTER_file=
	test -f $WAIT_time_file && Check_WAIT_time_file="OK" || Check_WAIT_time_file="Fail"

	# Get Target , wait time, counter.
	TARGET_RUN=$((`cat "$TARGET_times_file"`))
	COUNTER=$((`cat "$COUNTER_file"`))
	WAIT_TIME=$((`cat "$WAIT_time_file"`))





	# Test time reached the Target run times.

	if [ "$COUNTER" -gt "$TARGET_RUN" ]; then
	
		#clear .bashrc setting.
		`sed -i '/dccycle-test/d' /root/.bashrc`
		`sed -i '/reboot-test/d' /root/.bashrc`	

		# package the log files.
		Date=`date +%F`
		`tar cfzk reboot-test-"$Date".tar.gz "$REBOOT_TEST_FOLDER"`
		lslog=`ls *.tar.gz`

		# remove the test folder
		rm -fr "$REBOOT_TEST_FOLDER"

		if [ -f reboot-test-"$Date".tar.gz ]; then
			whiptail --backtitle "Test completed" --title "Testing finished." --infobox " The testing was finished.\n
				Target run: "$TARGET_RUN"\n
				Counter   : "$COUNTER"   \n
				------------------------------------------------\n
				"$err_sel_show" \n\n
				Please remember to check the root's .bashrc setting.\n
				The test log files was located: $REBOOT_TEST_FOLDER \n
				---------------------------------------------------\n
				backup the log folder: please check the file like reboot-test-DATE.tar.gz \n
				If you plan to run another reboot test, please remove whole test log folder: 
				$REBOOT_TEST_FOLDER \n
				" 30 100
			exit
		else
			whiptail --msgbox " The test logs was NOT package into file." 30 70
			exit
		fi


	elif [ "$COUNTER" -eq "0" ]; then
		counter=$((`cat "$COUNTER_file"`))
		if [ "$counter" = 0 ] ; then
			COUNTER=$((`expr $counter + 1`))
			echo "$COUNTER" > "$COUNTER_file"
			#reboot
			whiptail --msgbox "counter is $COUNTER now"  30 70
		else
			whiptail --msgbox "counter not work. counter="$COUNTER", counter file : "$COUNTER_file"	 .." 30 70
			exit
		fi
#


	elif [ "$COUNTER" -le "$TARGET_RUN" ]  && [ "$COUNTER" != 0 ]; then
		

		`lspci > "$PCI_info_file"-"$COUNTER"`
		`lscpu | sed '15,16d' > "$CPU_info_file"-"$COUNTER"`
		`free | grep Mem | awk '{print $2}' > "$MEM_info_file"-"$COUNTER"`
		`lsscsi > "$HDD_info_file"-"$COUNTER"`
		`lsusb > "$USB_info_file"-"$COUNTER"`
		`dmidecode > "$SMBIOS_file"-"$COUNTER"`
		`ipmitool sel elist > "$SEL_detail"-"$COUNTER"`
		`dmesg > "$DMESG_file"-"$COUNTER"`
	#	`ipmitool fru > "$FRU_file"-"$COUNTER"`
	
		#Check SEL for error/warn/lost critical events.
		`ipmitool sel elist >> $REBOOT_TEST_FOLDER/sel-summary`
		declare -a SEL_ERR=`grep -i 'lost\|ecc\|fail\|error\|warn\|unknown\|nmi' "$SEL_detail"-"$COUNTER" > /dev/null 2>&1`
		if [ -z "$SEL_ERR" ]; then
			sel_status="$Check_Pass"
		else
			sel_status="$Check_Fail"
			echo "$SEL_ERR" > "$REBOOT_TEST_FOLDER"/err-sel-"$COUNTER"
			err_sel_show=`awk '{print $7" "$8}' "$REBOOT_TEST_FOLDER"/err-sel-"$COUNTER" `
			whiptail --infobox "The SEL got something wrong, test STOPPED! \n "$err_sel_show"\n\n" 30 70
		fi

		#Compare FRU table
#		ERROR_FRU=`diff "$FRU_file" "$FRU_file"-"$COUNTER" > /dev/null 2>&1`
#		if [ -z "$ERROR_FRU" ]; then
#			fru_status="$Check_Pass"
#		else
#			fru_status="$Check_Fail"
#			whiptail --title "FRU Table mismatch!" --infobox "FRU table mismatch.\n "$ERROR_FRU" " 30 70
#		fi

		#compare SMBIOS table
		declare -a ERROR_SMBIOS=`diff "$SMBIOS_file" "$SMBIOS_file"-"$COUNTER" > /dev/null 2>&1`
		if [ -z "$ERROR_SMBIOS" ]; then
			smbios_status="$Check_Pass"
		else
			smbios_status="$Check_Fail"
			whiptail --title "SMBIOS table mismatch!" --infobox "SMBIOS table mistmatch.\n "$ERROR_SMBIOS"" 30 70
		fi

		#compare CPU info
		declare -a ERROR_CPU=`diff "$CPU_info_file" "$CPU_info_file"-"$COUNTER" > /dev/null 2>&1`
		if [ -z "$ERROR_CPU" ]; then
			cpu_status="$Check_Pass"
		else
			cpu_status="$Check_Fail"
			whiptail --title "CPU Mismatch" --infobox "CPU infomration mismatch.\n "$ERROR_CPU"" 30 70
		fi

		#compare memory info
		declare -a ERROR_MEM=`diff "$MEM_info_file" "$MEM_info_file"-"$COUNTER" > /dev/null 2>&1`
		if [ -z "$ERROR_MEM" ]; then
			mem_status="$Check_Pass"
		else
			mem_status="$Check_Fail"
			whiptail --title "Memory Mismatch" --infobox "Memory information mismatch.\n "$ERROR_MEM" " 30 70
			
		fi

		#compare pci info
		declare -a ERROR_PCI=`diff "$PCI_info_file" "$PCI_info_file"-"$COUNTER" > /dev/null 2>&1`
		if [ -z "$ERROR_PCI" ]; then
			pci_status="$Check_Pass"
		else
			pci_status="$Check_Fail"
			whiptail --title "PCI Mismatch" --infobox "PCI information mismatch.\n "$ERROR_PCI" " 30 70
		fi

		#compare HDD info
		declare -a ERROR_HDD=`diff "$HDD_info_file" "$HDD_info_file"-"$COUNTER" > /dev/null 2>&1`
		if [ -z "$ERROR_HDD" ]; then
			hdd_status="$Check_Pass"
		else
			hdd_status="$Check_Fail"
			whiptail --title "HDD Mismatch" --infobox "HDD information mismatch.\n "$ERROR_HDD" " 30 70
		fi

		#compare USB info
		declare -a ERROR_USB=`diff "$USB_info_file" "$USB_info_file"-"$COUNTER" > /dev/null 2>&1`
		if [ -z "$ERROR_USB" ]; then
			usb_status="$Check_Pass"
		else
			usb_status="$Check_Fail"
			whiptail --title "USB Mismatch" --infobox "USB information mismatch.\n "$ERROR_USB" " 30 70
		fi
		
		TOTAL_PERCENT=$((100*$COUNTER/$TARGET_RUN))

		dialog --pause "Waiting "$WAIT_TIME" second to reboot..\n\n
		----------------------------------------------------\n
		Product: "$Product"\n
		BIOs   : "$BiosVersion" \n
		BMC    : "$BmcVersion" \n\n
		----------------------------------------------------\n
		Running Status : "$TOTAL_PERCENT" % \n\n
		Target Times   : "$TARGET_RUN"  \n
		Test Count     : "$COUNTER"     \n\n
		Hardware device:-----------------------------------------\n
		Check CPU      : "$cpu_status"	\n
		Check Memory   : "$mem_status"	\n
		Check HDD/SSD  : "$hdd_status"	\n
		Check PCI      : "$pci_status"	\n
		Check USB      : "$usb_status"	\n
		Check SMBIOS   : "$smbios_status" \n\n
		Check Error ----------------------------------------\n
		Check SEL logs : "$sel_status"\n 
		\n\n\n\n\n
		====================================================\n
		Press OK to reboot now, press cancel to stop the script.
		" 50 100 "$WAIT_TIME"
		
		COUNTER=$((`expr $COUNTER + 1 `))
		echo "$COUNTER" > "$COUNTER_file"
		ipmitool sel clear &

		if [ "$?" -eq 0 ]; then
			reboot
		else
			exit
		fi

	
	else
		whiptail --msgbox "What happend?\n
		counter is: "$COUNTER"
		target run is: "$TARGET_RUN"
		can NOT get number to compare? \n
		or.. not get the file content?\n
		" 30 70
	fi

else
	create_folder
	reboot_init
fi

