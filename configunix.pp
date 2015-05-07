# Basic NTP
include '::ntp'

# RVM
include rvm
rvm::system_user { 'puppet': }
rvm_system_ruby { 'ruby-2.1.5':
  ensure      => 'present',
  default_use => true
}
rvm_gemset { 'ruby-2.1.5@configunix':
  ensure  => present,
  require => Rvm_system_ruby['ruby-2.1.5']
}
rvm_gem { 'ruby-2.1.5@global/bundler':
  ensure  => '1.9.6',
  require => Rvm_system_ruby['ruby-2.1.5']
}
rvm_gem { 'ruby-2.1.5@global/puma':
  ensure  => '2.11.2',
  require => Rvm_system_ruby['ruby-2.1.5']
}
rvm_gem { 'ruby-2.1.5@global/puppet':
  ensure  => '3.7.5',
  require => Rvm_system_ruby['ruby-2.1.5']
}

# Puppet Agent
class { 'puppet::agent':
  enable => false,
  master => 'localhost'
}

# Puppet Master
class { 'puppet::master':
  enable        => false,
  ensure        => 'stopped',
  autosign      => true,
  environments  => ['production'],
  require       => File['/etc/puppet/hieradata']
}
file { '/etc/puppet/hieradata':
  ensure  => 'directory',
  group   => 'puppet',
  owner   => 'puppet'
}
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
file { '/usr/share/puppet/rack/puppetmasterd/puma.rb':
  ensure  => 'present',
  # source  => 'puppet:///files/puma-config.rb',
  group   => 'puppet',
  owner   => 'puppet',
  require => File['/usr/share/puppet/rack/puppetmasterd'],
  content => "#!/usr/bin/env puma

# The directory to operate out of.
directory '/usr/share/puppet/rack/puppetmasterd'

# Set the environment in which the rack's app will run. The value must be a string.
environment 'production'

# Daemonize the server into the background.
daemonize

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

# Nginx
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
  ssl_cert             => "/var/lib/puppet/ssl/certs/${fqdn}.pem",
  ssl_key              => "/var/lib/puppet/ssl/private_keys/${fqdn}.pem",
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
