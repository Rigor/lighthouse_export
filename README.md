Lighthouse Export
=================

This exporter will convert exported Lighthouse tickets into a single JSON file formatted for import into JIRA.
It assumes that the project does NOT already exist in JIRA and that users DO exist.

It also uses S3 to upload Lighthouse attachments for reference in the imported JIRA tickets.

*Have improvements? Submit a pull request!*

### Usage

Setup project information in the export script:
```ruby
project = {
  :name => 'test',
  :key => "TST",
  :url => 'www.tester.com',
  :description => 'best app ever'
}
```

Provide the path to the Lighthouse export directory:
```ruby
export_path = "path/to/lighthouse_export"
```

Provide a hash of users (Lighthouse user id as key, JIRA username as value):
```ruby
users = {
  # lighthouse_user_id => 'jira.username'
  12345  => 'user.name',
  nil => ''
}
```

Set AWS S3 access keys to save attachments to S3:
```ruby
access_key = "My S3 access key id"
secret = "My S3 secret access key"
```

Initialize the converter, passing in the setup stuff:
```ruby
e = LighthouseExport::Jira::Converter.new(project,
  :export_directory => export_path,
  :user_map => users,
  :s3 => {
    :access_key_id => access_key,
    :secret_access_key => secret
  }
)
```

Call convert to create the JIRA JSON Importer formatted file:
```ruby
e.convert
```

### Additional Options
```ruby
e = LighthouseExport::Jira::Converter.new(project,
  :export_directory => export_path,
  :result_directory => 'path/to/save/converted_file', # defaults to script directory
  :result_filename => 'name_for_converted_file.json', # default: "#{Time.now}_lighthouse_export_jira_converter.json"
  :priority_map => {
    # translate lighthouse priorities to jira priorities
    "High" => 'Major',
    "Medium" => 'Minor',
    "Low" => 'Trivial'
  },
  :user_map => users,
  :s3 => {
    :bucket => 'bucket-to-upload-lighthouse-attachments', # defaults to 'lighthouse-attachments'
    :access_key_id => access_key,
    :secret_access_key => secret
  },
  :github_url => 'https://github.com/myaccount/myproject' # if present, adds a link to the commit on Github to commit comments
)
```


[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/Rigor/lighthouse_export/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

