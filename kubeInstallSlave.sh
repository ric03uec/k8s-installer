#!/bin/bash -e
<%
/*
#
# Shippable kubernetes slave installer
#
# Required env vars:
#
# NODE_TYPE
# type of node e.g. ubuntu1204/fedora etc
# 
# MASTER_IP
# ip address of master node. This is the IP 
# slaves will use to connect to master
#
# SLAVE_IP
# ip address of the slave.
#
# PORTS_LIST
# list of ports that should be available to the slave
#
# KUBERNETES_RELEASE_VERSION
# release version of kubernetes to install
# 
# KUBERNETES_CLUSTER_ID
# uuid of the kubernetes cluster
#
########################################

*/
%>

# Export environment variables
<% _.each(scriptData.environmentVariables, function(e) { %>
export <%= e %>;
<% }); %>
# End of environment exports

export DEFAULT_CONFIG_PATH=/etc/default
export KUBERNETES_DOWNLOAD_PATH=/tmp
export ETCD_PORT=4001
export KUBERNETES_EXTRACT_DIR=$KUBERNETES_DOWNLOAD_PATH/kubernetes
export KUBERNETES_DIR=$KUBERNETES_EXTRACT_DIR/kubernetes
export KUBERNETES_SERVER_BIN_DIR=$KUBERNETES_DIR/server/kubernetes/server/bin
export KUBERNETES_EXECUTABLE_LOCATION=/usr/bin
export KUBERNETES_MASTER_HOSTNAME=$KUBERNETES_CLUSTER_ID-master
export KUBERNETES_SLAVE_HOSTNAME=$KUBERNETES_CLUSTER_ID-slave
export FLANNEL_EXECUTABLE_LOCATION=/usr/bin
export shippable_group_name="kube-install-slave"
export MAX_FILE_DESCRIPTORS=900000
export MAX_WATCHERS=524288
export MAX_CONNECTIONS=196608
export CONNECTION_TIMEOUT=500
export ESTABLISHED_CONNECTION_TIMEOUT=86400

# Indicates whether the install has succeeded
export is_success=false

######################### REMOTE COPY SECTION ##########################
########################################################################
## SSH variables ###
export NODE_SSH_IP=$SLAVE_IP
export NODE_SSH_PORT=22
export NODE_SSH_USER=shippable
export NODE_SSH_PRIVATE_KEY=$NODE_SSH_PRIVATE_KEY

## Read command line args ###
block_uuid=$1
script_uuid=$2

copy_kube_slave_install_script() {
  echo "copying kernel install script to remote host: $NODE_SSH_IP"
  script_folder="/tmp/$block_uuid"
  script_name="$block_uuid-$script_uuid.sh"
  script_path="/tmp/$block_uuid/$script_name"
  node_key_path=$script_folder/node_key

  copy_key=$(echo -e "$NODE_SSH_PRIVATE_KEY"  > $node_key_path)
  chmod_cmd="chmod -cR 600 $node_key_path"
  chmod_out=$($chmod_cmd)

  echo "Removing any host key if present"
  remove_key_cmd="ssh-keygen -f '$HOME/.ssh/known_hosts' -R $NODE_SSH_IP"
  {
    eval $remove_key_cmd
  } || {
    echo "Key not present for the host: $NODE_SSH_IP"
  }

  copy_cmd="rsync -avz -e 'ssh -o StrictHostKeyChecking=no -o NumberOfPasswordPrompts=0 -p $NODE_SSH_PORT -i $node_key_path -C -c blowfish' $script_folder $NODE_SSH_USER@$NODE_SSH_IP:/tmp"
  echo "executing $copy_cmd"
  copy_cmd_out=$(eval $copy_cmd)
  echo $copy_cmd_out

  mkdir_cmd="ssh -o StrictHostKeyChecking=no -o NumberOfPasswordPrompts=0 -p $NODE_SSH_PORT -i $node_key_path $NODE_SSH_USER@$NODE_SSH_IP mkdir -p $script_folder"
  echo "creating script directory: $mkdir_cmd"
  create_dir_out=$(eval $mkdir_cmd)
  echo $create_dir_out

  execute_cmd="ssh -o StrictHostKeyChecking=no -o NumberOfPasswordPrompts=0 -p $NODE_SSH_PORT -i $node_key_path $NODE_SSH_USER@$NODE_SSH_IP sudo $script_path"
  echo "executing command: $execute_cmd"
  eval $execute_cmd

}

######################### REMOTE COPY SECTION ENDS ##########################

copy_configs() {
  echo "copying config files "
  script_folder=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
  <% _.each(setupFiles, function(e) { %>
    copy_cmd="sudo cp -vr $script_folder/<%= e.name %> <%= e.installPath %>"
    exec_cmd "$copy_cmd"
  <% }); %>
}

#
# Prints the command start and end markers with timestamps
# and executes the supplied command
#
exec_cmd() {
  cmd=$@
  cmd_uuid=$(python -c 'import uuid; print str(uuid.uuid4())')
  cmd_start_timestamp=`date +"%s"`
  echo "__SH__CMD__START__|{\"type\":\"cmd\",\"sequenceNumber\":\"$cmd_start_timestamp\",\"id\":\"$cmd_uuid\"}|$cmd"
  eval "$cmd"
  cmd_status=$?
  if [ "$2" ]; then
    echo $2;
  fi

  cmd_end_timestamp=`date +"%s"`
  echo "__SH__CMD__END__|{\"type\":\"cmd\",\"sequenceNumber\":\"$cmd_start_timestamp\",\"id\":\"$cmd_uuid\",\"completed\":\"$cmd_status\"}|$cmd"
  return $cmd_status
}

exec_grp() {
  group_name=$1
  group_uuid=$(python -c 'import uuid; print str(uuid.uuid4())')
  group_start_timestamp=`date +"%s"`
  echo "__SH__GROUP__START__|{\"type\":\"grp\",\"sequenceNumber\":\"$group_start_timestamp\",\"id\":\"$group_uuid\"}|$group_name"
  eval "$group_name"
  group_status=$?
  group_end_timestamp=`date +"%s"`
  echo "__SH__GROUP__END__|{\"type\":\"grp\",\"sequenceNumber\":\"$group_end_timestamp\",\"id\":\"$group_uuid\",\"completed\":\"$group_status\"}|$group_name"
}

start_exec_grp() {
  group_name=$1
  group_uuid=$(python -c 'import uuid; print str(uuid.uuid4())')
  group_start_timestamp=`date +"%s"`
  echo "__SH__GROUP__START__|{\"type\":\"grp\",\"sequenceNumber\":\"$group_start_timestamp\",\"id\":\"$group_uuid\"}|$group_name"
}

end_exec_grp() {
  group_end_timestamp=`date +"%s"`
  echo "__SH__GROUP__END__|{\"type\":\"grp\",\"sequenceNumber\":\"$group_end_timestamp\",\"id\":\"$group_uuid\",\"completed\":\"$group_status\"}|$group_name"
}

create_manifests_dir() {
  manifests_dir='/etc/kubernetes/manifests'
  exec_cmd "echo 'Creating kubelet manifests dir: $manifests_dir'"
  exec_cmd "mkdir -p $manifests_dir"
}

enable_forwarding() {
  exec_cmd "echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf"
  exec_cmd "sudo sysctl -p"
}

update_file_limits() {

  ## increase the max number of file descriptors; applied at kernel limit
  exec_cmd "echo 'fs.file-max=$MAX_FILE_DESCRIPTORS' | sudo tee -a /etc/sysctl.conf"
  exec_cmd "sudo sysctl -p"

  ## increase the max files for root user
  exec_cmd "echo '*   hard  nofile  $MAX_FILE_DESCRIPTORS' | sudo tee -a /etc/security/limits.conf"
  exec_cmd "echo '*   soft  nofile  $MAX_FILE_DESCRIPTORS' | sudo tee -a /etc/security/limits.conf"
  exec_cmd "echo '*   hard  nproc $MAX_FILE_DESCRIPTORS' | sudo tee -a /etc/security/limits.conf"
  exec_cmd "echo '*   hard  nproc $MAX_FILE_DESCRIPTORS' | sudo tee -a /etc/security/limits.conf"
  exec_cmd "sudo sysctl -p"
}

update_watchers() {
  ## increase the number of file watcher limits
  exec_cmd "echo $MAX_WATCHERS | sudo tee -a /proc/sys/fs/inotify/max_user_watches"
  exec_cmd "echo 'fs.inotify.max_user_watches=$MAX_WATCHERS' | sudo tee -a /etc/sysctl.conf"
  exec_cmd "sudo sysctl -p"
}

update_connection_limits() {

  ## maximum connection supported by server
  exec_cmd "echo 'net.netfilter.nf_conntrack_max=$MAX_CONNECTIONS' | sudo tee -a /etc/sysctl.conf"

  ## timout for each connection(seconds)
  exec_cmd "echo 'net.netfilter.nf_conntrack_generic_timeout=$CONNECTION_TIMEOUT' | sudo tee -a /etc/sysctl.conf"

  ## timeout of established connection(seconds)
  exec_cmd "echo 'net.netfilter.nf_conntrack_tcp_timeout_established=$ESTABLISHED_CONNECTION_TIMEOUT' | sudo tee -a /etc/sysctl.conf"
}

install_prereqs() {
  exec_cmd "sudo apt-get install -yy bridge-utils"
}

update_hosts() {
  exec_cmd "echo 'updating /etc/hosts to add slave IP entry'"
  exec_cmd "echo '$MASTER_IP master-<%=scriptData.clusterModel.id %>-<%= scriptData.masterNodeModel.id %>' | sudo tee -a /etc/hosts"
  slave_entry="echo '$SLAVE_IP slave-<%= scriptData.clusterModel.id %>-<%= scriptData.nodeModel.id %>' | sudo tee -a /etc/hosts"
  exec_cmd "$slave_entry"
}

clear_network_entities() {
  ## remove the docker0 bridge created by docker daemon
  exec_cmd "echo 'stopping docker'"
  exec_cmd "sudo service docker stop || true"
  exec_cmd "sudo ip link set dev docker0 down  || true"
  exec_cmd "sudo brctl delbr docker0 || true"
}

download_kubernetes_release() {
  ## download and extract kubernetes archive ##
  exec_cmd "echo 'Downloading kubernetes release version: $KUBERNETES_RELEASE_VERSION'"

  cd $KUBERNETES_DOWNLOAD_PATH
  mkdir -p $KUBERNETES_EXTRACT_DIR
  kubernetes_download_url="https://github.com/GoogleCloudPlatform/kubernetes/releases/download/$KUBERNETES_RELEASE_VERSION/kubernetes.tar.gz";
  exec_cmd "sudo curl --max-time 180 -L $kubernetes_download_url -o kubernetes.tar.gz";
  exec_cmd "sudo tar xzvf kubernetes.tar.gz -C $KUBERNETES_EXTRACT_DIR";
}

extract_server_binaries() {
  ## extract the kubernetes server binaries ##
  exec_cmd "echo 'Extracting kubernetes server binaries from $KUBERNETES_DIR'"
  cd $KUBERNETES_DIR/server
  exec_cmd "sudo tar xzvf kubernetes-server-linux-amd64.tar.gz"
  exec_cmd "echo 'Successfully extracted kubernetes server binaries'"
}


update_master_binaries() {
  # place binaries in correct folders
  exec_cmd "echo 'Updating kubernetes master binaries'"
  cd $KUBERNETES_SERVER_BIN_DIR
  exec_cmd "sudo cp -vr * $KUBERNETES_EXECUTABLE_LOCATION/"
  exec_cmd "echo 'Successfully updated kubernetes server binaries to $KUBERNETES_EXECUTABLE_LOCATION'"
}

download_flannel_release() {
  exec_cmd "echo 'Downloading flannel release version: $FLANNEL_VERSION'"
 
  cd $KUBERNETES_DOWNLOAD_PATH
  flannel_download_url="https://github.com/coreos/flannel/releases/download/v$FLANNEL_VERSION/flannel-$FLANNEL_VERSION-linux-amd64.tar.gz";
  exec_cmd "sudo curl --max-time 180 -L $flannel_download_url -o flannel.tar.gz";
  exec_cmd "sudo tar xzvf flannel.tar.gz && cd flannel-$FLANNEL_VERSION";
  exec_cmd "sudo mv -v flanneld $FLANNEL_EXECUTABLE_LOCATION/flanneld";
}
 
update_flanneld_config() {
  exec_cmd "echo 'updating flanneld config'"
  echo "FLANNELD_OPTS='-etcd-endpoints=http://$MASTER_IP:$ETCD_PORT -iface=$SLAVE_IP -ip-masq=true'" | sudo tee -a /etc/default/flanneld
}

remove_redundant_config() {
  # remove the config files for redundant services so that they dont boot up if 
  # node restarts
  exec_cmd "echo 'removing redundant service configs...'"

  # removing from /etc/init
  exec_cmd "sudo rm -rf /etc/init/kube-apiserver.conf || true"
  exec_cmd "sudo rm -rf /etc/init/kube-controller-manager.conf || true"
  exec_cmd "sudo rm -rf /etc/init/kube-scheduler.conf || true"

  # removing from /etc/init.d
  exec_cmd "sudo rm -rf /etc/init.d/kube-apiserver || true"
  exec_cmd "sudo rm -rf /etc/init.d/kube-controller-manager || true"
  exec_cmd "sudo rm -rf /etc/init.d/kube-scheduler || true"

  # removing from /etc/default
  exec_cmd "sudo rm -rf /etc/default/kube-apiserver || true"
  exec_cmd "sudo rm -rf /etc/default/kube-controller-manager || true"
  exec_cmd "sudo rm -rf /etc/default/kube-scheduler || true"
}

stop_services() {
  # stop any existing services
  exec_cmd "echo 'Stopping slave services...'"
  exec_cmd "sudo service kubelet stop || true"
  exec_cmd "sudo service kube-proxy stop || true"
}

start_services() {
  exec_cmd "echo 'Starting slave services...'"

  exec_cmd "sudo service flanneld restart || true"
  exec_cmd "sudo service kubelet restart || true "
  exec_cmd "sudo service kube-proxy restart || true"
}

check_service_status() {
  exec_cmd "echo 'Checking slave services status...'"
  sleep 3
  exec_cmd "sudo service flanneld status || true"
  exec_cmd "sudo service kubelet status || true"
  exec_cmd "sudo service kube-proxy status || true"

  is_success=true
}

log_service_versions() {
  exec_cmd "flanneld --version"
  exec_cmd "sudo kubelet --version"
  exec_cmd "sudo kube-proxy --version"
  exec_cmd "sudo docker version"
  exec_cmd "sudo docker info"
}

before_exit() {
  ## flush out any remaining console
  echo $1
  echo $2
  if [ "$is_success" == true ]; then
    echo "__SH__SCRIPT_END_SUCCESS__";
  else
    echo "__SH__SCRIPT_END_FAILURE__";
  fi
}

if [ ! -z $block_uuid ] && [ ! -z $script_uuid ]; then
  copy_kube_slave_install_script
else
  trap before_exit EXIT
  exec_grp "create_manifests_dir"

  trap before_exit EXIT
  exec_grp "copy_configs"

  trap before_exit EXIT
  exec_grp "enable_forwarding"

  trap before_exit EXIT
  exec_grp "update_file_limits"

  trap before_exit EXIT
  exec_grp "update_watchers"

  trap before_exit EXIT
  exec_grp "update_connection_limits"

  trap before_exit EXIT
  exec_grp "install_prereqs"

  trap before_exit EXIT
  exec_grp "update_hosts"

  trap before_exit EXIT
  exec_grp "clear_network_entities"

  trap before_exit EXIT
  exec_grp "stop_services"

  trap before_exit EXIT
  exec_grp "download_kubernetes_release"

  trap before_exit EXIT
  exec_grp "download_flannel_release"

  trap before_exit EXIT
  exec_grp "extract_server_binaries"

  trap before_exit EXIT
  exec_grp "update_master_binaries"

  trap before_exit EXIT
  exec_grp "update_flanneld_config"

  trap before_exit EXIT
  exec_grp "remove_redundant_config"

  trap before_exit EXIT
  exec_grp "start_services"

  trap before_exit EXIT
  exec_grp "check_service_status"

  trap before_exit EXIT
  exec_grp "log_service_versions"

  echo "Kubernetes slave install completed"
fi
