# dynmotd
Dynamic Motd (Message of the Day) a Script to print out all system specific informations



# installation
git clone 
mv addlog.sh /usr/local/bin/addlog
mv rmlog.sh /usr/local/bin/rmlog
mv listlog.sh /usr/local/bin/listlog
mv dynmotd.sh /usr/local/bin/dynmotd

chmod 700 /usr/local/bin/addlog
chmod 700 /usr/local/bin/rmlog
chmod 700 /usr/local/bin/listlog
chmod 777 /usr/local/bin/dynmotd

echo "/usr/local/bin/dynmotd" > /etc/profile.d/motd.sh

