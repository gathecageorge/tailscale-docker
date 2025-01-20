#!/bin/sh

# Unset the proxy environment variables 
unset http_proxy 
unset https_proxy 
unset all_proxy

# latest repo
echo "http://dl-cdn.alpinelinux.org/alpine/edge/main" > /etc/apk/repositories
echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

# setup ssl certs
update-ca-certificates

# Install firefox
apk add firefox

# Install tailscale
apk add tailscale
tailscaled --state=mem: --tun=userspace-networking --socks5-server=localhost:1056 --outbound-http-proxy-listen=localhost:1055 &
tailscale up --auth-key=$TAILSCALE_AUTH_KEY --hostname=$(hostname)

# Configure redsocks (optional, for non-proxy-aware apps)
apk add redsocks
if [ ! -f /etc/redsocks.conf ]; then
  echo "Configuring redsocks..."
  cat <<EOL > /etc/redsocks.conf
base {
    log_debug = on;
    log_info = on;
    daemon = on;
    redirector = iptables;
}
redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;
    ip = 127.0.0.1;
    port = 1056;
    type = socks5;
}
EOL
fi
redsocks -c /etc/redsocks.conf &
