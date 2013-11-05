namespace :shared do
  task :make_shared_dirs do
    run "if [ ! -d #{shared_path}/media ]; then mkdir #{shared_path}/media; fi"
    run "if [ ! -d #{shared_path}/config ]; then mkdir #{shared_path}/config; fi"
  end
  task :make_symlinks do
    run "if [ ! -h #{current_path}/content/media ]; then ln -s ../../../shared/media #{current_path}/content/media; fi"
    run "if [ ! -h #{current_path}/env_#{stage}.php ]; then ln -s ../../shared/config/env_#{stage}.php #{current_path}/env_#{stage}.php; fi"
  end
end

namespace :nginx do
  desc "Restarts nginx"
  task :restart do
    run "sudo /etc/init.d/nginx reload"
  end
end

namespace :phpfpm do
  desc" Restarts PHP-FPM"
  task :restart do
    run "sudo /etc/init.d/php-fpm restart"
  end
end

namespace :git do
  desc "Updates git submodule tags"
  task :submodule_tags do
    run "if [ -d #{shared_path}/cached-copy/ ]; then cd #{shared_path}/cached-copy/ && git submodule foreach --recursive git fetch origin --tags; fi"
  end
end

namespace :memcached do
  desc "Restarts Memcached"
  task :restart do
    run "echo 'flush_all' | nc localhost 11211", :roles => [:memcached]
  end
  desc "Updates the pool of memcached servers"
  task :update do
    unless find_servers( :roles => :memcached ).empty? then
      mc_servers = '<?php return array( "' + find_servers( :roles => :memcached ).join( ':11211", "' ) + ':11211" ); ?>'
      run "echo '#{mc_servers}' > #{current_path}/memcached.php", :roles => :memcached
    end
  end
end

namespace :db do
  desc "Syncs the staging database (and uploads) from production"

  task :sync_from_production, :roles => :web  do
    puts "Hang on... this might take a while."
    sync(wpdb[ :production ], wpdb[ :development ])
    puts "Database synced to staging"

    # Now to copy files
    find_servers( :roles => :web ).each do |server|
      system "scp -rp #{server}:#{production_deploy_to}/shared/media ../content/"
    end
  end

  task :sync_from_staging, :roles => :web  do
    puts "Hang on... this might take a while."
    sync(wpdb[ :staging ], wpdb[ :development ])
    puts "Database synced to staging"

    # Now to copy files
    find_servers( :roles => :web ).each do |server|
      system "scp -rp #{server}:#{staging_deploy_to}/shared/media ../content/"
    end
  end

  def sync(source, destination)
    timestamp = Time.now.to_i
    source_bk_file = "/tmp/wpstack-#{source[:host]}-#{timestamp}.sql"
    dest_bk_file = "/tmp/wpstack-#{destination[:host]}-#{timestamp}.sql"

    system "mysqldump -u #{source[:user]} --result-file=#{source_bk_file} -h #{source[:host]} -p#{source[:password]} #{source[:name]}"

    system "mysqldump -u #{destination[:user]} --result-file=#{dest_bk_file} -h #{destination[:host]} -p#{destination[:password]} #{destination[:name]}"

    system "mysql -u #{destination[:user]} -h #{destination[:host]} -p#{destination[:password]} #{destination[:name]} < #{source_bk_file}"
  end



  desc "Sets the database credentials (and other settings) in wp-config.php"
  task :make_config do
    set :staging_domain, '' if staging_domain.nil?
    {:'%%WP_STAGING_DOMAIN%%' => staging_domain, :'%%WP_STAGE%%' => stage, :'%%DB_NAME%%' => wpdb[stage][:name], :'%%DB_USER%%' => wpdb[stage][:user], :'%%DB_PASSWORD%%' => wpdb[stage][:password], :'%%DB_HOST%%' => wpdb[stage][:host]}.each do |k,v|
      run "sed -i 's/#{k}/#{v}/' #{release_path}/wp-config.php", :roles => :web
    end
  end
end

namespace :deploy do
  task :setup_config, roles: :app do
    put "#{repository_path}/env_local.php.sample", "#{shared_path}/config/env_#{stage}.php"
    put "RewriteEngine On\nRewriteRule (.*) current/$1\n", "#{deploy_to}/.htaccess"

    puts "Now edit the config files in #{shared_path}."
  end

end

require "pathname"

namespace :deploy do
  task :create_symlink, :except => { :no_release => true } do
    deploy_to_pathname = Pathname.new(deploy_to)

    on_rollback do
      if previous_release
        previous_release_pathname = Pathname.new(previous_release)
        relative_previous_release = previous_release_pathname.relative_path_from(deploy_to_pathname)
        run "rm -f #{current_path}; ln -s #{relative_previous_release} #{current_path}; true"
      else
        logger.important "no previous release to rollback to, rollback of symlink skipped"
      end
    end

    latest_release_pathname = Pathname.new(latest_release)
    relative_latest_release = latest_release_pathname.relative_path_from(deploy_to_pathname)
    run "rm -f #{current_path} && ln -s #{relative_latest_release} #{current_path}"
    run ""
  end
end
