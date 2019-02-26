# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'yaml'

# IMPORTANT: It is assumed that this file is used from the git checkout
# without modifying the directory structure. This isn't a good idea for
# production setups, but this is a development setup, so..
WORKING_DIR = Dir.pwd + '/'
VAGRANT_DIR = '/vagrant/'
CONFIG_DIR = 'conf/'
PROVISIONING_DIR = 'vm_provisioning/'
SYNCED_PROVISIONING_DIR = VAGRANT_DIR + PROVISIONING_DIR
SYNCED_PROVISIONING_DATA_DIR = SYNCED_PROVISIONING_DIR + 'run/'
MAC_ADDRESSES = YAML.load_file(CONFIG_DIR + 'mac.yml')
HOST_BRIDGE_DEV = "gcsbr0"

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|
  config.vm.synced_folder ".", "/vagrant", \
    owner: "root", group: "root", \
    mount_options: ["exec"]
  config.vm.box = "centos/7"

  # Disable automatic box update checking. If you disable this, then
  # boxes will only be checked for updates when the user runs
  # `vagrant box outdated`. This is not recommended.
  config.vm.box_check_update = false

  config.vm.define "master" do |master|
    master.vm.provider :libvirt do |lv|
      lv.default_prefix = "gcs"
      lv.cpus = 2
      lv.memory = 2048
      lv.nested = true
    end

    # This is the network the cluster can be contacted over to run tests
    # against. This network is just locally routed and not configured for DHCP.
    # This is because vagrant-libvirt sets up the management network which sets
    # up its own DHCP server and NAT. This DHCP server is unrestricted and
    # conflicts with any other DHCP server on the system. Management network
    # doesn't allow much configurability and basically didn't work at all when
    # manually configured.
    master.vm.network "public_network",
      dev:  HOST_BRIDGE_DEV,
      type: "bridge",
      mac:  MAC_ADDRESSES['master'],
      ip:   "192.168.150.11"

    # Vagrant documentation isn't fully clear on what exactly is done when
    # vagrant is set to manage the hostname. This option is thus better.
    # /etc/hosts file is setup for all VMs with a common provisioner later.
    master.vm.provision "Set master hostname", type: "shell", inline: <<-HOSTNAME
      hostnamectl set-hostname master
    HOSTNAME
  end

  (1..3).each do |i|
    config.vm.define "node#{i}" do |node|
      node.vm.provider :libvirt do |lv|
        lv.default_prefix = "gcs"
        lv.cpus = 2
        lv.memory = 2048
        lv.nested = true
      end

      node.vm.network "public_network",
        dev:  HOST_BRIDGE_DEV,
        type: "bridge",
        mac:  MAC_ADDRESSES["node#{i}"],
        ip:   "192.168.150.2#{i}"

      node.vm.provision "Set node#{i} hostname", type: "shell", inline: <<-HOSTNAME
        hostnamectl set-hostname node#{i}
      HOSTNAME
    end
  end

  # Add cluster hosts' IPs to /etc/hosts
  config.vm.provision "Setup /etc/hosts", type: "shell" do |s|
    hosts = File.read WORKING_DIR + PROVISIONING_DIR + 'hosts'
    s.inline = <<-HOSTS
      echo "Writing cluster hosts to /etc/hosts."
      echo -e "#{hosts}" >> /etc/hosts
      echo "/etc/hosts updated."
    HOSTS
  end

  # Setup SSH keys to allow the root user on the hypervisor to SSH in
  config.vm.provision "Configure SSH keys", type: "shell" do |s|
    ssh_pub_key_file = Dir.home + '/.ssh/id_rsa.pub'
    ssh_pub_key = ""
    ssh_dir = ".ssh"
    authorized_keys_file = ssh_dir + '/authorized_keys'

    if File.file? ssh_pub_key_file
      ssh_pub_key = File.readlines(ssh_pub_key_file).first.strip
    else
      STDERR.puts "No SSH public key found at #{ssh_pub_key_file}."
      exit 1
    end

    s.inline = <<-SSH_KEY
      if grep -sq #{ssh_pub_key} /home/vagrant/#{authorized_keys_file}; then
        echo "SSH key already provisioned for vagrant user."
      else
        echo "Provisioning SSH key for vagrant user."
        mkdir -p /home/vagrant/#{ssh_dir}
        touch /home/vagrant/#{authorized_keys_file}
        echo #{ssh_pub_key} >> /home/vagrant/#{authorized_keys_file}
        chmod 644 /home/vagrant/#{authorized_keys_file}
        chmod 700 /home/vagrant/#{ssh_dir}
        chown -R vagrant:vagrant /home/vagrant/${ssh_dir}
        echo "SSH key successfully provisioned for vagrant user."
      fi
      if grep -sq #{ssh_pub_key} /root/#{authorized_keys_file}; then
        echo "SSH key already provisioned for root user."
      else
        echo "Provisioning SSH Key for root user."
        mkdir -p /root/#{ssh_dir}
        touch /root/#{authorized_keys_file}
        echo #{ssh_pub_key} >> /root/#{authorized_keys_file}
        chmod 644 /root/#{authorized_keys_file}
        chmod 700 /root/#{ssh_dir}
        chown -R root:root /root/#{ssh_dir}
      fi
      if grep -sqE '^PermitRootLogin[[:space:]]+yes' /etc/ssh/sshd_config; then
        echo "Root login over SSH already enabled."
      else
        echo "Enabling root login over SSH."
        sed -i '/^\#PermitRootLogin/cPermitRootLogin yes' /etc/ssh/sshd_config
        echo "SSH PermitRootLogin set to '$(grep '^PermitRootLogin' /etc/ssh/sshd_config)'"
      fi
      exit 0
    SSH_KEY
  end

  # Doing some system configuration here instead of during kubeadm
  # installation, because this is executed before a `vagrant reload` that
  # precedes the kubeadm installation.

  # Disable swap since kubeadm asks for it
  config.vm.provision "Disable swap", type: "shell", inline: <<-SWAPOFF
    echo "Disabling swap."
    swapoff -a
    echo "Commenting out the swap entry from fstab."
    sed -ri 's@^(/swapfile.*)$@#\1@' /etc/fstab
  SWAPOFF

  # Disable SELinux since kubelet doesn't support SELinux yet.
  config.vm.provision "Disable selinux", type: "shell", inline: <<-SELINUX
    echo "Disabling SELinux."
    setenforce 0
    sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config
    echo "Reboot to disable SELinux, getenforce = '$(getenforce)'."
  SELINUX

  # Change sysctl settings for flannel pod network
  # https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/#pod-network
  config.vm.provision "Install sysctl configuration", type: "shell", inline: <<-SYSCTL
    cp #{SYNCED_PROVISIONING_DIR}sysctl.d/*.conf /etc/sysctl.d/
    sysctl --system
  SYSCTL

  # The provisioners hereon are to be manually invoked after a `vagrant reload`
  config.vm.provision "kubeadm installation", type: "shell", run: "never", inline: <<-KUBEADM
    #{SYNCED_PROVISIONING_DIR}install_kubeadm.bash
  KUBEADM

  config.vm.provision "k8s master setup", type: "shell", run: "never", inline: <<-K8S_MASTER
    set -e

    #{SYNCED_PROVISIONING_DIR}k8s_setup/flannel_sysctl.bash
    kubeadm config images pull

    mkdir -pv #{SYNCED_PROVISIONING_DATA_DIR}
    echo "Creating a kubernetes master using kubeadm."
    kubeadm init --pod-network-cidr=10.244.0.0/16 \
      --apiserver-advertise-address=192.168.150.11 2>&1 | \
      tee "#{SYNCED_PROVISIONING_DATA_DIR}kubeadm_init_$(date +%Y%m%d_%H%M%S%Z)"

    echo "Setting up flannel for pod networking."
    kubectl apply -f #{SYNCED_PROVISIONING_DIR}k8s_setup/kube-flannel.yml
    echo "Flannel pod network setup."

    echo "Setting up and storing token and ca cert hash for nodes to join."
    kubeadm token create > #{SYNCED_PROVISIONING_DATA_DIR}token
    ( \
      openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
        openssl rsa -pubin -outform der 2>/dev/null | \
        openssl dgst -sha256 -hex | sed 's/^.* //' \
    ) > #{SYNCED_PROVISIONING_DATA_DIR}ca_cert_hash
  K8S_MASTER
end
