# dynmotd
Dynamic Motd (Message of the Day) an old script to print out some system-specific information.

![Example](/data/dynmotd.png)

# Useful Functions
* easy to create own color schemes
* enabling or disabling information sections
* specific system description for each system
* maintenance logging
* only one shell script
* multi OS support
* easily extendable
* less dependencies

# Tested Linux Distributions

| Distribution 	  | Status                |
|-----------------|-----------------------|
| CentOS 8     	  | Successfully tested   |
| Debian 8        | Successfully tested   |
| Debian 9     	  | Successfully tested   |
| Debian 10       | Successfully tested   |
| Debian 11    	  | Successfully tested   |
| Debian 12       | Successfully tested   |
| Ubuntu 18       | Successfully tested   |
| Ubuntu 20       | Successfully tested   |
| Rocky Linux 8   | Successfully tested.  |
| Raspberry Pi OS | Successfully tested.  |


Pre-Setup Debian,Rasbian and Ubuntu 
-----------------------------------

Install default packages:

~~~
apt install coreutils bc procps hostname sed mawk grep bind9-host lsb-release git
~~~

Pre-Setup CentOS, Rocky Linux and RedHat
----------------------------------------

Install default packages:

~~~
yum install bc bind-utils redhat-lsb-core git 
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

Test dynmotd

~~~
exit
sudo -i
~~~
or try ssh reconnect to your system

Parameter 
---------

~~~
Usage: dynmotd [-c|-a|-d|--install|--help] <params>

    e.g. dynmotd -a "start web migration"

    Parameter:

      -a | addlog  | --addlog "..."             add new log entry
      -d | rmlog   | --rmlog [loglinenumber]    to delete a specific log entry use -l to identify
      -l | log     | --log                      list complete log
      -c | config  | --config                   configuration setup
      -i | install | --install                  install dynmotd
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
MAINTENANCE_INFO="1"        # show maintenance infomration
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

### The FQDN or hostname is not displayed correctly?
The FQDN Full Qualified Domain Name is not displayed correctly if it has not been made known to the system in the /etc/hostname file. In this case, the matching exposed IP cannot be displayed correctly either.

Example: The command: `hostname --fqdn` produces the following output:
~~~
mail
~~~

This is probably due to the fact that only "mail" has been entered in the /etc/hostname file. 
This can be remedied as follows:
~~~
hostname subdomain.domain.tld
echo "subdomain.domain.tld" >/etc/hostname
~~~

Example:
~~~
hostname mail.linux-hub.ch
echo mail.linux-hub.ch >/etc/hostname
~~~

You can check it with the following command.
~~~
hostname --fqdn
mail.linux-hub.ch
~~~

### UPDATE_INFO="1" displays errors
When I have activated UPDATE_INFO="1" I get errors. This may be because you are not working on a Debian based system. If you are not working on a Debian based system you should set the option UPDATE_INFO="0" so that this info block is not displayed.  Maybe this will be a feature for the future.
