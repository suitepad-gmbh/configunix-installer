# Configunix Installer

This installer and especially the first steps only apply to Ubuntu. Please adapt
accordingly.

## Steps

1. Set up hostname on your new Puppet Master and restart machine.

  ```shell
  sudo -i
  HOSTNAME=puppet.example.com
  hostname $HOSTNAME
  echo $HOSTNAME > /etc/hostname
  echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
  init 6
  ```

2. Install current Puppet version

  ```shell
  sudo -i
  wget https://apt.puppetlabs.com/puppetlabs-release-trusty.deb
  dpkg -i puppetlabs-release-trusty.deb
  echo "
  # /etc/apt/preferences.d/00-puppet.pref
  Package: puppet puppet-common puppetmaster puppetmaster-common
  Pin: version 3.7*
  Pin-Priority: 501
  " >> /etc/apt/preferences.d/00-puppet.pref
  apt-get update
  apt-get -y install puppet
  ```

3. Check out Configunix Installer repository

  ```shell
  sudo -i
  cd ~
  git clone https://github.com/suitepad-gmbh/configunix-installer.git
  ```

4. Install Puppet modules

  ```shell
  cd ~/configunix-installer
  puppet module install puppetlabs-ntp --version 3.3.0 --modulepath ./modules
  puppet module install jfryman-nginx --version 0.2.6 --modulepath ./modules
  puppet module install DracoBlue-rvm --version 0.3.0 --modulepath ./modules
  puppet module install puppetlabs-vcsrepo --version 1.2.0 --modulepath ./modules
  puppet module install puppetlabs-postgresql --version 4.3.0 --modulepath ./modules
  puppet module install puppetlabs-nodejs --version 0.7.1 --modulepath ./modules
  ```

5. Install Configunix

  ```shell
  sudo -i
  cd ~/configunix-installer
  puppet apply install_puppetmaster_unicorn.pp --modulepath ./modules
  puppet apply install_configunix.pp --modulepath ./modules --parser current
  ```

  Alternatively, you can install the Puppetmaster running behind Puma:

  ```shell
  sudo -i
  cd ~/configunix-installer
  puppet apply install_puppetmaster_puma.pp --modulepath ./modules
  puppet apply install_configunix.pp --modulepath ./modules --parser current
  ```

6. Write your manifests

Manifests are to be placed in `/etc/puppet/environments` in a sub folder matching
your environment name. At least you should a `production` in there, because
this is the default for Puppet agents.
