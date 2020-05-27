#!/bin/bash

# Color code
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log_info() {
    echo -e "INFO - $1"
}

log_error() {
    echo -e "${RED}ERROR${NC} - $1"
}

wait_key(){
    local file="$1"; shift
    local wait_seconds="${1:-120}"; shift # 120 seconds as default timeout

    until test $((wait_seconds--)) -eq 0 -o -f "$file" ; do log_info "waiting for key created..."; sleep 5; done
    ((++wait_seconds))
}

destroy_ovpn(){
    docker rm -f -v openvpn
    rm -rf /etc/openvpn
    log_info "OpenVPN server destroyed..."
}

# Install Docker
log_info "Installing Docker..."
apt-get update -qq
apt-get install -qqy \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common
curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/debian \
   $(lsb_release -cs) \
   stable"
apt-get update -qq && apt-get install -qqy docker-ce docker-ce-cli containerd.io

# Check Docker status
docker ps > /dev/null
result=$?
if [ "$result" != "0" ]; then
    log_error "Docker not started properly, exiting..."
    exit 1
else
    log_info "Docker installed..."
fi

# Running openvpn server
log_info "Starting openvpn server..."
if [ "$(docker ps -a | grep openvpn)" ]; then
    log_info "OpenVPN server found on server..."
    read < /dev/tty -p "Do you wish to re-create the OVPN server? (It would generate a new config!)" yn
    case $yn in
        [Yy]* ) destroy_ovpn;;
        [Nn]* ) log_error "Action aborted..."; exit 1;;
        * ) log_error "Please answer yes or no."; exit 1;;
    esac
fi

mkdir -p /etc/openvpn
externalip=$(curl -s http://whatismyip.akamai.com/)
docker run \
           --name openvpn \
           --volume /etc/openvpn:/etc/openvpn \
           --detach=true \
           -p 1194:1194/udp \
           -e "OVPN_SERVER_CN=${externalip}" \
           -e "USE_CLIENT_CERTIFICATE=true" \
           --cap-add=NET_ADMIN \
           wheelybird/openvpn-ldap-otp

wait_key "/etc/openvpn/pki/private/$externalip.key"
if [ ! -f /etc/openvpn/pki/private/$externalip.key ]; then
    log_error "Key file not exist, exiting..."
fi

# Grepping the config
templog="/tmp/openvpn.log"
rm -rf $templog
docker logs openvpn > $templog 2>&1

sline=$(grep -n "Client config" $templog | head -1 | cut -d: -f1 | awk '{print $1+2}')
eline=$(grep -n "Running NSCLD" $templog | head -1 | cut -d: -f1 | awk '{print $1-2}')
linediff="$((eline-sline))"
ovpn_name=$(echo $externalip | sed 's/\./-/g')
tail -n "+$sline" $templog | head -n "$(($eline-$sline+1))" > /tmp/$ovpn_name.ovpn

log_info "Please download the file located at ${GREEN}/tmp/$ovpn_name.ovpn${NC}"

log_info "${GREEN}DONE${NC}"