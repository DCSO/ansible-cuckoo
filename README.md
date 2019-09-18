# All in one ansible script to deploy a cuckoo instance

## Description
This ansible script deploys a working, reboot steady cuckoo installation on Debian stretch and buster.
The malware traffic gets routed through tor.
All dependencies are pinned so updates won't break the setup. This script generates appropriate
systemd service files, is somewhat baselined for common domains and most important, generates a fully working
Virtualbox image for cuckoo without any user interaction. The generated Windows image is setup with anti vm
detection in mind. Using [pafish](https://github.com/a0rtega/pafish) as reference. This script does not need
the Virtualbox extension pack which is licensed under the PUEL. It also deploys a self-signed version of the cuckoo driver
from hatching (which is closed source but permissively licensed).

Blogpost: https://hatching.io/blog/onemon-cuckoo-release  
License of driver: https://hatching.io/static/other/onemon-license.txt


## Configuration

In the file `site.yml` there are all variables used in the playbook. You can change these to your liking.
Interesting variables are for example:
```
num_cuckoo_processes: "8" --> The number of workers for postprocess analysis
choco_source: "https://chocolatey.org/api/v2/"
dnsserver_ip: "1.1.1.1" --> DNS server of malware vm
```

## Pafish output
```
[pafish] Start
[pafish] Windows version: 6.1 build 7600
[pafish] CPU: GenuineIntel Intel(R) Xeon(R) Silver 4114 CPU @ 2.20GHz
[pafish] CPU VM traced by checking the difference between CPU timestamp counters (rdtsc)
[pafish] CPU VM traced by checking the difference between CPU timestamp counters (rdtsc) forcing VM exit
[pafish] Sandbox traced using mouse activity
[pafish] Hooks traced using ShellExecuteExW method 1
[pafish] VirtualBox device identifiers traced using WMI
[pafish] End
```

## Dependencies
Install ansible 2.7.6 or higher.
To check your currently installed version execute:
```
$ ansible --version
```

## How to execute
```
$ ansible-playbook -i "host@192.168.122.45," site.yml --ask-become-pass
```
OR
```
./run.sh host@192.168.122.45
```

Note: The semicolon after the ip address is there on purpose.
Without it ansible doesn't recognize it as an entry in an inventory file.

## Without prompts
To execute the ansible script without user input the variables have to be defined on the commandline. Look at the run.sh or in https://docs.ansible.com/ansible/2.6/user_guide/playbooks_variables.html#passing-variables-on-the-command-line


To install the latest version of ansible on any os go to to the
[ansible doc](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#intro-installation-guide)

## Updating malboxes package
Execute the following in the root directory
```
$ rm roles/cuckoo/files/malboxes-deps/*
$ pip3 download git+ssh://github.com:DCSO/malboxes.git -d roles/cuckoo/files/malboxes-deps
```

## Updating cuckoo package
Execute the following in the root directory
```
$ rm  roles/cuckoo/files/cuckoo/Cuckoo-*.tar.gz
$ pip2 download Cuckoo -d roles/cuckoo/files/cuckoo --no-deps
```

## Notes
This script uses chocolatey to install software on the Windows vm. If you deploy a lot of cuckoo instances it
is a good idea to set up a chocolatey proxy like [Nexus](https://www.sonatype.com/download-oss-sonatype) to prevent hitting
API limits.


## Debugging the VM
To troubleshoot the VM you can execute the command: `cuckoo-vm-debug`.
This will install the virtualbox extension and setup a remote RDP without password to the
malware virtual machine. To save the changes to a vm execute:
```
$ vboxmanage snapshot cuckoo_win7_64_1 take --live
```

## Service names
* cuckoo-rooter  --> Routes the traffic through tor/vpn
* cuckoo-daemon  --> The main cuckoo daemon
* cuckoo-process --> Worker for the cuckoo daemon
* cuckoo-web     --> The web interface for cuckoo
* cuckoo-api     --> The web api of cuckoo
* vboxinterfaces --> Spawns the vbox interface on boot to be able to let tor listen on it


## Cuckoo API
[REST Documentation](https://cuckoo.readthedocs.io/en/latest/usage/api/#resources)  
The cuckoo api is reachable over port 8090 on all interfaces. The API key is written under
`/home/cuckoo/.cuckoo/conf/cuckoo.conf` and gets generated at random. To include the password into
a request there has to be a header named: `Authorization` with content ` Bearer <Password>`


## Stuck in Build VM / Download failed
Malboxes downloads its Windows ISO from
```
http://care.dlservice.microsoft.com/dl/download/evalx/win7/x64/EN/7600.16385.090713-1255_x64fre_enterprise_en-us_EVAL_Eval_Enterprise-GRMCENXEVAL_EN_DVD.iso
```
with the user agent
```
Mozilla/5.0 (X11; Linux x86_64; rv:69.0) Gecko/20100101 Firefox/69.0
```
because they block [some user agents](https://github.com/hashicorp/packer/issues/6560) for no apparent reason.
The download path is
```
/home/cuckoo/ISO/7600.16385.090713-1255_x64fre_enterprise_en-us_EVAL_Eval_Enterprise-GRMCENXEVAL_EN_DVD.iso
```
and it has to have the sha1 checksum `15ddabafa72071a06d5213b486a02d5b55cb7070`.
You can manually download the file and place it there or change the download url / user agent with the config found under `/home/cuckoo/.config/malboxes/config.js`


## VM does not have internet access
The cuckoo rooter sets iptable rules dynamically.
If you have a firewall configured with `Policy DROP` then you have to allow the routing from the vbox interface to the tor port explicitly.


## Cuckoo daemon fails to connect and crashes
This is probably the cause of elasticsearch not yet being reachable. There is a hardcoded sleep of 60 seconds which should suffice but if you server is very slow you might want to increase the wait time in `/lib/systemd/system/cuckoo-daemon.service`


## Debugging cuckoo
To restart all services execute as root:
```
$ systemctl status cuckoo-*
$ systemctl restart cuckoo-*
```
An often occured issue was that the virtualbox vbox interface wasn't available on boot which
created the problem that tor couldn't listen on that interface and then crashed. This has been fixed
with the vboxinterfaces service, but it is rather hacky. If tor crashed on reboot check if that is the problem.

If the result server is not reachable make sure that the resultserver ip is set to your cuckoo hosting machine.


## Setting up parallel vm analysis
Run this as `cuckoo` user:
```
$ VBoxManage snapshot cuckoo_win7_64_0 restorecurrent
$ VBoxManage clonevm cuckoo_win7_64_0 --name cuckoo_win7_64_1
$ VBoxManage registervm ~/VirtualBox\ VMs/cuckoo_win7_64_1/cuckoo_win7_64_1.vbox
$ VBoxManage startvm cuckoo_win7_64_1 --type headless
$ VBoxManage controlvm cuckoo_win7_64_1 acpipowerbutton
$ VBoxManage modifyvm cuckoo_win7_64_1 --macaddress2 $(python -c "import random; print('020000%02x%02x%02x' % (random.randint(0, 255), random.randint(0, 255), random.randint(0, 255)))")
$ cuckoo-vm-debug cuckoo_win7_64_1
```

Now connect to the vm via RDP and change the static ip with.
```
netsh int ip set address "local area connection 2" static 192.168.56.102 255.255.255.0 192.168.56.1
```
Note: To connect via RDP with Remmina the setting 'Use client resolution' has to be toggled on.

Afterwards execute and stop the RDP connection.
```
$ cuckoo-vm-debug cuckoo_win7_64_1
$ VBoxManage startvm cuckoo_win7_64_1 --type headless
$ VBoxManage snapshot cuckoo_win7_64_1 take --live
```

Now edit the `/home/cuckoo/.cuckoo/conf/virtualbox.conf` and add:
```
machines = cuckoo0, cuckoo1


[cuckoo1]
# Specify the label name of the current machine as specified in your
# VirtualBox configuration.
label = cuckoo_win7_64_1
platform = windows
ip = 192.168.56.102
snapshot =
interface =
resultserver_ip =
resultserver_port =
tags =
options = analysis=kernel
# (Optional) Specify the OS profile to be used by volatility for this
# virtual machine. This will override the guest_profile variable in
# memory.conf which solves the problem of having multiple types of VMs
# and properly determining which profile to use.
osprofile =
```
Afterwards execute to restart all cuckoo services.
```
$ systemctl restart cuckoo-*
```

Now check if the cuckoo daemon recognized your changes with
```
$ systemctl status cuckoo-daemon
```
There should be a line saying:
```
[cuckoo.core.scheduler] INFO: Loaded 2 machine/s
```

## Licenses
* [Malboxes](https://github.com/GoSecure/malboxes/blob/master/LICENSE)
* [Onemon driver](https://hatching.io/static/other/onemon-license.txt)
* [VirtualBox](https://www.virtualbox.org/wiki/Licensing_FAQ)
* [Packer](https://github.com/hashicorp/packer/blob/master/LICENSE)
