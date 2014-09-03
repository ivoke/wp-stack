namespace :shared do
  task :make_shared_dirs do
    run "if [ ! -d #{shared_path}/media ]; then mkdir #{shared_path}/media; fi"
    run "if [ ! -d #{shared_path}/plugins ]; then mkdir #{shared_path}/plugins; fi"
    run "if [ ! -d #{shared_path}/config ]; then mkdir #{shared_path}/config; fi"
  end
  task :make_symlinks do
    run "if [ ! -h #{current_path}/content/media ]; then ln -s ../../../shared/media #{current_path}/content/media; fi"
    run "if [ ! -h #{current_path}/content/plugins ]; then ln -s ../../../shared/plugins #{current_path}/content/plugins; fi"
    run "rm #{current_path}/wp-config.php && cp #{shared_path}/config/wp-config.php #{current_path}/wp-config.php"
    run "rm #{current_path}/robots.txt && cp #{shared_path}/config/robots.txt #{current_path}/robots.txt"
    run "rm #{current_path}/.htaccess && cp #{shared_path}/config/htaccess #{current_path}/.htaccess"
  end
end

namespace :git do
  desc "Updates git submodule tags"
  task :submodule_tags do
    run "if [ -d #{shared_path}/cached-copy/ ]; then cd #{shared_path}/cached-copy/ && git submodule foreach --recursive git fetch origin --tags; fi"
  end
end

namespace :db do
  desc "Syncs the staging database (and uploads)"
  task :sync, :roles => :web  do
    puts "Hang on... this might take a while."
    puts "Syncing database from #{stage} to local"
    sync_database(wp[ stage.to_sym ], wp[:local])

    # Now to copy files
    find_servers( :roles => :web ).each do |server|
      puts "Syncing files"
      system "rsync -avz --delete -e ssh #{server}:#{deploy_to}/shared/media/ ../content/media/"
    end
  end

  def sync_database from, to
    random = rand( 10 ** 5 ).to_s.rjust( 5, '0' )

    default_run_options[:shell] = '/bin/bash'

    # dump database
    system "mysqldump -u #{from[:db][:user]} --result-file=/tmp/wpstack-#{random}.sql -h #{from[:db][:host]} -p#{from[:db][:password]} #{from[:db][:name]}"

    # load database dump
    system "mysql -u #{to[:db][:user]} -h #{to[:db][:host]} -p#{to[:db][:password]} #{to[:db][:name]} < /tmp/wpstack-#{random}.sql && rm /tmp/wpstack-#{random}.sql"

    # change table prefixes if they don't match
    if to[:wp][:table_prefix] != from[:wp][:table_prefix]
      tables = run_locally <<-eos
        mysql -u #{to[:db][:user]} -h #{to[:db][:host]} -p#{to[:db][:password]} #{to[:db][:name]} <<< "SELECT GROUP_CONCAT(TABLE_NAME) FROM  information_schema.Tables WHERE TABLE_SCHEMA = '#{to[:db][:name]}';"
      eos

      tables = tables.split("\n")[1].split(',')

      cmd = "RENAME TABLE "
      tables.each do |table|
        base_name = table.sub(from[:wp][:table_prefix], '')
        cmd += "#{table} TO #{to[:wp][:table_prefix]}#{base_name},"
      end

      cmd = "#{cmd[0,cmd.length-1]};"

      run_locally <<-eos
        mysql -u #{to[:db][:user]} -h #{to[:db][:host]} -p#{to[:db][:password]} #{to[:db][:name]} <<< "#{cmd}"
      eos
    end

    # update multisite config
    #run_locally <<-eos
    run_locally "mysql -u #{to[:db][:user]} -h #{to[:db][:host]} -p#{to[:db][:password]} #{to[:db][:name]} <<< \"UPDATE #{to[:wp][:table_prefix]}blogs SET domain='#{to[:wp][:host]}';\""
    run_locally "mysql -u #{to[:db][:user]} -h #{to[:db][:host]} -p#{to[:db][:password]} #{to[:db][:name]} <<< \"UPDATE #{to[:wp][:table_prefix]}site SET domain='#{to[:wp][:host]}';\""
    #eos

  end

end

namespace :deploy do
  task :setup_config, :roles => :web do
    run "mkdir -p #{shared_path}/config"
    run "mkdir -p #{shared_path}/media"
    run "mkdir -p #{shared_path}/plugins"

    put "RewriteEngine On\nRewriteRule (.*) current/$1\n", "#{deploy_to}/.htaccess"
    put "", "#{shared_path}/config/htaccess"
    put "", "#{shared_path}/config/robots.txt"
    put "", "#{shared_path}/config/wp-config.php"

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

require 'fileutils'

namespace :deploy do
  task :build do

    versioned_files = [
      'assets/css/main.min.css',
      'assets/js/scripts.min.js',
      'lib/scripts.php'
    ]

    @last_commit = run_locally("git rev-parse HEAD")
    FileUtils.cd "../content/themes/#{theme}" do
      system("grunt build")
      versioned_files.each do |file|
        system("git add #{file}")
      end
      system("git commit -m 'built files for production'")
    end
  end

  task :build_cleanup do
    system("git reset --merge #{@last_commit}")
    system("git checkout ../content/themes/#{theme}/assets/css/main.css")
  end
end

namespace :plugins do
  task :sync do
    find_servers( :roles => :web ).each do |server|
      puts "Syncing plugins"
      system "rsync -avz --delete -e ssh #{server}:#{deploy_to}/shared/plugins/ ../content/plugins/"
    end
  end
  task :push do
    find_servers( :roles => :web ).each do |server|
      puts "Pushing plugins"
      system "rsync -avz --delete -e ssh ../content/plugins/ #{server}:#{deploy_to}/shared/plugins/"
    end
  end
end