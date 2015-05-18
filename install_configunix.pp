# Create a user for the API
user { "configunix":
  ensure  => 'present',
  shell   => '/bin/bash',
  home    => "/home/configunix"
}
file { "configunix home dir":
  ensure  => 'directory',
  path    => "/home/configunix",
  require => User["configunix"],
  owner   => "configunix",
  group   => "configunix",
  mode    => '0750'
}
file { "configunix key store":
  ensure  => 'directory',
  path    => "/home/configunix/.gnupg",
  require => User["configunix"],
  owner   => "configunix",
  group   => "configunix",
  mode    => '0750'
}

# Install RVM for Configunix
rvm::ruby { 'configunix':
  user    => 'configunix',
  version => "ruby-2.2.2",
  require => File['configunix key store']
}
rvm::gem { 'bundler':
  ruby   => Rvm::Ruby['configunix'],
  ensure => '1.9.6'
}

# We need Git and Postgres libs
package { 'git': }
package { 'libpq-dev': }

# Checkout configunix API
vcsrepo { "/home/configunix/api":
  ensure    => latest,
  provider  => git,
  source    => 'https://github.com/suitepad-gmbh/configunix-api.git',
  revision  => 'master',
  user      => 'configunix',
  group     => 'configunix',
  require   => Package['git']
}

# Remove Ruby version specifications for Configunix API
file { '/home/configunix/api/.ruby-version':
  ensure => 'absent',
  require => Vcsrepo["/home/configunix/api"]
}
file { '/home/configunix/api/.ruby-gemset':
  ensure => 'absent',
  require => Vcsrepo["/home/configunix/api"]
}

# Install Postgresql
class { 'postgresql::server': }
class { 'postgresql::server::contrib': }

# Create postgres database
postgresql::server::db { 'configunix':
  user     => 'configunix',
  password => postgresql_password('configunix', 'configunix')
}

# Install required gems
rvm::bash_exec { 'configunix-api-bundle-install':
  command  => 'bundle install --deployment --without development test',
  cwd      => '/home/configunix/api',
  user     => 'configunix',
  group    => 'configunix',
  provider => 'shell',
  timeout  => 600,
  require   => [
    Package['libpq-dev'],
    Rvm::Gem['bundler'],
    Vcsrepo["/home/configunix/api"],
    File['/home/configunix/api/.ruby-version'],
    File['/home/configunix/api/.ruby-gemset']
  ]
}

# Create database.yml
file { '/home/configunix/api/config/database.yml':
  ensure  => 'present',
  group   => 'configunix',
  owner   => 'configunix',
  require => Vcsrepo["/home/configunix/api"],
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

# Create application.yml
file { '/home/configunix/api/config/application.yml':
  ensure  => 'present',
  group   => 'configunix',
  owner   => 'configunix',
  require => Vcsrepo["/home/configunix/api"],
  replace => false,
  content => "
production:
  aws_access_key_id: ''
  aws_secret_access_key: ''
  region: ''
  puppet_repository_path: '/etc/puppet/environments/production'
"
}

# Run migrations
rvm::bash_exec { 'configunix-api-db-migrate':
  command      => 'RAILS_ENV=production bundle exec rake db:migrate',
  cwd          => '/home/configunix/api',
  user         => 'configunix',
  group        => 'configunix',
  require      => [
    Rvm::Bash_exec['configunix-api-bundle-install'],
    File['/home/configunix/api/config/database.yml'],
    Postgresql::Server::Db['configunix']
  ]
}

# Create tmp directory
file { '/home/configunix/api/tmp':
  ensure  => 'directory',
  group   => 'configunix',
  owner   => 'configunix',
  require => Vcsrepo["/home/configunix/api"]
}

# Create Puma config
file { '/home/configunix/api/config/puma.rb':
  ensure  => 'present',
  group   => 'configunix',
  owner   => 'configunix',
  content => "#!/usr/bin/env puma

# The directory to operate out of.
directory '/home/configunix/api'

# Set the environment in which the rack's app will run. The value must be a string.
environment 'production'

# Store the pid of the server in the file at “path”.
pidfile '/home/configunix/api/tmp/puma.pid'

# Use “path” as the file to store the server info state.
state_path '/home/configunix/api/tmp/puma.state'

# Redirect STDOUT and STDERR to files specified.
# I was having trouble getting this to work correctly:
stdout_redirect '/home/configunix/api/log/puma.log', '/home/configunix/api/log/puma_err.log', true

# Bind the server to “url”. “tcp://”, “unix://” and “ssl://” are the only
bind 'unix:///home/configunix/api/tmp/puma.sock'

# How many worker processes to run.
workers 2
preload_app!
"
}

# Create API Upstart config
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

setuid configunix
setgid configunix

exec /bin/bash -c "cd ~/api; ~/.rvm/bin/rvm 2.2.2 do bundle exec puma -C ./config/puma.rb"
'
}

# Ensure Configunix is running
service { 'configunix':
  ensure    => 'running',
  provider  => 'upstart',
  require   => File['/etc/init/configunix.conf']
}

# Make sure www-data user is in suitepad group
user { 'www-data':
  groups  => ['configunix'],
  require => User['configunix']
}

# Generate Nginx config
class { 'nginx':
  manage_repo => true # Latest and greatest, please!
}
nginx::resource::upstream { 'configunix_rack_app':
  ensure                => 'present',
  members               => ['unix:/home/configunix/api/tmp/puma.sock'],
  upstream_fail_timeout => 0
}
nginx::resource::vhost { 'configunix':
  ensure               => present,
  server_name          => ["${::fqdn}"],
  listen_port          => 80,
  use_default_location => true,
  access_log           => '/var/log/nginx/configunix_access.log',
  error_log            => '/var/log/nginx/configunix_error.log',
  www_root             => '/home/configunix/frontend/dist',
  try_files            => ['$uri', '$uri/', '/index.html?$request_uri']
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

# Install Node.js to be able to build frontend
include nodejs
package { 'nodejs-legacy': }
package { 'npm': }
package { 'ember-cli':
  ensure   => '0.2.3',
  provider => 'npm',
  require  => Package['npm']
}
package { 'bower':
  ensure   => '1.4.1',
  provider => 'npm',
  require  => Package['npm']
}

# Check out frontend repo
vcsrepo { "/home/configunix/frontend":
  ensure    => latest,
  provider  => git,
  source    => 'https://github.com/suitepad-gmbh/configunix-frontend.git',
  revision  => 'master',
  user      => 'configunix',
  group     => 'configunix',
  require   => [
    Package['git'],
    User['configunix']
  ]
}

# Generate config files
file { '/home/configunix/frontend/config/environment.js':
  ensure  => 'present',
  source  => '/home/configunix/frontend/config/environment.sample.js',
  owner   => 'configunix',
  group   => 'configunix',
  replace => false,
  require => Vcsrepo["/home/configunix/frontend"]
}

# Install NPM packages
exec { 'configunix-frontend-npm-install':
  path     => ['/usr/bin', '/usr/sbin', '/bin', '/usr/local/bin'],
  command  => 'npm install',
  cwd      => '/home/configunix/frontend',
  user     => 'configunix',
  group    => 'configunix',
  timeout  => 1200,
  require  => [
    Vcsrepo["/home/configunix/frontend"],
    Class['nodejs'],
    Package['npm']
  ]
}

# Install Bower packages
exec { 'configunix-frontend-bower-install':
  environment => 'HOME=/home/configunix',
  path        => ['/usr/bin', '/usr/sbin', '/bin', '/usr/local/bin'],
  command     => 'bower install',
  cwd         => '/home/configunix/frontend',
  user        => 'configunix',
  group       => 'configunix',
  timeout     => 600,
  require     => [
    Vcsrepo["/home/configunix/frontend"],
    Exec['configunix-frontend-npm-install'],
    Package['bower'],
    Class['nodejs']
  ]
}

# Run bundler
rvm::bash_exec { 'configunix-frontend-bundle-install':
  command  => 'bundle install --deployment',
  cwd      => '/home/configunix/frontend',
  user     => 'configunix',
  group    => 'configunix',
  timeout  => 600,
  require  => [
    Rvm::Gem['bundler'],
    Vcsrepo["/home/configunix/frontend"]
  ]
}

# Build the frontend
rvm::bash_exec { 'configunix-frontend-build':
  command     => 'bundle exec ember build -prod',
  cwd         => '/home/configunix/frontend',
  user        => 'configunix',
  group       => 'configunix',
  timeout     => 600,
  require     => [
    Vcsrepo["/home/configunix/frontend"],
    Exec['configunix-frontend-npm-install'],
    Package['bower'],
    Class['nodejs'],
    Package['nodejs-legacy'],
    Exec['configunix-frontend-bundle-install'],
    Exec['configunix-frontend-bower-install'],
    File['/home/configunix/frontend/config/environment.js']
  ]
}
