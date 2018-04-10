#!/system/bin/sh

#set -x

# usage in cmd (Windows 7 and above):
#  0) u need device with UV kernel and root, adb tool. Disable all UV for pure, and reboot device.
#  1) upload script:
#  adb push undervolting_UV_mV_table.sh /sdcard/
#  2) if u need, run benchmark/stability test/cpu monitor app. For example:
#  adb am start -n skynet.cputhrottlingtest/skynet.cputhrottlingtest.MainActivity
#  adb input tap 100 100
#  3) set frequencies list for testing. For example:
#  set list=300000 422400 652800 729600 883200 960000 1036800 1190400 1267200 1497600 1574400 1728000 1958400 2265600
#  or
#  for /f "delims=" %%i in ('adb shell "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies"') do ( set freqlist=%%i)
#  4) start undervolting script for each frequency which find lower voltage:
#  for %a in (%list%) do ( adb wait-for-device & adb shell su -c /system/bin/sh /sdcard/undervolting_UV_mV_table.sh %a & TIMEOUT 60)
#

# initial value for UV offset. recommend -25
UV_SHIFT="-25"
sdcard="/sdcard"

# check root
if [ "$(id -u)" != "0" ]; then echo "This script must be run as root"; exit 1; fi

# Stop Hotplug driver
stop mpdecision
echo 0 > /sys/module/intelli_plug/parameters/intelli_plug_active
echo 0 > /sys/module/msm_hotplug/msm_enabled
echo 0 > /sys/kernel/alucard_hotplug/hotplug_enable
echo 0 > /sys/module/msm_thermal/parameters/enabled
echo 0 > /sys/module/msm_thermal/core_control/enabled

# Run CPU Throttling Test 1.3.3 as stability test
#am force-stop skynet.cputhrottlingtest
#sleep 0.5
#am start -W -n skynet.cputhrottlingtest/skynet.cputhrottlingtest.MainActivity
#sleep 5
#input tap 100 100

# Run CPU Monitor. (exec "adb shell dumpsys window windows | grep 'mCurrentFocus'" to get name)
#am start -n com.glgjing.stark/com.glgjing.stark.HomeActivity # CPU Monitor 
#am start -n com.dp.sysmonitor.app/com.dp.sysmonitor.app.activities.MainActivity # Simple System Monitor

mkdir -p /mnt/temp_png

# Set Frequence to test from argument or from governor max_freq value
if [[ "$1" != "" ]]; then TEST_FREQ=$1; else TEST_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq); fi
NPROC=$(grep processor /proc/cpuinfo|wc -l)
FREQLIST=( $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies) )
TEST_FREQ_MHZ=$(($TEST_FREQ / 1000))

# Save base voltage values
cat /sys/devices/system/cpu/cpu0/cpufreq/UV_mV_table > $sdcard/UV_mV_table_stock.txt
if [[ ${FREQLIST[0]} -eq $TEST_FREQ ]]; then
  rm $sdcard/UV_mV_table.txt
  echo "Base Voltage table:"
  cat $sdcard/UV_mV_table_stock.txt
fi
if [ ! -f $sdcard/UV_mV_table.txt ]; then cp $sdcard/UV_mV_table_stock.txt $sdcard/UV_mV_table.txt; fi

# Set permissions to allow change files
for cpu in $(seq 0 $(($NPROC - 1)))
do
  chmod 0644 /sys/devices/system/cpu/cpu$cpu/online
  echo 1 > /sys/devices/system/cpu/cpu$cpu/online
  chmod 0644 /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor
  echo "performance" > /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor
  chmod 0644 /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq;
  chmod 0644 /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq;
  #echo ${FREQLIST[0]} > /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq;
  #echo $TEST_FREQ > /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq;
  # Unlock all frequencies at msm_cpufreq driver
  if [ -f /sys/kernel/msm_cpufreq_limit/cpufreq_limit ]; then echo ${FREQLIST[-1]} > /sys/kernel/msm_cpufreq_limit/cpufreq_limit; fi
done

# Main loop
while true;
do
  echo
  echo -n "UV offset: $UV_SHIFT "
  
  new_uv_table=""
  # get voltage table and calculate new
  while read in;
  do
  	freq=$(sed -r 's/([0-9]+).* ([0-9]+).*/\1/' <<< "$in")
    voltage=$(sed -r 's/([0-9]+).* ([0-9]+).*/\2/' <<< "$in")
	# calculate new voltage
    if [[ "$freq" -eq "$TEST_FREQ_MHZ" ]]; then
	  voltage=$(expr $UV_SHIFT + $voltage);
	  # log value
      sed -i -r "s/${TEST_FREQ_MHZ}.+/${TEST_FREQ_MHZ}mhz: ${voltage} mV ${UV_SHIFT}/g" $sdcard/UV_mV_table.txt
	fi
	new_uv_table="${new_uv_table} $voltage"
  done <"$sdcard/UV_mV_table_stock.txt"

  sync

  # set new voltage table
  old_voltage_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/UV_mV_table|grep "$TEST_FREQ_MHZ")
  echo -n "$new_uv_table" > /sys/devices/system/cpu/cpu0/cpufreq/UV_mV_table

  # test table updated ok
  voltage_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/UV_mV_table|grep "$TEST_FREQ_MHZ")
  if [[ "$old_voltage_freq" == "$voltage_freq" ]]; then echo "${voltage_freq} No voltage changes "; exit 1; fi
  
  echo -n " Testing ${voltage_freq}"
  for cpu in $(seq 0 $(($NPROC - 1)))
  do
    if [[ ${FREQLIST[0]} -ne $TEST_FREQ ]]; then
	  echo ${FREQLIST[0]} > /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq
	else
	  echo ${FREQLIST[1]} > /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq
	fi
	if [[ $cpu -gt 0 ]]; then echo 0 > /sys/devices/system/cpu/cpu$cpu/online; fi
	sleep 0.1
	echo -n '.'
	echo 1 > /sys/devices/system/cpu/cpu$cpu/online
	echo $TEST_FREQ > /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq
	echo -n '.'
  done
  
  # sleep a bit for stability test new voltage
  duration=15        # seconds
  endtime=$(($(date +%s) + $duration))
  for cpu in $(seq 0 $(($NPROC - 1)))
  do
    # dd if=/dev/mem skip=$((0x804660c)) bs=$((0x10)) count=64000|sha256sum
    # while (($(date +%s) < $endtime)); do timeout 2 sha256sum /dev/zero > /dev/null; done &
	while (($(date +%s) < $endtime)); do timeout 5 screencap -p /mnt/temp_png/screencap_$cpu.png; echo -n '.'; done &
	pchild_pid[$cpu]=$!
	if [[ $(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq") != $(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq") ]];
	then echo "Current CPU frequency wrong: "; $(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq"); exit 1; fi
  done
  sleep $duration
  for cpu in $(seq 1 $instances); do kill -15 ${pchild_pid[$cpu]} > /dev/null 2>&1; done
  
  # Set next UV offset
  UV_SHIFT=$(($UV_SHIFT - 5))
  if [[ $UV_SHIFT -le -300 ]]; then echo "Exceeded UV offset"; exit 1; fi

done
