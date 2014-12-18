# Backs up disks
#
# Cookbook Name:: hft-chef-ebs-backup
#
# All rights reserved - Do Not Redistribute
#
Chef::Log.info("hft-chef-ebs-backups - Start of backup recipe")
aws = data_bag_item("aws", node['aws'].fetch('databag_entry','main'))

bk_user = node['hft-chef-ebs-backups']['user']

user bk_user do
  comment "EBS backup User"
  shell   "/bin/bash"
  action  :create
end


node.set[:awscli][:config_profiles][:default][:aws_access_key_id] = aws['aws_access_key_id']
node.set[:awscli][:config_profiles][:default][:aws_secret_access_key ] = aws['aws_secret_access_key']

include_recipe "awscli"

#AWS info grab
instance_id=`wget -q -O- http://169.254.169.254/latest/meta-data/instance-id`
node_locationAZ = `wget -q -O- http://169.254.169.254/latest/meta-data/placement/availability-zone`
node_location = node_locationAZ[0...-1]

#Designated devices arbitration, identification and sanitation
#variable setup
node.run_state['vols_to_backup'] = []
designated_devices_directives = []
pre_backup_cmds = []
post_backup_cmds =[]

if node['hft-chef-ebs-backup'].nil? or node['hft-chef-ebs-backup'].fetch('devices_to_backup', nil).nil?
  Chef::Log.info("hft-chef-ebs-backups - Designated devices - NO backup_title directives found")
  use_designated_devices = false
else
  Chef::Log.info("hft-chef-ebs-backups - Designated devices - Found directives")
  use_designated_devices = true
  Chef::Log.info("hft-chef-ebs-backups - Designated devices - use_designated_devices has been set to: " + use_designated_devices.to_s)
  node['hft-chef-ebs-backup']['devices_to_backup'].each do |(backup_title,meta_attributes)|
    Chef::Log.info("hft-chef-ebs-backups - Designated devices - Found backup_title of: " + backup_title.to_s + " and meta_attributes of: " + meta_attributes.to_s)
    
    #set working attributes
    type = meta_attributes.fetch('type',"regular")
    
    #injecting pre+post scripts to conglomeration
    pre_backup_cmds << meta_attributes.fetch('pre_backup_cmd',[])
    post_backup_cmds << meta_attributes.fetch('post_backup_cmd',[])

    #working on obtaining devices to backup from supported types (regular, lvm and md)
    Chef::Log.info("hft-chef-ebs-backups - Designated devices - Found for backup_title of: " + backup_title.to_s + " a device type \"type\" of: " + type.to_s)
    case type
	    when "regular", "r"
			Chef::Log.info("hft-chef-ebs-backups - Designated devices - This is a \"regular\" device. Only pushing " + meta_attributes.location.to_s + " into conglomerated array.")
			designated_devices_directives << meta_attributes.location
		when "lvm", "LVM"
			Chef::Log.info("hft-chef-ebs-backups - Designated devices - Found a none-regular device to cipher of \"type\": " + type.to_s)
			#Finding devices the pool name maps to
			mapping_raw = `vgdisplay #{meta_attributes.location}  --noheadings -C -o pv_name`
		when "md", "MD", "mdadm"
			Chef::Log.info("hft-chef-ebs-backups - Designated devices - Found a none-regular device to cipher of \"type\": " + type.to_s)
			#Finding devices the MD name maps to
			mapping_raw = `mdadm -D /dev/#{meta_attributes.location} | grep sync | awk '{print $7}'`
		else
	    	Chef::Application.fatal!("hft-chef-ebs-backups - Designated devices - Error, the device type of: \"" + type.to_s + "\", is not valid for arbitration :(.", 42)
	#End of "case"
	end

	#Converting all raw mappings obtained to an array format
	unless mapping_raw.nil?
		mapping_array = mapping_raw.gsub(/\n/," ").split 
		designated_devices_directives << mapping_array
	end
	Chef::Log.info("hft-chef-ebs-backups - Designated devices - designated_devices_directives after " + backup_title + ", has been set to: " + designated_devices_directives.to_s)
	#End of "each" loop
	end
    
	Chef::Log.info("hft-chef-ebs-backups - Designated devices - Conglomerated designated_devices_directives (flatten-ed + uniq-ed) has been set to: " + designated_devices_directives.flatten.uniq.to_s)
	Chef::Log.info("hft-chef-ebs-backups - Designated devices - Conglomerated pre_backup_cmds(flatten-ed + uniq-ed) has been set to: " + pre_backup_cmds.flatten.uniq.to_s)
	Chef::Log.info("hft-chef-ebs-backups - Designated devices - Conglomerated post_backup_cmds(flatten-ed + uniq-ed) has been set to: " + post_backup_cmds.flatten.uniq.to_s)
	
	#Extracting vol_ids from dev names
	ruby_block "hft-chef-ebs-backups - vol extractor" do
		action :run
		block do
			vols_to_backup=[]
			designated_devices_directives.flatten.uniq.each do |device_xen|
			#special case for xvda1
			if device_xen == "/dev/xvda"
				device_xen = device_xen.sub("xvda", "xvda1")
			end
			# sanity check that the device is part of the system
			Chef::Application.fatal!("hft-chef-ebs-backups - Designated devices - Error, the device \"" + device_xen.to_s + "\" doesn't exist :(.", 42) unless ::File.exist?(device_xen)
			#De-Xen name the device list to we can look for them in the VM description.
			device_un_xened = device_xen.sub("xvd", "sd")
				vol=`aws ec2 --region #{node_location} describe-volumes --filters Name=attachment.instance-id,Values=#{instance_id} Name=attachment.device,Values=#{device_un_xened} --query Volumes[].VolumeId --output text`
			  	Chef::Log.info("hft-chef-ebs-backups - vol extractor - a vol of: " + vol.to_s + " from device_xen of: " + device_xen.to_s + " which converted to device_un_xened: " + device_un_xened.to_s)
				vols_to_backup << vol.gsub(/\n/," ").split
			end
			# vols_to_backup = vols_to_backup.flatten
			node.run_state['vols_to_backup'] = vols_to_backup.flatten
			Chef::Log.info("hft-chef-ebs-backups - vol extractor - vols_to_backup is now: " + vols_to_backup.flatten.to_s)
			Chef::Log.info("hft-chef-ebs-backups - vol extractor - node.run_state['vols_to_backup'] is now: " + node.run_state['vols_to_backup'].to_s)
		end
	end
end

#Creating the backup script
Chef::Log.info("hft-chef-ebs-backups - Creating backup snapshots script")
template ::File.join("/home/",bk_user,"/backup_with_snapshot.sh/") do
  source "snapshot.erb"
  mode 0500
  owner bk_user
  group bk_user
  variables lazy {{
			:snapshot_zabbix_dipstick => ::File.join("/home/",bk_user,"zabbix_backup_snapshot_yey"),
			:aws_access_key => aws["aws_access_key_id"],
			:aws_secret_key => aws["aws_secret_access_key"],
			:days_to_retain => node['type'] == "dev" ? 1 : node['hft-chef-ebs-backup']['retention'],
			:node_location => node_location,
			:send_retry_limit => node['type'] == "dev" ? 5 : 240, #This is minutes
			:mongo_node => node['hft-chef-ebs-backup']['mongo_node'] ? true : false,
			:snapshot_replication_lag => 600,
			:pre_backup_cmds => pre_backup_cmds.flatten.uniq,
			:post_backup_cmds => post_backup_cmds.flatten.uniq,
			:use_designated_devices => use_designated_devices,
			:designated_devices_directives => node.run_state['vols_to_backup'].empty? ? [] : node.run_state['vols_to_backup'],
            }}
end
#Creating the retention script
Chef::Log.info("hft-chef-ebs-backups - Creating backup snapshots retention script")
template ::File.join("/home/",bk_user,"snapshots-retention.sh") do
  source "snapshot_retention.erb"
  mode 0500
  owner bk_user
  group bk_user
  variables({
              :snapshot_zabbix_dipstick => ::File.join("/home/",bk_user,"zabbix_backup_snapshot_retention_yey"),
              :aws_access_key => aws["aws_access_key_id"],
              :aws_secret_key => aws["aws_secret_access_key"],
              :days_to_retain => node['type'] == "dev" ? 1 : node['hft-chef-ebs-backup']['retention'],
              :node_location => node_location,
              :send_retry_limit => node['type'] == "dev" ? 5 : 100, #This is minutes
              :mongo_node => node['hft-chef-ebs-backup']['mongo_node'] ? true : false
            })
end

#Backup cron - Hourly snapshot
cron "Backups - Snapshot" do
	user "root"
	minute "0"
	hour "*/1"
	command ::File.join("/home/",bk_user,"/backup_with_snapshot.sh")
	action :create
end
#Backup cron - Daily retention cleanup
cron "Backups - Retention" do
  user "root"
  minute "0"
  hour "1"
  command ::File.join("/home/",bk_user,"snapshots-retention.sh")
  action :create
end

Chef::Log.info("hft-chef-ebs-backups - End of backup recipe")

