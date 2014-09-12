#!/usr/bin/env ruby
class GITHUB_RELEASE
  require 'octokit'
  require 'pathname'
  require 'mime-types'
  
  Error = Class.new(StandardError)
  OPTION_PATTERN = /\A--([a-z][a-z_\-]*)(?:=(.+))?\z/

  def self.die(message)
    $stderr.puts("Error: " + message)
    exit 1
  end
  
  def self.cli(*args)
    options = {}
    args.flatten.each do |arg|
      next options.update(arg) if arg.is_a? Hash
      die("invalid option %p" % arg) unless match = OPTION_PATTERN.match(arg)
      key = match[1].tr('-', '_').to_sym
      if options.include? key
        options[key] = Array(options[key]) << match[2]
      else
        options[key] = match[2] || true
      end
    end
    token        = options[:token]   || ENV['GITHUB_TOKEN'] ||
                   raise(ArgumentError, "github token must be provide through --token or enviroment ${GITHUB_TOKEN}")
    args_version = options[:version] || raise(ArgumentError, "--version must be provided")
    commit       = options[:commit]  || ENV['TRAVIS_COMMIT']
    tag          = options[:tag]     || ENV['TRAVIS_TAG']
    repo         = options[:repo]    || ENV['TRAVIS_REPO_SLUG']
    github_release = new(token, repo, {:dry_run => options[:dry_run]})
    if tag and (tag != "")
      ## build for a tag
      if github_release.releases_versions.any?{|x| x==tag}
        puts  "The current build is for a release. Try to upload asstes"
        release_url = ( github_release.list_releases.select{|r| r.tag_name == tag} )[0].url
        github_release.upload_asset(release_url, Array(options[:file])) 
      else
        if /^v(\d+)(\.\d+)*/ =~ tag
          puts "The current build is for a tag, which looks like a release version number. Create release."
          github_release.create_release(repo, tag) unless options[:dry_run]
        ## TODO: If create release wouldn't trigger another build,
        ## we should upload asset here.
        else
          puts "The tag name doesn't seem to be a release name. Skip release."
        end
      end
    else
      ## build for a commit
      ## look for [try deploy github] in single line in comment
      message = github_release.commit(repo, commit)[:commit][:message]
      if /^\s*\[try\s+deploy\s+github\]\s*$/.match(message)
        puts "Find '[try deploy github]' in commit message. Create release."
        if options[:bump_version]
          version = github_release.bump_version(args_version)
        else
          version = args_version
        end
        puts "Create release with version number #{version}"
        github_release.create_release(repo, version) unless @dry_run
      end
    end
    return github_release
  rescue StandardError => error
    options[:debug] ? raise(error) : die(error.message)
  end

  def initialize(token, repo, options = {})
    @token = token
    @repo = repo
    @dry_run = options[:dry_run]
    
    @client = Octokit::Client.new(:access_token => @token)
    check_auth
    @client.auto_paginate = true
  end

  def check_auth
    unless @client.scopes.include? 'public_repo' or @client.scopes.include? 'repo'
      raise Error, "Dpl does not have permission to upload assets. Make sure your token contains the repo or public_repo scope."
    end

  end
  
  def list_releases(refresh = false)
    if @releases.nil? 
      return @releae = @client.releases(@repo)
    end
  end

  def releases_versions(refresh = false)
    list_releases(refresh).collect{|x| x[:tag_name]}
  end

  def create_release(*args, &block)
    @client.create_release(*args, &block)
  end

  def commit(*args, &block)
    @client.commit(*args, &block)
  end
  
  def bump_version(version)
    unless matched = /^([^*]*)\*([^*]*)$/.match(version)
      raise ArgumentError, "the argument 'version' must include one '*'"
    else
      prefix = matched[1]
      suffix = matched[2]
      matched_version = releases_versions.collect do |x|
        unless x[0, prefix.length] == prefix and
              x[-suffix.length, suffix.length] == suffix; next; end
        if /\d+/ =~ (mid = x[prefix.length, x.length - prefix.length - suffix.length])
          mid.to_i
        else
          next
        end
      end.compact
      version = prefix + ((matched_version.max || -1) + 1).to_s + suffix
      puts "The bumped version is #{version}"
      return version
    end
  end

  def upload_asset(release_url, file_array)
    file_array.uniq!
    assets = @client.release(release_url).assets
    exists_files = assets.collect{|x| x.name}
    file_array.each do |file|
      filename = Pathname.new(file).basename.to_s
      if exists_files.include? filename
        puts "#{filename} already exists, skipping."
      else
        content_type = MIME::Types.type_for(file).first.to_s
        if content_type.empty?
          # Specify the default content type, as it is required by GitHub
          content_type = "application/octet-stream"
        end
        puts "upload asset #{file}"
        unless @dry_run
          @client.upload_asset(release_url, file, {:name => filename, :content_type => content_type})
        end
      end
    end
  end

end


if __FILE__ == $0 then
  GITHUB_RELEASE.cli(ARGV)
  exit 0
end

