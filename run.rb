#!/usr/bin/env ruby
require 'net/http'
require 'openssl'
require 'base64'
require 'json'
require 'pp'
require 'date'
require 'yaml'

PLAN_STATUSES = {
  0 => {:text => "Success", :bad => false},
  1 => {:text => "Overdue", :bad => true},
  2 => {:text => "Error", :bad => true},
  3 => {:text => "Running", :bad => false},
  4 => {:text => "Unknown", :bad => true},
  5 => {:text => "Interrupted", :bad => true},
  6 => {:text => "UnexpectedlyClosed", :bad => true},
  7 => {:text => "Warning", :bad => true}
}

PLAN_TYPES = {
  0 => {:text => "NA", :is_restore => false, :is_backup => false},
  1 => {:text => "Backup", :is_restore => false, :is_backup => true},
  2 => {:text => "Restore", :is_restore => true, :is_backup => false},
  3 => {:text => "BackupFiles", :is_restore => false, :is_backup => true},
  4 => {:text => "RestoreFiles", :is_restore => true, :is_backup => false},
  5 => {:text => "VMBackup", :is_restore => false, :is_backup => true},
  6 => {:text => "VMRestore", :is_restore => true, :is_backup => false},
  7 => {:text => "SQLBackup", :is_restore => false, :is_backup => true},
  8 => {:text => "SQLResore", :is_restore => true, :is_backup => false},
  9 => {:text => "ExchangeBackup", :is_restore => false, :is_backup => true},
  10 => {:text => "ExchangeRestore", :is_restore => true, :is_backup => false},
  11 => {:text => "BMSSBackup", :is_restore => false, :is_backup => true},
  12 => {:text => "BMSSRestore", :is_restore => true, :is_backup => false},
  13 => {:text => "ConsistencyCheck", :is_restore => false, :is_backup => false},
  14 => {:text => "EC2Backup", :is_restore => false, :is_backup => true},
  15 => {:text => "EC2Restore", :is_restore => true, :is_backup => false},
  16 => {:text => "HyperVBackup", :is_restore => false, :is_backup => true},
  17 => {:text => "HyperVRestore", :is_restore => true, :is_backup => false}
}

def load_settings
  begin
    return YAML.load_file('settings.yml')
  rescue
    puts "Error reading settings.yml. #{$!.message}"
    abort
  end
end

def get_access_token
  uri = URI("#{@settings[:api_settings][:endpoint]}/Provider/Login")
  req = Net::HTTP::Post.new(uri)
  req.body = {"UserName" => @settings[:api_settings][:username], "Password" => @settings[:api_settings][:password]}.to_json
  req['Content-Type'] = "application/json"
  JSON.parse(Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true) { |http| http.request(req) }.body)["access_token"]
end

def get_plan_details(token)
  uri = URI("#{@settings[:api_settings][:endpoint]}/Monitoring")
  req = Net::HTTP::Get.new(uri)
  req['Content-Type'] = "application/json"
  req['Authorization'] = "bearer #{token}"
  JSON.parse(Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true) { |http| http.request(req) }.body)
end

def send_telegram(message)
  uri = URI("https://api.telegram.org/bot#{@settings[:telegram_settings][:bot_key]}/sendMessage")
  begin
    res = Net::HTTP.post_form(uri, 'chat_id' => @settings[:telegram_settings][:chat_id], 'disable_web_page_preview' => '1', 'parse_mode' => 'Markdown', 'text' => message)
  rescue
    puts "Failed to send Telegram alert! Reason: " + $!.message
  end
end

#load settings
@settings = load_settings

#request access token from api
token = get_access_token

#request list of plans (and details)
plans = get_plan_details(token)

#filter out only the info we want from the json response
all_plans = plans.map { |p|
  {
    :company => p['CompanyName'], 
    :computer => p['ComputerName'], 
    :plan => p['PlanName'], 
    :type => p['PlanType'], 
    :lastrun => p['LastStart'].sub('T',' @ ').split('.')[0], 
    :lastrun_hours => ((DateTime.now.to_time - DateTime.parse("#{p['LastStart']} America/Chicago").to_time) / 3600).to_i,
    :report_url => p['DetailedReportLink'], 
    :status => p['Status'],
    :files_scanned => p['FilesScanned'],
    :files_to_backup => p['FilesToBackup'],
    :files_copied => p['FilesCopied'],
    :files_failed => p['FilesFailed']}
}

good_plans = Array.new
bad_plans = Array.new

all_plans.each do |p|
  # check if plan type is ignored
  next if @settings[:general_settings][:ignored_plantypes].include? p[:type].to_i

  # check plan status
  if PLAN_STATUSES[p[:status]][:bad] == true then
    if p[:lastrun_hours] < @settings[:general_settings][:overdue_thresh] && PLAN_TYPES[p[:type]][:is_restore] == false then 
      #skip missed backups within defined threshold
      #useful for ignoring missed backups over the weekend
      good_plans.push p
    else
      bad_plans.push p
    end
  else
    good_plans.push p
  end

end

#compose and send report
message = String.new
message << "*.:: SUMMARY ::.*\n"
message << "#{"-" * 40}\n"
message << "There are #{good_plans.count} plans in good standing\n"
message << "There are #{bad_plans.count} plans in BAD standing.\n"

message <<  "\n*.:: FAILED PLANS ::.*\n"
message << "#{"-" * 40}"
bad_plans.each do |p|
  message << "\n"
  message << "Company Name: #{p[:company]}\n"
  message << "Computer Name: #{p[:computer]}\n"
  message << "Plan Name: #{p[:plan]}\n"
  message << "Last Run: #{p[:lastrun]} (#{p[:lastrun_hours]} hours ago)\n"
  message << "Plan Type: #{PLAN_TYPES[p[:type]][:text]}\n"
  message << "Plan Status: #{PLAN_STATUSES[p[:status]][:text]}\n"
  message << "Report: [View](#{p[:report_url]})\n" if ! p[:report_url].nil?
end

message <<  "\n*.:: WARNING BACKUPS ::.*\n"
message << "#{"-" * 40}"

good_plans.each do |p|
  # skip over plan that isn't a backup
  next if PLAN_TYPES[p[:type]][:is_backup] == false

  do_warn = false

  # warn if we didn't back everything up
  do_warn = true if p[:files_to_backup].to_i > p[:files_copied].to_i

  # warn if any files failed
  do_warn = true if p[:files_failed].to_i > 0

  # warn if we scanned no files
  do_warn = true if p[:files_scanned].to_i == 0

  next unless do_warn

  message << "\n#{p[:computer]} (#{p[:company]})\n"
  message << "#{' ' * 3}- #{p[:files_scanned]} files scanned\n"
  message << "#{' ' * 3}- #{p[:files_to_backup]} files to backup\n"
  message << "#{' ' * 3}- #{p[:files_copied]} files copied\n"
  message << "#{' ' * 3}- #{p[:files_failed]} files failed\n"
end

send_telegram message

#DEBUGGING STUFF
#puts message
#puts ".:: GOOD PLANS ::.\n#{pp good_plans}\n\n.:: BAD PLANS ::.\n#{pp bad_plans}"
