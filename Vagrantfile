# -*- mode: ruby -*-
# vi: set ft=ruby :

# IMPORTANT: It is assumed that this file is used from the git checkout
# without modifying the directory structure. This isn't a good idea for
# production setups, but this is a development setup, so..
WORKING_DIR = Dir.pwd + '/'
CONFIG_DIR = WORKING_DIR + 'conf/'
PROVISIONING_DIR_NAME = 'vm_provisioning/'
PROVISIONING_DIR = WORKING_DIR + PROVISIONING_DIR_NAME

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.synced_folder ".", "/home/vagrant/sync", disabled: true
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
      dev: "gcsbr0",
      type: "bridge",
      mac: "52:54:00:a3:25:0a",
      ip: "192.168.150.11"

    # Vagrant documentation isn't fully clear on what exactly is done when
    # vagrant is set to manage the hostname. This option is thus better.
    # /etc/hosts file is setup for all VMs with a common provisioner later.
    master.vm.provision "Set hostname", type: "shell", inline: <<-HOSTNAME
      hostnamectl set-hostname master
    HOSTNAME
  end

  # Add cluster hosts' IPs to /etc/hosts
  config.vm.provision "Setup /etc/hosts", type: "shell" do |s|
    hosts = File.read PROVISIONING_DIR + 'hosts'
    s.inline = <<-HOSTS
      echo "Writing cluster hosts to /etc/hosts."
      echo -e "#{hosts}" >> /etc/hosts
      echo "/etc/hosts updated."
    HOSTS
  end

  # Enable provisioning with a shell script. Additional provisioners such as
  # Puppet, Chef, Ansible, Salt, and Docker are also available. Please see the
  # documentation for more information about their specific syntax and use.
  config.vm.provision "Configure SSH keys", type: "shell" do |s|
    ssh_pub_key_file = Dir.home + '/.ssh/id_rsa.pub'
    ssh_pub_key = ""
    ssh_dir = ".ssh"
    authorized_keys_file = ssh_dir + '/authorized_keys'

    if File.file? ssh_pub_key_file
      ssh_pub_key = File.readlines(ssh_pub_key_file).first.strip
    else
      puts "No SSH key found."
    end

    s.inline = <<-SSH_KEY
      if grep -sq "#{ssh_pub_key}" /home/vagrant/"#{authorized_keys_file}"; then
        echo "SSH key already provisioned for vagrant user."
      else
        echo "Provisioning SSH key for vagrant user."
        mkdir -p /home/vagrant/"#{ssh_dir}"
        touch /home/vagrant/"#{authorized_keys_file}"
        echo "#{ssh_pub_key}" >> /home/vagrant/"#{authorized_keys_file}"
        chmod 644 /home/vagrant/"#{authorized_keys_file}"
        chmod 700 /home/vagrant/"#{ssh_dir}"
        chown -R vagrant:vagrant /home/vagrant/"${ssh_dir}"
        echo "SSH key successfully provisioned for vagrant user."
      fi
      if grep -sq "#{ssh_pub_key}" /root/"#{authorized_keys_file}"; then
        echo "SSH key already provisioned for root user."
      else
        echo "Provisioning SSH Key for root user."
        mkdir -p /root/"#{ssh_dir}"
        touch /root/"#{authorized_keys_file}"
        echo "#{ssh_pub_key}" >> /root/"#{authorized_keys_file}"
        chmod 644 /root/"#{authorized_keys_file}"
        chmod 700 /root/"#{ssh_dir}"
        chown -R root:root /root/"#{ssh_dir}"
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

  # Disable SELinux since kubelet doesn't support SELinux yet.
  # Doing it here instead of during kubeadm installation, because this is
  # executed before a `vagrant reload` that precedes the kubeadm installation.
  config.vm.provision "Disable selinux", type: "shell", inline: <<-SELINUX
    echo "Disabling SELinux."
    setenforce 0
    sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config
    echo "Reboot to disable SELinux, getenforce = '$(getenforce)'."
  SELINUX

  # Copy over the scripts for deploying kubernetes
  config.vm.provision "Copy provisioning directory", type: "file",
    source: PROVISIONING_DIR,
    destination: "$HOME/#{PROVISIONING_DIR_NAME}"

  # The provisioners hereon are to be manually invoked after a `vagrant reload`
  config.vm.provision "kubeadm installation", type: "shell", run: "never", inline: <<-KUBEADM
    cd "/home/vagrant/#{PROVISIONING_DIR_NAME}"
    ./install_kubeadm.bash
  KUBEADM
end
