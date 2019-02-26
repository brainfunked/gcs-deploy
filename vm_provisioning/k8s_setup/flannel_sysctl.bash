#!/bin/bash

# Check if the necessary sysctl settings have been applied
output=$(sysctl net.bridge.bridge-nf-call-iptables)
echo "$output"
if [[ $(echo ${output:(-1)}) == 1 ]];
then
  exit 0
else
  echo "sysctl setting 'net.bridge.bridge-nf-call-iptables' not set." >&2
  exit 1
fi

