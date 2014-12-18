hft-chef-ebs-backup Cookbook
=====================
This cookbook is used to create LVMs. If it is running on AWS/EC2, it can also request disks automatically

Usage
-----
When using the cookbook, you need to include it in the runlist (we "cuttingly" do it by adding it to the role).
We've designed it so that if you wish to use it and have it work automatically for all disks on the system, it must be last in the runlist. (Otherwize, there may be disks that get added to the system dynamically after it has finished its run, and it will be unaware of them, until the next chef run.)

If you don't declare anything, all disks on the system will be backed-up

Required
----------
type - If you are trying to use anything other then a "regular" disk (i.e. LVM or MD), you must declare your intentions. Otherwise the cookbook will not be able to find the disks. Option are: "r","regular","lvm","LVM","md","MD".

location - If you are passing directives, You must declare a "location". Options are: Simple device name: "/dev/xvdh". An array of device names: ["/dev/xvdh","/dev/xvdk"]. LVM "volume group" name: "mongo-pool00" (must be coupled with type attribute of LVM or invoked from the hft-chef-lvm "snapshot_backup": true attribute). MDadm (a.k.a Linux RAID) device name: "md0" (must be coupled with type attribute of MD).

Optionals
----------
pre_backup_cmd/post_backup_cmd - You may declare per and post scripts you wish the machine will run before and after the backup. Note: multiple entries are conglomerated and run in no particular order for all snapshot directives regardless to if they belong to other disks on the machine. Also, if the exact same cmd is declared, only one occurrence will be considered. Options can be: Simple command, for example: "ls -lash". An array of commands, for example: ["ls -lash", "ps-ef"]. Note: you may declare other scripts to be invoked, but there is no protection if they cause the script to error out, or if they even exist on the system.



Attributes
----------
in a role or environment Json, this would look like:
"hft-chef-ebs-backup": {
      "devices_to_backup" : {
        "mongo2_gever" : {
          "location" : "/dev/xvdh",
          "type" : "r",
          "pre_backup_cmd" : "echo velan_my_trimbers"
        }
      }
    }



e.g.

Contributing
------------
TODO: (optional) If this is a public cookbook, detail the process for contributing. If this is a private cookbook, remove this section.

e.g.
1. Fork the repository on Github
2. Create a named feature branch (like `add_component_x`)
3. Write you change
4. Write tests for your change (if applicable)
5. Run the tests, ensuring they all pass
6. Submit a Pull Request using Github

License and Authors
-------------------
Authors: Aviad
