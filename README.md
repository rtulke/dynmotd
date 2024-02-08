# dynmotd
Dynamic Motd (Message of the Day) an old script to print out some system-specific information.

![Example](/data/screenshot.png)

# Useful Functions
* easy to create own color schemes
* enabling or disabling information sections
* specific system description for each system
* maintenance logging
* only one shell script
* multi OS support
* easily extendable
* less dependencies

New features comming soon
* GeoIP Information
* Weather Information 
* better Multi OS support
* NewsFeeder?

# Tested Linux Distributions

| Distribution 	     | Status               |
|--------------------|----------------------|
| CentOS 8 - 9	     | Successfully tested  |
| Debian 8 - 12      | Successfully tested  |
| Ubuntu 18 - 23.10  | Successfully tested  |
| Fedora 38 - 39     | Successfully tested  |
| Rocky Linux 8 - 9  | Successfully tested  |
| Raspberry Pi OS    | Successfully tested  |


Pre-Setup Debian, Rasbian and Ubuntu 
------------------------------------

Install default packages:

~~~
apt update && apt upgrade
apt install coreutils bc procps hostname sed mawk grep bind9-host lsb-release git
~~~

Pre-Setup CentOS, Rocky Linux and RedHat
----------------------------------------

Install default packages:

~~~
yum install bc bind-utils redhat-lsb-core git 
~~~

Alma Linux
----------

Install default packages:

~~~
dnf install bc git bind-utils almalinux-release
~~~


Installation
------------

Script runs only as root.

~~~
sudo -i
git clone https://github.com/rtulke/dynmotd.git
cd dynmotd
./dynmotd.sh --install
~~~

To test dynmotd properly, you should log out of the system and log in again.
If you have logged in directly via ssh root, log in to the server again.

~~~
exit
sudo -i
~~~


Parameter 
---------

~~~
Usage: dynmotd [-c|-a|-d|--install|--help] <params>

    e.g. dynmotd -a "start web migration"

    Parameter:

    -a | addlog    | --addlog "..."             add new log entry
    -d | rmlog     | --rmlog [loglinenumber]    delete a specific log entry by using -l to identify the line number
    -l | log       | --log                      list log entries
    -c | config    | --config                   restart setup
    -i | install   | --install                  install dynmotd
    -u | uninstall | --uninstall                uninstall dynmotd
~~~

Some dynmotd Options
--------------------

~~~
vim /usr/local/bin/dynmotd
~~~

You can enable or disable information blocks 

~~~
## enable system related information about your system
SYSTEM_INFO="1"             # show system information
STORAGE_INFO="1"            # show storage information
USER_INFO="1"               # show some user infomration
ENVIRONMENT_INFO="1"        # show environement information
MAINTENANCE_INFO="1"        # show maintenance information
UPDATE_INFO="0"             # show update information, deactivate when using redhat
VERSION_INFO="1"            # show the version banner
~~~

 * 1 = enable
 * 0 = disable

You can also change the number of log lines displayed by changing "LIST_LOG_ENTRY".

~~~
LIST_LOG_ENTRY="5"
~~~

Known Issues
------------

### The FQDN or hostname or IP Address is not displayed correctly?
The FQDN Full Qualified Domain Name is not displayed correctly if it has not been made known to the system in the /etc/hostname file. In this case, the matching exposed IP cannot be displayed correctly either.

Example: The command: `hostname --fqdn` produces the following output:
~~~
mail
~~~

This is probably due to the fact that only "mail" has been entered in the /etc/hostname file. 
This can be remedied as follows:
~~~
hostname subdomain.domain.tld
hostname >/etc/hostname
~~~

Example:
~~~
hostname mail.linux-hub.ch
hostname >/etc/hostname
~~~

You can check it with the following command.
~~~
hostname --fqdn
mail.linux-hub.ch
~~~

check also the `/etc/hosts` entry

~~~
127.0.1.1 mail.linux-hub.ch
~~~

### UPDATE_INFO="1" displays errors
When I have activated UPDATE_INFO="1" I get errors. This may be because you are not working on a Debian based system. If you are not working on a Debian based system you should set the option UPDATE_INFO="0" so that this info block is not displayed.  Maybe this will be a feature for the future.

### In "User Data" info block, SshKeyRootUsers shows "- Unkown -"
This always happens if the SSH key has no comment that indicates which SSH key it is. To fix the problem, you either have to enter an additional name or e-mail address at the end of the key in the ~/.ssh/authorized_keys file using a space or create your SSH keys with ssh-keygen -C "YourNameHere"
