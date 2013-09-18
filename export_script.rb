require './lib/lighthouse_export/lighthouse_export.rb'

project = {
  :name => 'test',
  :key => "TST",
  :url => 'www.tester.com',
  :description => 'best app ever'
}

export_path = "path/to/lighthouse_export"

users = {
  #lighthouse_user_id => 'jira.username'
  12345  => 'user.name',
  nil => ''
}

e = LighthouseExport::Jira::Converter.new(project,
  :export_directory => export_path,
  :user_map => users,
  :s3 => {
    :access_key_id => "S3 access key id",
    :secret_access_key => "S3 secret access key"
  }
)

e.convert