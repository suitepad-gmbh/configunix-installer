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
rvm_gemset { 'ruby-2.1.5@configunix-api':
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
rvm_gem { 'ruby-2.1.5@configunix-api/puma':
  ensure  => '2.11.2',
  require => Rvm_system_ruby['ruby-2.1.5']
}
rvm_gem { 'ruby-2.1.5@configunix-api/bundler':
  ensure  => '1.9.6',
  require => Rvm_system_ruby['ruby-2.1.5']
}
rvm_gem { 'ruby-2.1.5@global/puppet':
  ensure  => '3.7.5',
  require => Rvm_system_ruby['ruby-2.1.5']
}

# Puppet Agent
class { 'puppet::agent':
  enable => false,
  ensure => 'stopped',
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
file { '/etc/init/puppetmaster.conf':
  ensure  => 'present',
  group   => 'root',
  owner   => 'root',
  content => '# /etc/init/puppetmaster.conf - Puppetmaster Puma config

description "Puppet Master Puma Service"

start on (local-filesystems and net-device-up IFACE=lo and runlevel [2345])
stop on (runlevel [!2345])

respawn
respawn limit 3 30

script
# this script runs in /bin/sh by default
# respawn as bash so we can source in rbenv/rvm
# quoted heredoc to tell /bin/sh not to interpret
# variables
exec /bin/bash <<EOT
  # set HOME to the setuid users home, there doesnt seem to be a better, portable way
  export HOME="$(eval echo ~$(id -un))"

  if [ -d "$HOME/.rbenv/bin" ]; then
    export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
  elif [ -f  /etc/profile.d/rvm.sh ]; then
    source /etc/profile.d/rvm.sh
  elif [ -f /usr/local/rvm/scripts/rvm ]; then
    source /etc/profile.d/rvm.sh
  elif [ -f "$HOME/.rvm/scripts/rvm" ]; then
    source "$HOME/.rvm/scripts/rvm"
  elif [ -f /usr/local/share/chruby/chruby.sh ]; then
    source /usr/local/share/chruby/chruby.sh
    if [ -f /usr/local/share/chruby/auto.sh ]; then
      source /usr/local/share/chruby/auto.sh
    fi
    # if you arent using auto, set your version here
    # chruby 2.0.0
  fi

  logger -t puma "Starting Puppet Master server"

  exec puma -C /usr/share/puppet/rack/puppetmasterd/puma.rb
EOT
end script

pre-stop script
exec /bin/bash <<EOT
  # set HOME to the setuid users home, there doesnt seem to be a better, portable way
  export HOME="$(eval echo ~$(id -un))"

  if [ -d "$HOME/.rbenv/bin" ]; then
    export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
  elif [ -f  /etc/profile.d/rvm.sh ]; then
    source /etc/profile.d/rvm.sh
  elif [ -f /usr/local/rvm/scripts/rvm ]; then
    source /etc/profile.d/rvm.sh
  elif [ -f "$HOME/.rvm/scripts/rvm" ]; then
    source "$HOME/.rvm/scripts/rvm"
  elif [ -f /usr/local/share/chruby/chruby.sh ]; then
    source /usr/local/share/chruby/chruby.sh
    if [ -f /usr/local/share/chruby/auto.sh ]; then
      source /usr/local/share/chruby/auto.sh
    fi
    # if you arent using auto, set your version here
    # chruby 2.0.0
  fi

  logger -t puma "Stopping Puppet Master server"

  exec pumactl --pidfile /var/run/puppet/puppetmaster_puma.pid stop
EOT
end script'
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

# Checkout configunix API
vcsrepo { "/usr/share/puppet/rack/configunix-api":
  ensure    => latest,
  provider  => git,
  source    => 'https://github.com/suitepad-gmbh/configunix-api.git',
  revision  => 'master',
  user      => 'puppet',
  group     => 'puppet'
}

# Install required gems
exec { 'configunix-api-bundle-install':
  command  => 'bundle install --deployment',
  cwd      => '/usr/share/puppet/rack/configunix-api',
  #unless  => 'bundle check',
  user     => 'puppet',
  group    => 'puppet',
  provider => 'shell',
  timeout  => 600,
  subscribe => [
    Vcsrepo["/usr/share/puppet/rack/configunix-api"]
  ],
  require   => [
    Rvm_gemset['ruby-2.1.5@configunix-api'],
    Package['libpq-dev'],
    Rvm_gem['ruby-2.1.5@configunix-api/bundler']
  ]
}

# Create database.yml
file { '/usr/share/puppet/rack/configunix-api/config/database.yml':
  ensure  => 'present',
  group   => 'puppet',
  owner   => 'puppet',
  require => Rvm_gemset['ruby-2.1.5@configunix-api'],
  content => "
production:
  adapter: postgresql
  host: localhost
  pool: 5
  timeout: 5000
  database: configunix
  user: configunix
  password: configunix
"
}

# Create postgres database
class { 'postgresql::server': }
class { 'postgresql::server::contrib': }
postgresql::server::db { 'configunix':
  user     => 'configunix',
  password => postgresql_password('configunix', 'configunix')
}
package { 'libpq-dev':
  ensure => installed
}

# Run migrations
exec { 'configunix-api-db-migrate':
  environment  => 'RAILS_ENV=production',
  command      => 'rake db:migrate',
  cwd          => '/usr/share/puppet/rack/configunix-api',
  #refreshonly => true,
  subscribe    => Vcsrepo["/usr/share/puppet/rack/configunix-api"],
  user         => 'puppet',
  group        => 'puppet',
  provider     => 'shell',
  require      => [
    Exec['configunix-api-bundle-install'],
    File['/usr/share/puppet/rack/configunix-api/config/database.yml'],
    Postgresql::Server::Db['configunix']
  ]
}

# Configure puma for configunix-api
file { '/usr/share/puppet/rack/configunix-api/tmp':
  ensure  => 'directory',
  group   => 'puppet',
  owner   => 'puppet',
  require => Vcsrepo["/usr/share/puppet/rack/configunix-api"]
}

file { '/usr/share/puppet/rack/configunix-api/puma.rb':
  ensure  => 'present',
  group   => 'puppet',
  owner   => 'puppet',
  require => File['/usr/share/puppet/rack/configunix-api/tmp'],
  content => "#!/usr/bin/env puma

# The directory to operate out of.
directory '/usr/share/puppet/rack/configunix-api'

# Set the environment in which the rack's app will run. The value must be a string.
environment 'production'

# Daemonize the server into the background.
daemonize

# Store the pid of the server in the file at “path”.
pidfile '/usr/share/puppet/rack/configunix-api/tmp/puma.pid'

# Use “path” as the file to store the server info state.
state_path '/usr/share/puppet/rack/configunix-api/tmp/puma.state'

# Redirect STDOUT and STDERR to files specified.
# I was having trouble getting this to work correctly:
stdout_redirect '/usr/share/puppet/rack/configunix-api/log/puma.log', '/usr/share/puppet/rack/configunix-api/log/puma_err.log', true

# Bind the server to “url”. “tcp://”, “unix://” and “ssl://” are the only
bind 'unix:///var/run/puppet/configunix_puma.sock'

# How many worker processes to run.
workers 2
preload_app!
"
}
file { '/etc/init/configunix.conf':
  ensure  => 'present',
  group   => 'root',
  owner   => 'root',
  content => '# /etc/init/configunix.conf - Configunix Puma config

description "Configunix Puma Service"

start on (local-filesystems and net-device-up IFACE=lo and runlevel [2345])
stop on (runlevel [!2345])

respawn
respawn limit 3 30

script
# this script runs in /bin/sh by default
# respawn as bash so we can source in rbenv/rvm
# quoted heredoc to tell /bin/sh not to interpret
# variables
exec /bin/bash <<EOT
  # set HOME to the setuid users home, there doesnt seem to be a better, portable way
  export HOME="$(eval echo ~$(id -un))"

  if [ -d "$HOME/.rbenv/bin" ]; then
    export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
  elif [ -f  /etc/profile.d/rvm.sh ]; then
    source /etc/profile.d/rvm.sh
  elif [ -f /usr/local/rvm/scripts/rvm ]; then
    source /etc/profile.d/rvm.sh
  elif [ -f "$HOME/.rvm/scripts/rvm" ]; then
    source "$HOME/.rvm/scripts/rvm"
  elif [ -f /usr/local/share/chruby/chruby.sh ]; then
    source /usr/local/share/chruby/chruby.sh
    if [ -f /usr/local/share/chruby/auto.sh ]; then
      source /usr/local/share/chruby/auto.sh
    fi
    # if you arent using auto, set your version here
    # chruby 2.0.0
  fi

  logger -t puma "Starting Configunix server"

  cd /usr/share/puppet/rack/configunix-api
  rvm ruby-2.1.5@configunix-api do bundle exec puma -C /usr/share/puppet/rack/configunix-api/puma.rb
EOT
end script

pre-stop script
exec /bin/bash <<EOT
  # set HOME to the setuid users home, there doesnt seem to be a better, portable way
  export HOME="$(eval echo ~$(id -un))"

  if [ -d "$HOME/.rbenv/bin" ]; then
    export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
  elif [ -f  /etc/profile.d/rvm.sh ]; then
    source /etc/profile.d/rvm.sh
  elif [ -f /usr/local/rvm/scripts/rvm ]; then
    source /etc/profile.d/rvm.sh
  elif [ -f "$HOME/.rvm/scripts/rvm" ]; then
    source "$HOME/.rvm/scripts/rvm"
  elif [ -f /usr/local/share/chruby/chruby.sh ]; then
    source /usr/local/share/chruby/chruby.sh
    if [ -f /usr/local/share/chruby/auto.sh ]; then
      source /usr/local/share/chruby/auto.sh
    fi
    # if you arent using auto, set your version here
    # chruby 2.0.0
  fi

  logger -t puma "Stopping Configunix server"

  cd /usr/share/puppet/rack/configunix-api
  rvm ruby-2.1.5@configunix-api do bundle exec pumactl --pidfile /usr/share/puppet/rack/configunix-api/tmp/puma.pid stop
EOT
end script'
}

# setup nginx for configunix
nginx::resource::upstream { 'configunix_rack_app':
  ensure                => 'present',
  members               => ['unix:/var/run/puppet/configunix_puma.sock'],
  upstream_fail_timeout => 0
}
nginx::resource::vhost { 'configunix':
  ensure               => present,
  server_name          => ["${::fqdn}"],
  listen_port          => 80,
  use_default_location => true,
  access_log           => '/var/log/nginx/configunix_access.log',
  error_log            => '/var/log/nginx/configunix_error.log',
  www_root             => '/var/www' # TBD
}
nginx::resource::location { 'configunix-api':
  ensure           => present,
  vhost            => 'configunix',
  location         => '/api/',
  proxy            => 'http://configunix_rack_app/',
  proxy_set_header => [
    'Host $host',
    'X-Real-IP $remote_addr',
    'X-Forwarded-For $proxy_add_x_forwarded_for',
    'X-Client-Verify $ssl_client_verify',
    'X-Client-DN $ssl_client_s_dn',
    'X-SSL-Issuer $ssl_client_i_dn'
  ]
}
