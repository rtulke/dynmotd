# dynmotd
Dynamic Motd (Message of the Day) a Script to print out all system specific informations

![Example](/images/rpen1.png)


Requirements
------------

* awk, egrep, sed, whoami, hostname, touch, source, rm, who, sort, uniq, tty, ps, ulimit, groups, cat, cut, wc, uptime, bc, uname, host, id, bash, df, 

Installation
------------

download

~~~
git clone https://github.com/rtulke/dynmotd.git
cd dynmotd
~~~

rename files

~~~~
mv addlog.sh /usr/local/bin/addlog
mv rmlog.sh /usr/local/bin/rmlog
mv listlog.sh /usr/local/bin/listlog
mv dynmotd.sh /usr/local/bin/dynmotd
~~~~

change permissions

~~~~
chmod 700 /usr/local/bin/addlog
chmod 700 /usr/local/bin/rmlog
chmod 700 /usr/local/bin/listlog
chmod 777 /usr/local/bin/dynmotd
~~~


**enabled dynmotd to display all informations after user login (only root)**

~~~
echo "/usr/local/bin/dynmotd" > /etc/profile.d/motd.sh
~~~


Usage
-----

Commands 
--------
* addlog, add a new log entry into the .maintenance file
* rmlog, delete a specific line in .maintenance 
* listlog, list all .maintenance log entries
