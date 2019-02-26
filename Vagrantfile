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
MAC_ADDRESSES = YAML.load_file(CONFIG_DIR + 'mac.yml')
HOST_BRIDGE_DEV = "gcsbr0"

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|
  config.vm.synced_folder ".", "/vagrant", type: "rsync"
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
    master.vm.provision "Set master hostname", type: "shell",
    inline: <<-HOSTNAME
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

      node.vm.provision "Set node#{i} hostname", type: "shell",
      inline: <<-HOSTNAME
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
      set -e
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
    set -e
    echo "Disabling swap."
    swapoff -a
    echo "Commenting out the swap entry from fstab."
    sed -ri 's@^(/swapfile.*)$@#\1@' /etc/fstab
  SWAPOFF

  # Disable SELinux since kubelet doesn't support SELinux yet.
  config.vm.provision "Disable selinux", type: "shell", inline: <<-SELINUX
    set -e
    echo "Disabling SELinux."
    setenforce 0
    sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config
    echo "Reboot to disable SELinux, getenforce = '$(getenforce)'."
  SELINUX

  # Change sysctl settings for flannel pod network
  # https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/#pod-network
  config.vm.provision "Install sysctl configuration", type: "shell",
  inline: <<-SYSCTL
    set -e
    cp #{SYNCED_PROVISIONING_DIR}sysctl.d/*.conf /etc/sysctl.d/
    sysctl --system
  SYSCTL

  # The provisioners hereon are to be manually invoked after a `vagrant
  # reload`.
  #
  # IMPORTANT: Run the "k8s master setup" only on the master node and the "k8s
  # node setup" only on the nodes.
  #
  # Given the requirement for reload, following is the most optimal way to run
  # these provisioners first on master, then on nodes once all of the master
  # setup is done. Start with:
  # `vagrant reload --provision-with "kubeadm installation","k8s master setup" master`
  config.vm.provision "kubeadm installation", type: "shell", run: "never",
  inline: <<-KUBEADM
    #{SYNCED_PROVISIONING_DIR}install_kubeadm.bash
  KUBEADM

  # This sets up the kubernetes master node using kubeadm. The `kubeadm join`
  # command that is then needed to be invoked from the nodes is installed in
  # /root/vagrant_logs/join_command. This needs to be copied onto the host
  # running vagrant using:
  # `vagrant ssh -c 'sudo cat /root/vagrant_logs/join_command' > vm_provisioning/k8s_setup/join_command`
  # A `vagrant rsync` then would copy this file to all the nodes, after which
  # the node setup provisioner can be run.
  config.vm.provision "k8s master setup", type: "shell", run: "never",
  inline: <<-K8S_MASTER
    set -e

    #{SYNCED_PROVISIONING_DIR}k8s_setup/flannel_sysctl.bash
    kubeadm config images pull

    echo "Setting up the log directory"
    log_dir=/root/vagrant_logs/
    mkdir -pv $log_dir

    echo "Creating a kubernetes master using kubeadm."
    kubeadm init --pod-network-cidr=10.244.0.0/16 \
      --apiserver-advertise-address=192.168.150.11 2>&1 | \
      tee "${log_dir}kubeadm_init_$(date +%Y%m%d_%H%M%S%Z)"

    echo "Setting up and storing token and ca cert hash for nodes to join."
    kubeadm token create \
      --description "Token for vagrant setup" \
      --print-join-command > "${log_dir}join_command"

    echo "Setting up configuration for kubectl."
    mkdir -pv $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

    echo "Setting up flannel for pod networking."
    kubectl apply -f #{SYNCED_PROVISIONING_DIR}k8s_setup/kube-flannel.yml
    echo "Flannel pod network setup."
  K8S_MASTER

  # This needs to be run on all the nodes via
  # `vagrant reload --provision-with "kubeadm installation","k8s node setup" /node/`
  # AFTER downloading the join_command into the synced folder. The join_command
  # will be synced to the nodes as part of the reload. Omit the "kubeadm
  # installation" provisioner if it had already been executed on the nodes
  # earlier.
  config.vm.provision "k8s node setup", type: "shell", run: "never",
  inline: <<-K8S_NODE
    bash #{SYNCED_PROVISIONING_DIR}k8s_setup/join_command
  K8S_NODE
end
