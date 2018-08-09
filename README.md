# BYOLWebService
----------------
1. Post-Sysprep-Windows.ps1 is for windows which located in C:\Program Files\Cloudbase Solutions\Cloudbase-Init\LocalScripts\.

2. vendor_data.json and cloudinit-vendordata.sh are for linux, vendor_data.json was configure in /etc/nova/vendordata.json, cloudinit-vendordata.sh should deploy on https://100.125.xx.xx/repo/tools/cloudinit-vendordata.sh.

###Pushing the Vendor Data File:

Step 1	Run the following command to upload the vendor data file to all nova-api-deployed nodes at the cascading layer and enter the password of user root as prompted: 
- ansible fs61_nova_api_cascading -m copy -a "src=/home/admin/vendordata.json dest=/etc/nova owner=fsp group=fsp mode=0777" -u fsp --su --su-user=root --ask-su-pass --private-key=/home/admin/id_rsa

Step 2	Run the following command to change the file permission:
- ansible fs61_nova_api_cascading -m command -a "chown openstack:openstack /etc/nova/vendordata.json" -u fsp --su --su-user=root --ask-su-pass --private-key=/home/admin/id_rsa
----End
