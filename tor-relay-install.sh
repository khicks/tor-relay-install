#!/bin/bash

# A bash script to automatically install and configure a Tor relay.
# By Kevin Hicks with help from an existing script by micahflee.

echo
echo "Welcome to the Tor Relay Automatic Installer!"
echo

# check root
if [[ $EUID -ne 0 ]]; then
  echo "Error: You must be root to run this script." 1>&2
  exit 1
fi

# create working directory
if [[ ! -e "$PWD/tor-relay" ]]; then
  mkdir "$PWD/tor-relay"
elif [[ ! -d tor-relay ]]; then
  echo "Error: tor-relay already exists as a file. Please delete it and try again" 1>&2
  exit 2
fi

# prompt nickname
NICKNAME=" "
until ! [[ "$NICKNAME" =~ [^0-9a-zA-Z] ]]; do
  read -e -p "Please enter a nickname for your node (alphanumeric) [MyTorRelay]: " NICKNAME
  if [ -z "$NICKNAME" ]; then
    NICKNAME="MyTorRelay"
  fi
  echo
done

# prompt contact info
read -e -p "Please enter your node's contact info [Anonymous]: " CONTACT
if [ -z "$CONTACT" ]; then
  CONTACT="Anonymous"
fi
echo

# prompt for ports 443 and 80
echo -e "Tor defaults to running relays with ORPort 9001 and DirPort 9030,\nbut it is commonly prefered that relays be run on ports 443 and 80, respectively.\nYou should only do this if you are not running anything else on those ports."
read -e -p "Would you like to run your relay on ports 443 and 80? [y/N]: " -r

if [[ $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
  ORPort=443
  DirPort=80
else
  ORPort=9001
  DirPort=9030
fi
echo

# prompt for address to listen on
ADDRESSES=(`ifconfig | awk '/inet addr/{print substr($2,6)}'`);
if [[ ${#ADDRESSES[@]} -eq 0 ]]; then
  echo "Error: You have no active network interfaces." 1>&2
  exit 3
fi

REPLY=""
until [[ "$REPLY" =~ ^[0-9]+$ ]] && [ "$REPLY" -ge 1 -a "$REPLY" -le ${#ADDRESSES[@]} ]; do
  echo "You have ${#ADDRESSES[@]} active interface(s) that you can use for your relay:"
  for i in `seq 2 ${#ADDRESSES[@]}`; do
    echo "  $i) ${ADDRESSES[i-1]}"
  done
  read -e -p "Which one would you like for your relay to listen on?: " -r
  echo
done
ADDRESS=${ADDRESSES["$REPLY"-1]}

# confirm settings
echo "Almost done! Please review your settings:"
echo "  Nickname:    $NICKNAME"
echo "  ContactInfo: $CONTACT"
echo "  Listen addr: $ADDRESS"
echo "  ORPort:      $ORPort"
echo "  DirPort:     $DirPort"
if [[ $ORPort -eq 443 ]]; then
  echo "  A firewall rule will be added to redirect ports 443 and 80 to 9001 and 9030."
fi
read -e -p "Would you like to continue? [y/N]: " -r

if [[ ! $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
  echo -e "Cancelled by user.\n"
  exit 4
fi
echo

# add repository
if ! grep -q "http://deb.torproject.org/torproject.org" /etc/apt/sources.list; then
  echo "Adding Tor repository..."
  echo -e "\n#Official Tor repositories" >> /etc/apt/sources.list
  echo "deb http://deb.torproject.org/torproject.org `lsb_release -cs` main" >> /etc/apt/sources.list
  echo "deb-src http://deb.torproject.org/torproject.org `lsb_release -cs` main" >> /etc/apt/sources.list
  gpg -q --keyserver keys.gnupg.net --recv A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 &> /dev/null
  gpg -q --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add - > /dev/null
fi

# update apt
echo "Updating system repositories..."
apt-get update > /dev/null

# install tor
echo "Installing Tor..."
apt-get install -y debconf-utils > /dev/null
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections > /dev/null
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections > /dev/null
apt-get install -y tor deb.torproject.org-keyring iptables iptables-persistent &> /dev/null
service tor stop

# configure tor
echo "Configuring Tor..."
echo "## Automatically generated Tor configuration" > $PWD/tor-relay/torrc
echo "RunAsDaemon 1" >> $PWD/tor-relay/torrc
echo "DataDirectory /var/lib/tor" >> $PWD/tor-relay/torrc
echo "SocksPolicy reject *" >> $PWD/tor-relay/torrc
echo >> $PWD/tor-relay/torrc
echo "Nickname $NICKNAME" >> $PWD/tor-relay/torrc
echo "ContactInfo $CONTACT" >> $PWD/tor-relay/torrc
echo >> $PWD/tor-relay/torrc
echo "RelayBandwidthRate 100 MBytes" >> $PWD/tor-relay/torrc
echo "RelayBandwidthBurst 200 MBytes" >> $PWD/tor-relay/torrc
echo >> $PWD/tor-relay/torrc

if [[ $ORPort -eq 443 ]]; then
  echo "ORPort 443 NoListen" >> $PWD/tor-relay/torrc
  echo "ORPort $ADDRESS:9001 NoAdvertise" >> $PWD/tor-relay/torrc
  echo "DirPort 80 NoListen" >> $PWD/tor-relay/torrc
  echo "DirPort $ADDRESS:9030 NoAdvertise" >> $PWD/tor-relay/torrc
else
  echo "ORPort $ADDRESS:9001" >> $PWD/tor-relay/torrc
  echo "DirPort $ADDRESS:9030" >> $PWD/tor-relay/torrc
fi
echo >> $PWD/tor-relay/torrc

echo "# If you would like to configure an exit relay, you may do so here" >> $PWD/tor-relay/torrc
echo "ExitPolicy reject *:*" >> $PWD/tor-relay/torrc
echo >> $PWD/tor-relay/torrc

echo "# If you would like to display a webpage at your DirPort, you may specify one here" >> $PWD/tor-relay/torrc
echo "#DirPortFrontPage /etc/tor/dir-port-notice.html" >> $PWD/tor-relay/torrc
echo >> $PWD/tor-relay/torrc

echo "# If you are running multiple relays, you should specify their fingerprints here" >> $PWD/tor-relay/torrc
echo -e "#MyFamily \$keyid1, \$keyid2, \$keyid3..." >> $PWD/tor-relay/torrc
echo >> $PWD/tor-relay/torrc


# configure iptables
echo "Configuring firewall rules..."
if ! iptables-save | grep -q -- "--dport $ORPort -j ACCEPT"; then
  iptables -A INPUT -p tcp --dport $ORPort -j ACCEPT
fi
if ! iptables-save | grep -q -- "--dport $DirPort -j ACCEPT"; then
  iptables -A INPUT -p tcp --dport $DirPort -j ACCEPT
fi

if [[ $ORPort -eq 443 ]]; then
  if ! iptables-save | grep -q -- "--dport 443 -j DNAT"; then
    iptables -t nat -A PREROUTING -p tcp -d $ADDRESS --dport 443 -j DNAT --to-destination $ADDRESS:9001
  fi
  if ! iptables-save | grep -q -- "--dport 80 -j DNAT"; then
    iptables -t nat -A PREROUTING -p tcp -d $ADDRESS --dport 80 -j DNAT --to-destination $ADDRESS:9030
  fi
  iptables-save > $PWD/tor-relay/rules.v4
fi

# apply
echo "Applying settings..."
mv /etc/tor/torrc /etc/tor/torrc.bak
cp $PWD/tor-relay/torrc /etc/tor/torrc
if [[ $ORPort -eq 443 ]]; then
  cp $PWD/tor-relay/rules.v4 /etc/iptables/rules.v4
fi

service tor start

echo -e "\nDone!\nYou may want to check the /var/log/tor/log file to make sure it's working.\n"

