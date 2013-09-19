module LighthouseExport
  require 'rubygems'
  require 'time'
  require 'csv'
  require 'json'
  require 'aws-sdk'
  require_relative 'rigor_s3'
  
  module Jira
    
    class Converter

      attr_reader :translator

      def initialize project_settings, options={}
        @jira_project = project_settings
        @export_directory = options[:export_directory] || File.dirname(__FILE__)
        @result_directory = options[:result_directory] || File.dirname(__FILE__)
        @result_filename = options[:result_filename] || "#{Time.now}_lighthouse_export_jira_converter.json"
        
        @converted_issues = []
        @translator = Translator.new(
          :priority_map => options[:priority_map],
          :user_map => options[:user_map],
          :s3 => options[:s3],
          :github_url => options[:github_url]
        )
      end

      def convert_project
        {
          :name => @jira_project[:name],
          :key => @jira_project[:key],
          :url => @jira_project[:url],
          :description => @jira_project[:description],
          :issues => @converted_issues.sort_by { |k| k[:externalId] }
        }
      end

      def export_files
        Dir.glob("#{@export_directory}/tickets/*/ticket.json")
      end

      def convert
        raise 'Wrong export directory!' if export_files.empty?
        export_files.each do |f|
          puts f
          ticket_file = File.open(f)
          current_dir = File.dirname(f)
          JSON.parse(ticket_file.read).each do |hash|
            puts hash
            @converted_issues << convert_issue(f, hash.last)
          end
        end
        write_results
      end

      def jira_fields
        [
          :priority, :description, :status, :resolution, :reporter, :issueType,
          :created, :updated, :summary, :assignee, :externalId, :labels,
          :comments, :history, :attachments
        ]
      end

      def convert_issue file, data
        issue = {}
        jira_fields.each do |field|
          data.merge!(:path => file.split("ticket.json").first) if field == :attachments
          issue[field] = self.translator.send(field, data)
        end
        issue
      end

      def result_location
        "#{@result_directory}/#{@result_filename}"
      end

      def converted_results
        {
          :projects => [
            self.convert_project
          ]
        }
      end

      def write_results
        File.open(result_location, 'w') do |f|
          f.write(converted_results.to_json)
        end        
      end

    end

    class Translator

      def initialize options={}
        @priority_map = options[:priority_map] || default_priorities
        @user_map = options[:user_map]
        raise 'Provide a user map!' unless @user_map
        @s3 = RigorS3.new(options[:s3])
        @github_url = options[:github_url]
      end

      def default_priorities
        {
          "High" => 'Major',
          "Medium" => 'Minor',
          "Low" => 'Trivial'
        }
      end

      
      def priority data
        if data['importance_name']
          @priority_map[data['importance_name']]
        else
          case data['importance']
          when 0..5
            'Trivial'
          when 6..10
            'Minor'
          when 11..20
            'Major'
          else
            'Critical'
          end
        end
      end

      def description data
        data['body']
      end

      def status data
        jira_status(data['state'])[:string]
      end

      def resolution data
        case data['state']
        when 'resolved'
          'Fixed'
        when 'invalid'
          'Invalid'
        when 'hold'
          'Hold'
        else
          nil
        end
      end

      def reporter data
        jira_user(:user_id => data['creator_id'])
      end

      def issueType data
        'Bug'
      end

      def created data
        data['created_at']
      end

      def updated data
        data['updated_at']
      end

      def summary data
        data['title']
      end

      def assignee data
        jira_user(:user_id => data['assigned_user_id'])
      end

      def externalId data
        data['number'].to_i
      end

      def labels data
        data['tag'] ? [data['tag'].gsub('"', '')] : []
      end

      def comments data
        comments_from_versions(data['versions'])
      end

      def history data
        history_from_versions(data['versions'])
      end

      def attachments data
        attachments_from_ticket(data['attachments'], :path => data[:path])
      end

      def jira_user options={}
        if options[:user_name]
          options[:user_name].gsub(' ', '.').downcase
        elsif options[:user_id]
          @user_map[options[:user_id]]
        else
          ''
        end
      end

      def jira_status status, options={}
        case status
        when 'new'
          string = 'Open'
          val = '1'
        when 'open'
          string = 'In Progress'
          val = '3'
        when 'resolved', 'invalid', 'hold'
          string = 'Closed'
          val = '6'
        # when 'invalid', 'hold'
        #   string = 'Resolved'
        #   val = '5'
        end
        {:string => string, :value => val}
      end

      def jira_item version, field, old_value
        case field
        when 'assigned_user'
          f = 'assignee'
          from_val = jira_user(:user_id => old_value)
          from_string = jira_user(:user_id => old_value)
          to_val = jira_user(:user_id => version['assigned_user_id'])
          to_string = jira_user(:user_id => version['assigned_user_id'])
        when 'state'
          f = 'status'
          old_status = jira_status(old_value)
          new_status = jira_status(version['state'])
          from_val = old_status[:value]
          from_string = old_status[:string]
          to_val = new_status[:value]
          to_string = new_status[:string]
          if version['state'] == 'invalid'
            resolution_to_val = 6
            resolution_to_string = 'Invalid'
          elsif version['state'] == 'hold'
            resolution_to_val = 7
            resolution_to_string = 'Hold'
          elsif version['state'] == 'resolved'
            resolution_to_val = 1
            resolution_to_string = 'Fixed'
          end

          if resolution_to_val && resolution_to_string
            resolution_history = {
              :fieldType => 'jira',
              :field => 'resolution',
              :from => -1,
              :fromString => 'Unresolved',
              :to => resolution_to_val,
              :toString => resolution_to_string
            }
          end
        when 'milestone', 'tag'
          return nil
        else
          f = field
          from_val = old_value
          from_string = old_value
          to_val = version[field]
          to_string = version[field]
        end
        item = {
          :fieldType => 'jira',
          :field => f,
          :from => from_val,
          :fromString => from_string,
          :to => to_val,
          :toString => to_string
        }
        resolution_history ? [item, resolution_history] : [item]
      end

      def history_from_versions versions
        return unless versions.any?
        histories = []
        versions.each do |v|
          if v['diffable_attributes'].any?
            items = []
            v['diffable_attributes'].each do |field, old_value|
              item = jira_item(v, field, old_value)
              next unless item
              items << item.flatten
            end
            history = {
              :author => jira_user(:user_name => v['user_name']),
              :created => v['created_at'],
              :items => items.flatten
            }
            histories << history if items.any?
          end
        end
        histories
      end

      def comments_from_versions versions
        return unless versions.any?
        comments = []
        versions.each do |v|
          commit_comment = v['body'] && v['body'].include?('(from [')
          next if (!commit_comment && v['diffable_attributes'].any?) || v['version'] == 1
          if v['body']
            if commit_comment && @github_url
              github_link = "#{@github_url}/commit/#{v['body'].split("/changesets/").last}"
              comment_body = "#{v['body']}\n\"View on Github\":#{github_link}"
            else
              comment_body = v['body']
            end
            comment = {
              :body => comment_body,
              :author => jira_user(:user_name => v['user_name']),
              :created => v['created_at']
            }
            comments << comment
          end
        end
        comments
      end

      def attachments_from_ticket attachments, options={}
        return [] unless attachments && attachments.any?
        # save attachments to s3 and use new url for jira import
        jira_attachments = []
        # save attachments to s3
        attachments.each_with_index do |a, index|
          attachment = a['image'] ? a['image'] : a['attachment']
          filename = attachment['filename']
          filepath = "#{options[:path]}#{filename}"
          content_type = attachment['content_type']
          contents = File.open(filepath).read
          data = contents
          s3_url = @s3.save_file(data, filename, :content_type => content_type)
          filename = "#{index}_#{filename}" if jira_attachments.map {|a| a[:name]}.include?(filename) # avoid duplicate filenames in jira
          a = {
            :name => filename,
            :attacher => jira_user(:user_id => attachment['uploader_id']),
            :created => attachment['created_at'],
            :uri => s3_url,
            :description => "original lighthouse url: #{attachment['url']}"
          }
          jira_attachments << a
        end
        jira_attachments
      end

    end

  end
end