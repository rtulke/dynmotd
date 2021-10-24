# dynmotd
Dynamic Motd (Message of the Day) an old script to print out some system-specific information.


![Example](/data/dynmotd.png)


Requirements
------------

awk, egrep, sed, whoami, hostname, touch, source, rm, who, sort, uniq, tty, ps, ulimit, groups, cat, cut, wc, uptime, bc, uname, host, id, bash, df, 

Installation
------------


~~~
git clone https://github.com/rtulke/dynmotd.git
cd dynmotd
chmod 700 *.sh
mv *.sh /usr/local/bin/
chmod 777 /usr/local/bin/dynmotd
~~~~

**enabled dynmotd to display all informations after user login (only root)**

~~~
echo "/usr/local/bin/dynmotd" > /etc/profile.d/motd.sh
~~~

Commands 
--------
* addlog, add a new log entry into the .maintenance file
* rmlog, delete a specific line in .maintenance 
* listlog, list all .maintenance log entries
* dynmotd, shows system informations
