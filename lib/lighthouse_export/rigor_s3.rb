class RigorS3
  
  def initialize options={}
    @s3 = connect!(options[:access_key_id], options[:secret_access_key])
    @lighthouse_bucket = options[:bucket] || 'lighthouse-attachments'
  end
  
  def bucket
    @s3.buckets[@lighthouse_bucket]
  end
  
  def server
    "s3.amazonaws.com"
  end
  
  def buckets
    @s3.buckets.collect(&:name)
  end
  
  def save_file(data, filename, options={})
    s3_opts = options
    s3_opts.store(:acl, :public_read)
    object = bucket.objects.create(filename, data, s3_opts)
    return "#{object.public_url(:secure => true)}" rescue nil
  end
  
  protected 
  
  def connect! access_key_id, secret_access_key
    raise 'Provide S3 access keys!' unless access_key_id && secret_access_key
    AWS::S3.new(:access_key_id => access_key_id, :secret_access_key => secret_access_key, :s3_endpoint => server)
  end


end