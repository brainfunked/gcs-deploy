#!/bin/bash

# Abort immediately on failure.
# DO NOT MODIFY. The script behaviour depends upon this being set.
set -e

# Enable/disable shell debugging.
#set -x

###################################################################
### Configuration variables

## Package dependencies to be installed.
PACKAGES=(
  dnsmasq                         # DNS server
  util-linux                      # Provides `uuidgen`
  gettext                         # Provides `envsubst`
  bridge-utils                    # Provides `brctl`
  bind-utils                      # Provides `host`
  net-tools                       # Provides `netstat`
)

## Executable dependencies to verify only existence of explicitly.
# If not executable, this script will abort because `set -e`.
EXECUTABLES=(uuidgen envsubst brctl host netstat ip ifup awk)

## Configuration for the network bridge the GCS cluster will be setup against.
BRIDGE_UUID="" # UUID is filled in once uuidgen availability is validated
BRIDGE_NAME=gcsbr0
BRIDGE_IP="192.168.150.1"
# Netmask is hardcoded in the template to simplify the IP assignment
# validation for the bridge.

###################################################################

### Exit codes

# 254: Runtime prerequisite not met
# 253: Dependency unsatisfied
# 252: Explicit validation failed on something the script setup

###################################################################

if [[ $(id -u) == 0 ]]
then
  echo "[DEBUG] Running with root privileges, proceeding."
else
  echo "[ERROR] Need root privileges to proceed."
  exit 254
fi

if grep -sqi 'centos.*release 7' /etc/redhat-release
then
  echo "[DEBUG] Running on CentOS 7, proceeding."
else
  echo "[ERROR] Only CentOS 7 is currently supported."
  exit 254
fi

echo "[INFO] # Setting up virtual networking for GCS VMs."

echo "[INFO] ## Installing dependencies."
yum -y install "${PACKAGES[@]}"
echo "[DEBUG] ## Installed packages: ${PACKAGES[*]}"

echo "[INFO] ## Checking executable dependencies."
declare -a MISSING_DEPS
for package in "${EXECUTABLES[@]}"
do
  if ! which "$package" &> /dev/null
  then
    MISSING_DEPS+=("$package")
  fi
done
if [[ ${#MISSING_DEPS[@]} != 0 ]]
then
  echo "[ERROR] Unsatisfied dependencies for executables: ${MISSING_DEPS[*]}"
  exit 253
fi

echo "[INFO] ## Setting up bridge gcsbr0"
BRIDGE_UUID=$(uuidgen)
export BRIDGE_UUID BRIDGE_NAME BRIDGE_IP

# Fill in the network configuration template and install it
# Fills in the exported variables
envsubst <"host_setup/ifcfg-gcsbr0.tmpl" >"/etc/sysconfig/network-scripts/ifcfg-${BRIDGE_NAME}"

ifup "$BRIDGE_NAME"

if ! ip link ls "$BRIDGE_NAME" &>/dev/null # Check the physical interface
then
  echo "[ERROR] Bridge ${BRIDGE_NAME} not up."
  exit 252
else
  ipaddr=$(ip addr ls dev "$BRIDGE_NAME" | \
    awk "/inet ${BRIDGE_IP//./\\.}/{print \$2;}") # Grab the ip/netmask string
  if [[ $ipaddr == ${BRIDGE_IP}/24 ]] # Check if the IP is as configured
  then
    echo "[DEBUG] Bridge ${BRIDGE_NAME} setup with IP: ${ipaddr}"
  else
    echo "[ERROR] Bridge ${BRIDGE_NAME} does not have the expected IP address."
    echo "[ERROR] Expected IP: ${BRIDGE_IP}, Found: ${ipaddr}"
    exit 252
  fi
fi

echo "[INFO] ## Setting up dnsmasq"

cp host_setup/dnsmasq.conf /etc/dnsmasq.conf
cp host_setup/dnsmasq-gcs.local /etc/dnsmasq.d/gcs.local
cat host_setup/hosts >> /etc/hosts
systemctl enable dnsmasq.service
systemctl restart dnsmasq.service

if [[ ! -z $(netstat -ntlp | grep "${BRIDGE_IP}:53.*dnsmasq") ]]
then
  echo "[DEBUG] dnsmasq listening on ${BRIDGE_IP}:53"
fi

echo "[INFO] ## Setting up NetworkManager to query dnsmasq"

cp host_setup/nm_localdns.conf /etc/NetworkManager/conf.d/localdns.conf
cp host_setup/nm_gcs.conf /etc/NetworkManager/dnsmasq.d/gcs.conf
systemctl reload NetworkManager.service

echo "[INFO] ## Verifying that the DNS setup is successful"
declare -A DNS_FAILED
while read -r ip fqdn alt
do
  # Check if the DNS query for $fqdn returns $ip
  matched_ip=$(host -t A "$fqdn" | grep -oF "$ip")
  # If $ip doesn't match, $matched_ip would be empty, which means failure
  if [[ -z $matched_ip ]]
  then
    DNS_FAILED["$fqdn"]="$ip"
  fi
done

# $DNS_ENABLED should be empty if all FQDNs resolved correctly
if ! [[ ${#DNS_FAILED[@]} -eq 0 ]]
then
  echo "[ERROR] DNS resolution failed."
  failures_string=""
  for key in "${!DNS_FAILED[@]}"
  do
    comma=""
    comma=$([[ ! -z $failures_string ]] && echo ,)
    comma+=" "
    failures_string+="${comma}${fqdn}:${ip}"
  done
  echo "[ERROR] Incorrect results: $failures_string"
  exit 252
fi
