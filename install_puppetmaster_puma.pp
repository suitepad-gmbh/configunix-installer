# Basic NTP
include '::ntp'

# Install Puppet Master
package { 'puppetmaster':
  ensure => 'present',
  require => File['/etc/puppet/puppet.conf']
}

# Puppet config
file { '/etc/puppet/puppet.conf':
  ensure  => 'present',
  owner   => 'root',
  group   => 'root',
  mode    => '0644',
  require => File[
    '/etc/puppet/environments/production',
    '/usr/local/bin/puppet_node_classifier',
    '/etc/sudoers.d/90-puppet-configunix-bridge'
  ],
  content => "[main]
  logdir = /var/log/puppet
  vardir = /var/lib/puppet
  ssldir = /var/lib/puppet/ssl
  rundir = /var/run/puppet
  factpath = \$vardir/lib/facter

  certname = $hostname
  dns_alt_names = $hostname,$fqdn

  parser = future

[master]
  autosign = true
  environmentpath = \$confdir/environments
  node_terminus = exec
  external_nodes = /usr/bin/sudo /usr/local/bin/puppet_node_classifier
"
  }

file { '/etc/puppet/environments/production':
  ensure  => 'directory',
  owner   => 'root',
  group   => 'configunix',
  mode    => '0664'
}

file { '/usr/local/bin/puppet_node_classifier':
  ensure  => 'present',
  owner   => 'root',
  group   => 'root',
  mode    => '0755',
  content => '#!/usr/bin/env bash

su configunix -c "cd ~/api; RAILS_ENV=production ~/.rvm/bin/rvm 2.2.2 do bundle exec ./bin/enc $1"
'
}

file { '/etc/sudoers.d/90-puppet-configunix-bridge':
  ensure  => 'present',
  owner   => 'root',
  group   => 'root',
  content => "puppet ALL=(root) NOPASSWD:/usr/local/bin/puppet_node_classifier\n"
}

file_line { '/etc/default/puppetmaster':
  ensure => present,
  path   => '/etc/default/puppetmaster',
  line   => 'START=no',
  match  => '^START\=yes',
  require => Package['puppetmaster']
}

service { 'puppetmaster':
  ensure => 'stopped',
  require => Package['puppetmaster']
}

# Gem installation for Puppet Master
package { 'ruby-dev': }
package { 'build-essential': }
package { 'libssl-dev': }
package { 'puma':
  provider  => 'gem',
  require   => Package['ruby-dev', 'build-essential', 'libssl-dev']
}

# Create directories for Puppet Master Rack
file { '/usr/share/puppet/rack':
  ensure  => 'directory',
  group   => 'puppet',
  owner   => 'puppet'
}
file { '/usr/share/puppet/rack/puppetmasterd':
  ensure  => 'directory',
  group   => 'puppet',
  owner   => 'puppet',
  require => File['/usr/share/puppet/rack']
}
file { '/usr/share/puppet/rack/puppetmasterd/public':
  ensure  => 'directory',
  group   => 'puppet',
  owner   => 'puppet',
  require => File['/usr/share/puppet/rack/puppetmasterd']
}
file { '/usr/share/puppet/rack/puppetmasterd/tmp':
  ensure  => 'directory',
  group   => 'puppet',
  owner   => 'puppet',
  require => File['/usr/share/puppet/rack/puppetmasterd']
}
file { '/usr/share/puppet/rack/puppetmasterd/config.ru':
  ensure  => 'present',
  source  => '/usr/share/puppet/ext/rack/config.ru',
  group   => 'puppet',
  owner   => 'puppet',
  require => File['/usr/share/puppet/rack/puppetmasterd']
}

# Create Puma config for Puppet Master
file { '/usr/share/puppet/rack/puppetmasterd/puma.rb':
  ensure  => 'present',
  group   => 'puppet',
  owner   => 'puppet',
  require => File['/usr/share/puppet/rack/puppetmasterd'],
  content => "#!/usr/bin/env puma

# The directory to operate out of.
directory '/usr/share/puppet/rack/puppetmasterd'

# Set the environment in which the rack's app will run. The value must be a string.
environment 'production'

# Store the pid of the server in the file at “path”.
pidfile '/var/run/puppet/puppetmaster_puma.pid'

# Use “path” as the file to store the server info state.
state_path '/var/run/puppet/puppetmaster_puma.state'

# Redirect STDOUT and STDERR to files specified.
# I was having trouble getting this to work correctly:
# stdout_redirect '/var/log/puppet/puppetmaster_puma.log', '/var/log/puppetmaster_puma_err.log', true

# Bind the server to “url”. “tcp://”, “unix://” and “ssl://” are the only
bind 'unix:///var/run/puppet/puppetmaster_puma.sock'

# How many worker processes to run.
workers 2
preload_app!
"
  }

# Create a service for Puma Puppet Master
file { '/etc/init/puppetmaster_puma.conf':
  ensure  => 'present',
  group   => 'root',
  owner   => 'root',
  require => File['/usr/share/puppet/rack/puppetmasterd/puma.rb'],
  content => '# /etc/init/puppetmaster_puma.conf - Puppetmaster Puma config

description "Puppet Master Puma Service"

start on (local-filesystems and net-device-up IFACE=lo and runlevel [2345])
stop on (runlevel [!2345])

respawn
respawn limit 3 30

exec puma -C /usr/share/puppet/rack/puppetmasterd/puma.rb
'
  }

# Ensure Puma Puppet Master is running
service { 'puppetmaster_puma':
  ensure    => 'running',
  provider  => 'upstart',
  require   => File['/etc/init/puppetmaster_puma.conf']
}

# Set up Nginx for Puppet Master Puma
class { 'nginx':
  manage_repo => true # Latest and greatest, please!
}
nginx::resource::upstream { 'puppetmaster_rack_app':
  ensure                => 'present',
  members               => ['unix:/var/run/puppet/puppetmaster_puma.sock'],
  upstream_fail_timeout => 0
}
nginx::resource::vhost { 'puppet':
  ensure               => present,
  server_name          => ["${::fqdn}"],
  listen_port          => 8140,
  ssl                  => true,
  ssl_cert             => "/var/lib/puppet/ssl/certs/${hostname}.pem",
  ssl_key              => "/var/lib/puppet/ssl/private_keys/${hostname}.pem",
  ssl_port             => 8140,
  ssl_ciphers          => 'ALL:!ADH:RC4+RSA:+HIGH:+MEDIUM:-LOW:-SSLv2:-EXP',
  ssl_session_timeout  => '5m',
  vhost_cfg_append     => {
    'ssl_crl'                => '/var/lib/puppet/ssl/ca/ca_crl.pem',
    'ssl_client_certificate' => '/var/lib/puppet/ssl/certs/ca.pem',
    'ssl_verify_client'      => 'optional',
    'ssl_verify_depth'       => 1
  },
  use_default_location => true,
  access_log           => '/var/log/nginx/puppet_access.log',
  error_log            => '/var/log/nginx/puppet_error.log',
  proxy                => 'http://puppetmaster_rack_app',
  proxy_set_header     => [
    'Host $host',
    'X-Real-IP $remote_addr',
    'X-Forwarded-For $proxy_add_x_forwarded_for',
    'X-Client-Verify $ssl_client_verify',
    'X-Client-DN $ssl_client_s_dn',
    'X-SSL-Issuer $ssl_client_i_dn'
  ]
}
