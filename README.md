Tor Relay Automatic Installer

This simple bash script will automatically install and configure a Tor relay.

This script was made for and has only been tested on Ubuntu!

This script will:

* Add the official Tor repository to your apt sources
* Install tor, deb.torproject.org-keyring, iptables, and iptables-persistent
* Write the config to your personal tor-relay/ directory and copy it to /etc/tor/torrc
* Add firewall rules to allow traffic to and, if needed, forward the correct ports to the Tor service.

To run, simply do:
        $ chmod +x tor-relay-install.sh
        $ sudo ./tor-relay-install.sh

Recommended post-installation steps:

* Upgrade the rest of your software packages with apt-get upgrade
* Check the /etc/tor/torrc config file and make sure that it is to your liking.
* Install fail2ban to protect your SSH server.
* Reboot the server.
