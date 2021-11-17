# dynmotd
Dynamic Motd (Message of the Day) an old script to print out some system-specific information.

![Example](/data/dynmotd.png)


# Tested Linux Distributions

| Distribution 	| Status                |
|--------------	|----------------------	|
| CentOS 8     	| Successfully tested   |
| Debian 8     	| Successfully tested   |
| Debian 9     	| Successfully tested  	|
| Debian 10    	| Successfully tested  	|
| Ubuntu 18     | Successfully tested  	|
| Ubuntu 20     | Successfully tested  	|
| Rocky Linux 8 | Successfully tested.  |


Pre-Setup Debian and Ubuntu
---------------------------

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
cp dynmotd.sh /usr/local/bin/dynmotd
chmod 777 /usr/local/bin/dynmotd
echo "/usr/local/bin/dynmotd" > /etc/profile.d/motd.sh
~~~

Test dynmotd

~~~
exit
sudo -i
~~~

Parameter 
---------

~~~
Usage: dynmotd [-c|-a|-d|--help] <params>

    e.g. dynmotd -a "start web migration"

    Parameter:

      -a | addlog  | --addlog "..."             add new log entry
      -d | rmlog   | --rmlog [loglinenumber]    to delete a specific log entry use -l to identify
      -l | log     | --log                      list complete log
      -c | config  | --config                   configuration setup
~~~

Some dynmotd Options
--------------------

~~~
vim /usr/local/bin/dynmotd
~~~

You can enable or disable information blocks 

~~~
## enable system related information about your system
SYSTEM_INFO="1"
STORAGE_INFO="1"
USER_INFO="1"
ENVIRONMENT_INFO="1"
MAINTENANCE_INFO="0"
VERSION_INFO="1"
~~~

 * 1 = enable
 * 0 = disable

You can also change the number of log lines displayed by changing "LIST_LOG_ENTRY".

~~~
LIST_LOG_ENTRY="5"
~~~
