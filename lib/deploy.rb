#
set :user, "deploy"
set :use_sudo, false
set :deploy_via, :remote_cache
set :copy_exclude, %w(.git .gitmodules .DS_Store .gitignore *.md *.sample cap composer.json composer.lock)
set :keep_releases, 5

#after "deploy:setup", "deploy:setup_config"
after "deploy:setup", "shared:make_shared_dirs"

after "deploy:restart", "deploy:cleanup"
after "deploy:update_code", "shared:make_symlinks"
after "deploy:update_code", "db:make_config"
#after "deploy", "memcached:update"

# Pull in the config file
loadFile 'config/config.rb'
