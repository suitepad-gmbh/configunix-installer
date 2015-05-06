# Configunix Installer

This installer and especially the first steps only apply to Ubuntu. Please adapt
accordingly.

## Steps

1. Set up hostname on your new Puppet Master and restart machine.

  ```shell
  HOSTNAME=puppet.example.com
  sudo hostname $HOSTNAME
  sudo echo $HOSTNAME > /etc/hostname
  sudo init 6
  ```

2. Install current Puppet version

  ```shell
  sudo -i
  wget https://apt.puppetlabs.com/puppetlabs-release-trusty.deb
  dpkg -i puppetlabs-release-trusty.deb
  echo "
  # /etc/apt/preferences.d/00-puppet.pref
  Package: puppet puppet-common
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
  git clone git@...
  ```

4. Install Puppet modules

  ```shell
  cd ~/configunix-installer
  puppet module install puppetlabs-ntp --version 3.3.0 --modulepath ./modules
  puppet module install maestrodev-rvm --version 1.11.0 --modulepath ./modules
  puppet module install jfryman-nginx --version 0.2.6 --modulepath ./modules
  puppet module install zooz-puppet --version 0.0.1 --modulepath ./modules
   ```

5. Install Configunix

  ```shell
  sudo -i
  cd ~/configunix-installer
  puppet apply configunix.pp --modulepath ./modules
  ```
