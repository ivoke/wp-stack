set :user, "deploy"
set :use_sudo, false
set :deploy_via, :remote_cache
set :copy_exclude, %w(.git .gitmodules .DS_Store .gitignore *.md *.sample cap composer.* tools)
set :keep_releases, 5

before "deploy", "deploy:build"

after "deploy:setup", "shared:make_shared_dirs"
after "deploy:setup", "deploy:setup_config"

after "deploy:restart", "deploy:cleanup"
after "deploy:create_symlink", "shared:make_symlinks"
after "deploy", "deploy:build_cleanup"

# Pull in the config file
loadFile 'config/config.rb'
