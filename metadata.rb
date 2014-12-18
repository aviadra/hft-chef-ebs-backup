name             'hft-chef-ebs-backup'
maintainer       'Hotfortech'
maintainer_email 'aviad.raviv@adallom.com'
license          'All rights reserved'
description      'Cookbook to create LVM stripped arrays (supports AES)'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '1.0.0'

depends "aws"
depends "lvm"
depends "awscli"