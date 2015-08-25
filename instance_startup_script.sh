#!/bin/bash

# Copyright 2014 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset

# The following can be used to run master and worker-specific code
function install_master()
{
  local master="${1}"
  local worker_list="${2}"
  local user_list="${3}"

  apt-get install --yes \
      gridengine-client \
      gridengine-qmon \
      gridengine-exec \
      gridengine-master

  for user_i in {user_list}
  do
    # Add your userid as a Grid Engine admin
    sudo sudo -u sgeadmin qconf -am $user_i

    # Add your userid as a Grid Engine user
    qconf -au $user_i users
  done

  # Add the master as submission host
  qconf -as $(hostname)

  # Add the @allhosts group # :wq write the content to the file
  qconf -ahgrp @allhosts <<< :wq 
  # Add the master to the list of hosts
    qconf -aattr hostgroup hostlist $(hostname) @allhosts

    # Register the main queue
    qconf -aq main.q <<< :wq

    # Add the @allhosts group to the main queue
    qconf -aattr queue hostlist @allhosts main.q
    
    # Set the slots attribute to the number of CPUs on each of the nodes (4).
    # On the master host, leave one (4-1 = 3) for the master process
    qconf -aattr queue slots "4, [$(hostname)=3]" main.q

  for worker_i in ${worker_list}
  do
    # Add the worker as a submit host
    qconf -as $worker_i

    # Add the worker to the host list
    qconf -aattr hostgroup hostlist $worker_i @allhosts
  done    
}
readonly -f install_master

function install_worker()
{
  local master="${1}"
  local worker_list="${2}"
  local user_list="${3}"
  
  for worker_i in ${worker_list}
  do
    sudo apt-get install --yes \
      gridengine-client \
      gridengine-exec
  done
}
readonly -f install_worker


# Get the master list
MASTERS=$(/usr/share/google/get_metadata_value attributes/cluster-master)
HOSTNAME=$(hostname --short)
WORKERS=$(/usr/share/google/get_metadata_value attributes/cluster-worker-list)
USERS=$(/usr/share/google/get_metadata_value attributes/cluster-users) 

echo "MASTER instances: ${MASTERS}"
echo "This instance: ${HOSTNAME}"


echo what i need is: 
echo $HOSTNAME
echo USERS

declare I_AM_MASTER=0
for master in $MASTERS; do
  if [[ "${master}" == "$HOSTNAME" ]]; then
    I_AM_MASTER=1
    break
  fi
done

if [[ ${I_AM_MASTER} -eq 1 ]]; then
  #echo "I am a master"
  echo "I am a master"
else
  echo "I am NOT a master"
fi

# Key off existence of the "data" mount point to determine whether
# this is the first boot.
if [[ ! -e /mnt/data ]]; then

  # This is a good place to do things that only need to be done the
  # first time an instance is started.
  mkdir -p /mnt/data

  sudo apt-get update 
  #apt-get update 
  #apt-get install debconf-utils

  if [[ ${I_AM_MASTER} -eq 1 ]]; then # MASTER
      # MASTER node tasks
      install_master "${HOSTNAME}" "${WORKERS}" "${USERS}"
  else
      # WORKER node tasks
      install_worker "${HOSTNAME}" "${WORKERS}" "${USERS}"
  fi

fi

# Get the device name of the "data" disk
DISK_DEV=$(basename $(readlink /dev/disk/by-id/google-$(hostname)-data))

# Mount it
/usr/share/google/safe_format_and_mount \
  -m "mkfs.ext4 -F -q" /dev/${DISK_DEV} /mnt/data

chmod 777 /mnt/data

