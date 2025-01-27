#!/bin/bash
apt update
apt install curl nano adduser openssh-server sudo

USERNAME="philo"
SERVER_NAME="philo-server"
PUBLIC_SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEoHlTzQPeeIiMCHaqty/FRV2aKvqPoKzazSCE73ANmN"

# Hostname
hostnamectl set-hostname $SERVER_NAME

# Add user and switch from root
adduser --disabled-password --gecos "" --home /home/$USERNAME $USERNAME
echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/$USERNAME
su $USERNAME
cd /home/$USERNAME
mkdir -p .ssh
echo "$PUBLIC_SSH_KEY" >> ~/.ssh/authorized_keys

# Disable root login
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Add tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Start tailscale
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
sudo tailscale up --advertise-exit-node --ssh

# UFW, with docker support
sudo tee -a /etc/ufw/after.rules > /dev/null << 'EOF'
# BEGIN UFW AND DOCKER
*filter
:ufw-user-forward - [0:0]
:ufw-docker-logging-deny - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j ufw-user-forward

-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16

-A DOCKER-USER -p udp -m udp --sport 53 --dport 1024:65535 -j RETURN

-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 172.16.0.0/12
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 172.16.0.0/12

-A DOCKER-USER -j RETURN

-A ufw-docker-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW DOCKER BLOCK] "
-A ufw-docker-logging-deny -j DROP

COMMIT
# END UFW AND DOCKER
EOF
sudo ufw allow from 100.64.0.0/10
sudo ufw route allow from 100.64.0.0/10
sudo ufw allow 41641/udp
sudo ufw allow 443
sudo ufw route allow 443
sudo ufw allow 80
sudo ufw route allow 80
sudo sed -i 's/^#\?IPV6.*/IPV6=no/' /etc/default/ufw
sudo ufw enable

# Docker
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Allow user to use docker
sudo usermod -aG docker $USERNAME
sudo groupadd docker
newgrp docker
