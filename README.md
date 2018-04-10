# Android-Undervolting-Script
sh script for undervolting Android CPU over ADB

# usage in cmd (Windows 7 and above):
#  0) u need device with UV kernel and root, adb tool. Disable all UV for pure, and reboot device.
#  1) upload script:
#  adb push undervolting_UV_mV_table.sh /sdcard/
#  2) if u need, run benchmark/stability test/cpu monitor app. For example:
#  adb am start -n skynet.cputhrottlingtest/skynet.cputhrottlingtest.MainActivity
#  adb input tap 100 100
#  adb shell su -c /system/bin/sh /sdcard/undervolting_UV_mV_table.sh 1728000
#  3) set frequencies list for testing. For example:
#  set list=300000 422400 652800 729600 883200 960000 1036800 1190400 1267200 1497600 1574400 1728000 1958400 2265600
#  or
#  for /f "delims=" %%i in ('adb shell "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies"') do ( set freqlist=%%i)
#  4) start undervolting script for each frequency which find lower voltage:
#  for %a in (%list%) do ( adb wait-for-device & adb shell su -c /system/bin/sh /sdcard/undervolting_UV_mV_table.sh %a & TIMEOUT 60)
