#!/bin/bash -e

print_help() {
  echo "Usage: 
  ./kube-installer.sh

  Options:
    --master <master ip address>                       Install kube master with provided IP
    --slave  <slave ip address> <master ip address>    Install kube slave with provided IP 
  "
}

if [[ $# > 0 ]]; then
  if [[ "$1" == "--slave" ]]; then
    export INSTALLER_TYPE=slave
    if [[ ! -z "$2" ]] && [[ ! -z "$3" ]]; then
      export SLAVE_IP=$2
      export MASTER_IP=$3
    else
      echo "Error!! missing Slave IP or Master IP"
      print_help
      exit 1
    fi
  elif [[ "$1" == "--master" ]]; then
    export INSTALLER_TYPE=master
    if [[ ! -z "$2" ]]; then
      export MASTER_IP=$2
    else
      echo "Error!! please provide Master IP"
      print_help
      exit 1
    fi
  else
    print_help
    exit 1
  fi
else
  print_help
  exit 1
fi

echo "####################################################################"
echo "#################### Installing kubernetes $INSTALLER_TYPE #########"
echo "####################################################################"

export KUBERNETES_RELEASE_VERSION=v1.0.1
export ETCD_VERSION=v2.0.5
export DEFAULT_CONFIG_PATH=/etc/default
export ETCD_EXECUTABLE_LOCATION=/usr/bin
export FLANNEL_EXECUTABLE_LOCATION=/usr/bin
export ETCD_PORT=4001
export FLANNEL_SUBNET=10.100.0.0/16
export FLANNEL_VERSION=0.5.2
export DOCKER_VERSION=1.6.2
export KUBERNETES_CLUSTER_ID=k8sCluster
export KUBERNETES_DOWNLOAD_PATH=/tmp
export KUBERNETES_EXTRACT_DIR=$KUBERNETES_DOWNLOAD_PATH/kubernetes
export KUBERNETES_DIR=$KUBERNETES_EXTRACT_DIR/kubernetes
export KUBERNETES_SERVER_BIN_DIR=$KUBERNETES_DIR/server/kubernetes/server/bin
export KUBERNETES_EXECUTABLE_LOCATION=/usr/bin
export KUBERNETES_MASTER_HOSTNAME=$KUBERNETES_CLUSTER_ID-master
export KUBERNETES_SLAVE_HOSTNAME=$KUBERNETES_CLUSTER_ID-slave
export SCRIPT_DIR=$PWD

# Indicates whether the install has succeeded
export is_success=false

install_etcd() {
  if [[ $INSTALLER_TYPE == 'master' ]]; then
    ## download, extract and update etcd binaries ##
    echo 'Installing etcd on master...'
    cd $KUBERNETES_DOWNLOAD_PATH;
    sudo rm -r etcd-$ETCD_VERSION-linux-amd64 || true;
    etcd_download_url="https://github.com/coreos/etcd/releases/download/$ETCD_VERSION/etcd-$ETCD_VERSION-linux-amd64.tar.gz";
    sudo curl -L $etcd_download_url -o etcd.tar.gz;
    sudo tar xzvf etcd.tar.gz && cd etcd-$ETCD_VERSION-linux-amd64;
    sudo mv -v etcd $ETCD_EXECUTABLE_LOCATION/etcd;
    sudo mv -v etcdctl $ETCD_EXECUTABLE_LOCATION/etcdctl;

    etcd_path=$(which etcd);
    if [[ -z "$etcd_path" ]]; then
      echo 'etcd not installed ...'
      return 1
    else
      echo 'etcd successfully installed ...'
      echo $etcd_path;
      etcd --version;
    fi
  else
    echo "Installing for slave, skipping etcd..."
  fi
}

install_docker() {
  echo "Installing docker version $DOCKER_VERSION ..."
  sudo apt-get -yy update
  echo "deb http://get.docker.com/ubuntu docker main" | sudo tee /etc/apt/sources.list.d/docker.list
  sudo apt-key adv --keyserver pgp.mit.edu --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9
  sudo apt-get -yy update
  sudo apt-get -o Dpkg::Options::='--force-confnew' -yy install lxc-docker-$DOCKER_VERSION
  sudo service docker stop || true
}

install_prereqs() {
  echo "Installing network prereqs on slave..."
  sudo apt-get install -yy bridge-utils
}

clear_network_entities() {
  ## remove the docker0 bridge created by docker daemon
  echo 'stopping docker'
  sudo service docker stop || true
  sudo ip link set dev docker0 down  || true
  sudo brctl delbr docker0 || true
}

download_flannel_release() {
  echo 'Downloading flannel release version: $FLANNEL_VERSION'
 
  cd $KUBERNETES_DOWNLOAD_PATH
  flannel_download_url="https://github.com/coreos/flannel/releases/download/v$FLANNEL_VERSION/flannel-$FLANNEL_VERSION-linux-amd64.tar.gz";
  sudo curl --max-time 180 -L $flannel_download_url -o flannel.tar.gz;
  sudo tar xzvf flannel.tar.gz && cd flannel-$FLANNEL_VERSION;
  sudo mv -v flanneld $FLANNEL_EXECUTABLE_LOCATION/flanneld;
}

update_hosts() {
  echo "Updating /etc/hosts..."
  echo "$MASTER_IP $KUBERNETES_MASTER_HOSTNAME" | sudo tee -a /etc/hosts
  echo "$SLAVE_IP $KUBERNETES_SLAVE_HOSTNAME" | sudo tee -a /etc/hosts
  cat /etc/hosts
}

download_kubernetes_release() {
  ## download and extract kubernetes archive ##
  echo 'Downloading kubernetes release version: $KUBERNETES_RELEASE_VERSION'

  cd $KUBERNETES_DOWNLOAD_PATH
  mkdir -p $KUBERNETES_EXTRACT_DIR
  kubernetes_download_url="https://github.com/GoogleCloudPlatform/kubernetes/releases/download/$KUBERNETES_RELEASE_VERSION/kubernetes.tar.gz";
  sudo curl -L $kubernetes_download_url -o kubernetes.tar.gz;
  sudo tar xzvf kubernetes.tar.gz -C $KUBERNETES_EXTRACT_DIR;
}

extract_server_binaries() {
  ## extract the kubernetes server binaries ##
  echo 'Extracting kubernetes server binaries from $KUBERNETES_DIR'
  #cd $KUBERNETES_DIR/server
  sudo su -c "cd $KUBERNETES_DIR/server && tar xzvf $KUBERNETES_DIR/server/kubernetes-server-linux-amd64.tar.gz"
  echo 'Successfully extracted kubernetes server binaries'
}

update_master_binaries() {
  # place binaries in correct folders
  echo 'Updating kubernetes master binaries'
  cd $KUBERNETES_SERVER_BIN_DIR
  sudo cp -vr * $KUBERNETES_EXECUTABLE_LOCATION/
  echo 'Successfully updated kubernetes server binaries to $KUBERNETES_EXECUTABLE_LOCATION'
}

copy_master_binaries() {
  echo "Copying binary files for master components"
  sudo cp -vr $KUBERNETES_SERVER_BIN_DIR/kube-apiserver $KUBERNETES_EXECUTABLE_LOCATION/
  sudo cp -vr $KUBERNETES_SERVER_BIN_DIR/kube-controller-manager $KUBERNETES_EXECUTABLE_LOCATION/
  sudo cp -vr $KUBERNETES_SERVER_BIN_DIR/kube-scheduler $KUBERNETES_EXECUTABLE_LOCATION/
  sudo cp -vr $KUBERNETES_SERVER_BIN_DIR/kubectl $KUBERNETES_EXECUTABLE_LOCATION/
}

copy_master_configs() {
  echo "Copying 'default' files for master components"
  sudo cp -vr $SCRIPT_DIR/config/thirdparty/etcd.conf /etc/init/etcd.conf
  sudo cp -vr $SCRIPT_DIR/config/thirdparty/etcd /etc/default/etcd

  sudo cp -vr $SCRIPT_DIR/config/k8s/kube-apiserver.conf /etc/init/kube-apiserver.conf
  sudo cp -vr $SCRIPT_DIR/config/k8s/kube-apiserver /etc/default/kube-apiserver

  sudo cp -vr $SCRIPT_DIR/config/k8s/kube-scheduler.conf /etc/init/kube-scheduler.conf
  sudo cp -vr $SCRIPT_DIR/config/k8s/kube-scheduler /etc/default/kube-scheduler

  sudo cp -vr $SCRIPT_DIR/config/k8s/kube-controller-manager.conf /etc/init/kube-controller-manager.conf
  sudo cp -vr $SCRIPT_DIR/config/k8s/kube-controller-manager /etc/default/kube-controller-manager
}

copy_slave_binaries() {
  echo "Copying binary files for slave components"
  sudo cp -vr $KUBERNETES_SERVER_BIN_DIR/kubelet $KUBERNETES_EXECUTABLE_LOCATION/
  sudo cp -vr $KUBERNETES_SERVER_BIN_DIR/kube-proxy $KUBERNETES_EXECUTABLE_LOCATION/
}

update_slave_configs() {
  sudo cp -vr $SCRIPT_DIR/config/thirdparty/flanneld.conf /etc/init/flanneld.conf
  echo "FLANNELD_OPTS='-etcd-endpoints=http://$MASTER_IP:$ETCD_PORT -iface=$SLAVE_IP -ip-masq=true'" | sudo tee -a /etc/default/flanneld

  sudo cp -vr $SCRIPT_DIR/config/thirdparty/docker.conf /etc/init/docker.conf
  sudo cp -vr $SCRIPT_DIR/config/thirdparty/docker /etc/default/docker

  # update kubelet config
  sudo cp -vr $SCRIPT_DIR/config/k8s/kubelet.conf /etc/init/kubelet.conf
  echo "export KUBERNETES_EXECUTABLE_LOCATION=/usr/bin" | sudo tee -a /etc/default/kubelet
  echo "KUBELET=$KUBERNETES_EXECUTABLE_LOCATION/kubelet" | sudo tee -a /etc/default/kubelet
  echo "KUBELET_OPTS='--address=0.0.0.0 --port=10250 --max-pods=75 --docker_root=/data --hostname_override=$KUBERNETES_SLAVE_HOSTNAME --api_servers=http://$KUBERNETES_MASTER_HOSTNAME:8080 --enable_server=true --logtostderr=true --v=0 --maximum-dead-containers=10'" | sudo tee -a /etc/default/kubelet

  # update kube-proxy config
  sudo cp -vr $SCRIPT_DIR/config/k8s/kube-proxy.conf /etc/init/kube-proxy.conf
  echo "KUBE_PROXY=$KUBERNETES_EXECUTABLE_LOCATION/kube-proxy" | sudo tee -a  /etc/default/kube-proxy
  echo -e "KUBE_PROXY_OPTS='--master=$KUBERNETES_MASTER_HOSTNAME:8080 --logtostderr=true'" | sudo tee -a /etc/default/kube-proxy
  echo "kube-proxy config updated successfully"
}

remove_redundant_config() {
  # remove the config files for redundant services so that they 
  # dont boot up if server restarts
  if [[ $INSTALLER_TYPE == 'master' ]]; then
    echo 'removing redundant service configs for master ...'

    # removing from /etc/init
    sudo rm -rf /etc/init/kubelet.conf || true
    sudo rm -rf /etc/init/kube-proxy.conf || true

    # removing from /etc/init.d
    sudo rm -rf /etc/init.d/kubelet || true
    sudo rm -rf /etc/init.d/kube-proxy || true

    # removing config from /etc/default
    sudo rm -rf /etc/default/kubelet || true
    sudo rm -rf /etc/default/kube-proxy || true
  else
    echo 'removing redundant service configs for master...'

    # removing from /etc/init
    sudo rm -rf /etc/init/kube-apiserver.conf || true
    sudo rm -rf /etc/init/kube-controller-manager.conf || true
    sudo rm -rf /etc/init/kube-scheduler.conf || true

    # removing from /etc/init.d
    sudo rm -rf /etc/init.d/kube-apiserver || true
    sudo rm -rf /etc/init.d/kube-controller-manager || true
    sudo rm -rf /etc/init.d/kube-scheduler || true

    # removing from /etc/default
    sudo rm -rf /etc/default/kube-apiserver || true
    sudo rm -rf /etc/default/kube-controller-manager || true
    sudo rm -rf /etc/default/kube-scheduler || true
  fi
}

stop_services() {
  # stop any existing services
  if [[ $INSTALLER_TYPE == 'master' ]]; then
    echo 'Stopping master services...'
    sudo service etcd stop || true
    sudo service kube-apiserver stop || true
    sudo service kube-controller-manager stop || true
    sudo service kube-scheduler stop || true
  else
    echo 'Stopping slave services...'
    sudo service flanneld stop || true
    sudo service kubelet stop || true
    sudo service kube-proxy stop || true
  fi
}

start_services() {
  if [[ $INSTALLER_TYPE == 'master' ]]; then
    echo 'Starting master services...'
    sudo service etcd start
    ## No need to start kube-apiserver, kube-controller-manager and kube-scheduler
    ## because the upstart scripts boot them up when etcd starts
  else
    echo 'Starting slave services...'
    sudo service flanneld start
    sudo service kubelet start
    sudo service kube-proxy start
  fi
}

update_flanneld_subnet() {
  ## update the key in etcd which determines the subnet that flannel uses
  exec_cmd "echo 'Waiting for 5 seconds for etcd to start'"
  sleep 5
  $ETCD_EXECUTABLE_LOCATION/etcdctl --peers=http://$MASTER_IP:$ETCD_PORT set coreos.com/network/config '{"Network":"'"$FLANNEL_SUBNET"'"}'
  ret=$?
  if [ $ret == 0 ]; then
    exec_cmd "echo 'Updated flanneld subnet in etcd'"
  else
    exec_cmd "echo 'Failed to flanneld subnet in etcd'"
  fi  
}

check_service_status() {
  if [[ $INSTALLER_TYPE == 'master' ]]; then
    sudo service etcd status
    sudo service kube-apiserver status
    sudo service kube-controller-manager status
    sudo service kube-scheduler status

    echo 'install of kube-master successful'
    is_success=true
  else
    echo 'Checking slave services status...'
    sudo service kubelet status
    sudo service kube-proxy status

    echo 'install of kube-slave successful'
    is_success=true
  fi
}

before_exit() {
  if [ "$is_success" == true ]; then
    echo "Script Completed Successfully";
  else
    echo "Script executing failed";
  fi
}

trap before_exit EXIT
update_hosts

trap before_exit EXIT
stop_services

trap before_exit EXIT
remove_redundant_config

trap before_exit EXIT
download_kubernetes_release

trap before_exit EXIT
extract_server_binaries

if [[ $INSTALLER_TYPE == 'slave' ]]; then
  trap before_exit EXIT
  install_docker

  trap before_exit EXIT
  download_flannel_release

  trap before_exit EXIT
  copy_slave_binaries

  trap before_exit EXIT
  update_slave_configs

  trap before_exit EXIT
  install_prereqs

  trap before_exit EXIT
  clear_network_entities

else
  trap before_exit EXIT
  install_etcd

  trap before_exit EXIT
  copy_master_binaries

  trap before_exit EXIT
  copy_master_configs
fi

trap before_exit EXIT
start_services

trap before_exit EXIT
check_service_status

if [[ $INSTALLER_TYPE == 'master' ]]; then
  update_flanneld_subnet
fi

echo "Kubernetes $INSTALLER_TYPE install completed"
