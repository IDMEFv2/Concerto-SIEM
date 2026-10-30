#!/bin/sh

EXPOSITIONS="
80:30080
443:30443
4690:30790
9092:30092
9301:30301
"

INTERFACE_EXT="ens3"

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run with root privileges (sudo)"
    exit 1
fi

echo "Retrieving the Minikube container IP..."
MINIKUBE_IP=$(podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' minikube 2>/dev/null)

if [ -z "$MINIKUBE_IP" ]; then
    echo "Error: Could not find the Minikube IP. Is the cluster running?"
    exit 1
fi

echo "-> Minikube IP detected : $MINIKUBE_IP"

echo "Applying iptables redirection rules..."

sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

for couple in $EXPOSITIONS; do
    EXT_PORT=$(echo "$couple" | cut -d':' -f1)
    NODE_PORT=$(echo "$couple" | cut -d':' -f2)

    echo "-> Redirecting external port $EXT_PORT to Minikube NodePort $NODE_PORT..."

    IFACE_OPT=""
    if [ -n "$INTERFACE_EXT" ]; then
        IFACE_OPT="-i $INTERFACE_EXT"
    fi

    if ! iptables -t nat -C PREROUTING $IFACE_OPT -p tcp --dport "$EXT_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$NODE_PORT" 2>/dev/null; then
        iptables -t nat -A PREROUTING $IFACE_OPT -p tcp --dport "$EXT_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$NODE_PORT"
    fi
    
    if ! iptables -C FORWARD -p tcp -d "$MINIKUBE_IP" --dport "$NODE_PORT" -j ACCEPT 2>/dev/null; then
        iptables -A FORWARD -p tcp -d "$MINIKUBE_IP" --dport "$NODE_PORT" -j ACCEPT
    fi

done

echo "Done! Redirections are in place."
