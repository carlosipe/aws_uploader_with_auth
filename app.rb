require 'aws-sdk'

File.read(".env").scan(/(.*?)="?(.*)"?$/).each do |key, value|
  ENV[key] ||= value
end

Aws.config.update({
  region: ENV.fetch('AWS_REGION'),
  credentials: Aws::Credentials.new(ENV.fetch('AWS_KEY_ID'), ENV.fetch('AWS_ACCESS_KEY'))
})

# obj = s3.bucket('bucket-name').object('key')
# obj.upload_file('/path/to/source/file')

require "cuba"
require "mote"
require "mote/render"
require "cuba/safe"
Cuba.plugin(Mote::Render)
Cuba.use(Rack::Session::Cookie, :secret => ENV.fetch("RACK_SECRET"))

class Uploader
  def bucket
    @bucket ||= Aws::S3::Resource.new.bucket('carlosipe2')
  end

  def single_upload(file)
    key = "#{Time.now.to_i}.#{file.fetch(:filename)}".gsub(/[^0-9A-Za-z.\-]/, '_')
    obj = bucket.object(key)
    obj.upload_file(file.fetch(:path))
  end

  def file_list
    s3 = Aws::S3::Client.new
    resp = s3.list_objects(bucket: 'carlosipe2') #, max_keys: 2)
    resp.contents.map{|f| {key: f.key, last_modified: f.last_modified}}
  end

  def upload(files)
    files.each do |file|      
      single_upload(file)
    end
  end

  def signed_request(key)
    s3 = Aws::S3::Client.new
    signer = Aws::S3::Presigner.new(client: s3)
    url = signer.presigned_url(:get_object, bucket: "carlosipe2", key: key)
  end
end

Cuba.define do
  on 'files' do
    on root do 
      render "index", files: Uploader.new.file_list
    end
  
    on ':key' do |key|
      res.redirect Uploader.new.signed_request(key)
    end
  end

  on root do
    on get do
      render 'form'
    end

    on post, param('filesToUpload') do |files|
      errors = []
      sanitized_files = []
      files.each do |file|
        tmpfile = file.fetch(:tempfile){}.path
        filename = file.fetch(:filename) {}
        if File.size(tmpfile) > 10000000
          errors << "We didn't upload the file #{filename} because it exceeded the allowed size"
        else
          sanitized_files << {filename: filename, path: tmpfile }
        end
      end
      # raise sanitized_files.inspect
      Uploader.new.upload(sanitized_files)
      render 'output', output: "Uploaded #{sanitized_files.count} files<br>" + errors.join('<br>')
    end

    on post do
      res.write 'No files'
    end
  end
end