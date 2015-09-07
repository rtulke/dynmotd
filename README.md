# dynmotd
Dynamic Motd (Message of the Day) a Script to print out all system specific informations



# installation
<code><pre>
git clone https://github.com/rtulke/dynmotd.git
cd dynmotd
mv addlog.sh /usr/local/bin/addlog
mv rmlog.sh /usr/local/bin/rmlog
mv listlog.sh /usr/local/bin/listlog
mv dynmotd.sh /usr/local/bin/dynmotd
</pre></code>

<code><pre>
chmod 700 /usr/local/bin/addlog
chmod 700 /usr/local/bin/rmlog
chmod 700 /usr/local/bin/listlog
chmod 777 /usr/local/bin/dynmotd
</pre></code>

# enabled dynmotd to display all informations after user login (only root)
<code>
echo "/usr/local/bin/dynmotd" > /etc/profile.d/motd.sh
</code>

# Commands 
* addlog, add a new log entry into the .maintenance file
* rmlog, delete a specific line in .maintenance 
* listlog, list all .maintenance log entries
