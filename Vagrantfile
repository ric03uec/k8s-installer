# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  # Create a private network, which allows host-only access to the machine
  # using a specific IP.
  config.vm.define "kube-master" do |master|
    master.vm.box = "trusty64"
    master.vm.network "private_network", ip: "192.168.33.10"
    master.vm.hostname = "kube-master"
  end

  config.vm.define "kube-slave1" do |slave|
    slave.vm.box = "trusty64"
    slave.vm.network "private_network", ip: "192.168.33.11"
    slave.vm.hostname = "kube-slave1"
  end
  
#  config.vm.define "kube-slave2" do |slave|
#    slave.vm.box = "trusty64"
#    slave.vm.network "private_network", ip: "192.168.33.12"
#    slave.vm.hostname = "kube-slave2"
#  end
end
