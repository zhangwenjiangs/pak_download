#!/usr/bin/env ruby

require 'net/http'
require "digest/md5"
require 'uri'
require "yaml"
require 'pathname'
require 'fileutils'
require 'Find'
require 'net/ftp'

$pak_name = Array.[]("NECJCpt-mgwin-x64.zip", "NECJCpt-mgwin-x86.zip" ,"NECJCpt-14.1.1-1.i386.rpm.bz2","NECJCpt-clwin-x86.zip")
$pak_count = 4

module ConfigFile
  def mkpath(*args)
    File.join(File.dirname(__FILE__), *args.map{|v| v.to_s})
  end

  def load(*args)
    YAML.load_file(mkpath(*args)+".yml")
  end
  module_function :mkpath, :load
end

module FileDigest
  def calc_local(path)
    Digest::MD5.file(path).hexdigest()
  end

  def calc_remote(digest)
    resp = Net::HTTP.get_response(URI("http://#{digest}/*fingerprint*/"))
    resp.body.to_s[/MD5:.*</][5,32]
  end

  def equal?(digest, path)
    calc_local(path) == calc_remote(digest)
  end
  module_function :equal?, :calc_local, :calc_remote
end

class PkgMgr
  def initialize()
    @param = ConfigFile.load(File.basename(__FILE__, ".*"))
    @repository = @param && @param[:repository] || {}
    @basedir = @param && @param[:platform][:basedir] || {}
    @version_num_input = @param[:revision].to_s
    @base_path = "//172.28.93.70/test/R#{@version_num_input}"
    @old_lastfile_name = nil
    @new_lastfile_name = nil
    @real_dir = Pathname.new(File.dirname(__FILE__)).realpath
  end

  def find_path(file_path)
    Find.find(file_path) do |filename|
       if filename.include? "LastSuccessfully_"
	     if filename.include? "#{@new_lastfile_name}"
	        exit
	     else
	        if @old_lastfile_name  == nil 
	           @old_lastfile_name = filename.split('/').last
	        end
	     end
	   end
    end
  end
 
  def get_path()
	today = Time.new
	year = today.year.to_s
	if today.month < 10
	 month = "0" + today.month.to_s
	else
	 month = today.month.to_s
	end
	if today.day < 10
	 day = "0" + today.day.to_s
	else
	 day = today.day.to_s
	end

	@new_lastfile_name = "LastSuccessfully_"+ year + month + day
    @totle_path = "//172.28.93.70/test/R#{@version_num_input}/#{@new_lastfile_name}"

    if File.directory? "#{@real_dir}/LastSuccessfully"
    else
       Dir.mkdir("#{@real_dir}/LastSuccessfully")
    end

	if File.directory? @base_path
       find_path(@base_path)
	   Dir.mkdir(@totle_path)
	   return
	else
	   Dir.mkdir(@base_path) 
	   Dir.mkdir(@totle_path)
	   return
	end
  end

  def download(remote_path, local_path)
    per = 0
    ret = true
    url = URI.parse "http://#{remote_path}"
    out_path = local_path || File.basename(remote_path)
    puts "Downloading #{remote_path.split('/').last}"
    begin
      while per < 100
        file = open(out_path, 'wb')
        Net::HTTP.start(url.host, url.port) do |http|
          req = Net::HTTP::Get.new(url.path)
          http.request(req) do |response|
            unless response.code == '200'
              raise response.message
            end
            length = response['Content-Length'].to_i
            read = 0
            count = 1
            response.read_body do |segment|
              read += segment.bytesize
              file.write(segment)
              if ((read.to_f/length.to_f)*10).round(0) >= count
                 printf "."
                 count += 1
              end
            end
            per = ((read.to_f/length.to_f)*100).round(2) 
          end
        end
        if per == 100
           puts "\nDownload successfully! (#{per}%)"
        else
           puts "\n-> Download failed, try downloading again! (#{per}%)"
        end
      end
    rescue => exc
        puts "#{remote_path} => #{out_path} : #{exc}"
        ret = false
    ensure
        file.close
        FileUtils.rm_rf(out_path) unless ret
    end
    return ret
  end

  def update
    get_path()

    begin
      i = 0
      $pak_count.times do
        case i
          when 0,1 then
            # windows remote path
            remote_path_base = [@repository[:host], @basedir[:win]].map(&:to_s).join('/')
          when 2 then
            # linux remote path
            remote_path_base = [@repository[:host], @basedir[:linux]].map(&:to_s).join('/')
          else
            # clwin remote path
            remote_path_base = [@repository[:host], @basedir[:clwin]].map(&:to_s).join('/')
        end
        remote_path = "#{remote_path_base}/#{$pak_name[i]}"
        local_path = "#{@real_dir}/LastSuccessfully/#{$pak_name[i]}"
        old_local_path = "#{@base_path}/#{@old_lastfile_name}/#{$pak_name[i]}"
        if File.exist?(old_local_path)
          if FileDigest.equal?(remote_path, old_local_path)
             # MD5 equal?
             puts "Copying #{$pak_name[i]} ..."
             FileUtils.mv(old_local_path,@totle_path)
             puts "Copyed successfully!"
             i += 1
             next
          end
        end
        g = download(remote_path,local_path)

        ftp = Net::FTP.new('172.28.93.70')
        ftp.passive = true
        ftp.login
        ftp.putbinaryfile(local_path,"/test/R#{@version_num_input}/#{@new_lastfile_name}/#{$pak_name[i]}")
        ftp.close
        i += 1
      end

      rescue => exc
        puts exc
        return false
      end
      if @old_lastfile_name
         FileUtils.rm_r("#{@base_path}/#{@old_lastfile_name}")
         puts "old file path remove successfully."
      end
      return true
  end
end

exit PkgMgr.new.update == true ? 0 : 1