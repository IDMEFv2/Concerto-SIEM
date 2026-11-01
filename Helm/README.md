# ConcertoSIEM Helm Chart

This repository contains the Helm chart for deploying **ConcertoSIEM** on a Kubernetes environment (specifically using Minikube).

---

## Prerequisites

Before deploying the Helm chart, ensure you have the following installed on your host system:

* [Minikube](https://minikube.sigs.k8s.io/docs/start/)
* [Podman](https://podman.io/)
* [Helm (v3+)](https://helm.sh/docs/intro/install/)
* `sudo` privileges to execute the firewall script

---

## Deployment Steps

Follow the instructions below in sequence to ensure a proper deployment.

### Step 1: Start Minikube

Initialize Minikube using the `podman` driver with the required CPU, memory, and volume mount parameters:

```bash
minikube start \
  --driver=podman \
  --mount-string /home/ubuntu/Minikube_ConcertoSIEM:/mnt \
  --cpus=8 \
  --memory=22000
```

> **Note:** Adjust `/home/ubuntu/Minikube_ConcertoSIEM` if your local host directory differs.

---

### Step 2: Configure and Run the Firewall Script

Before installing the Helm release, you need to configure network redirection for your external interface.

1. Open `firewall.sh` in a text editor and update the **external interface** variable (`EXTERNAL_IF` or similar) to match your host system's network interface (e.g., `eth0`, `ens33`, etc.).
2. Execute the script with `sudo`:

```bash
sudo sh firewall.sh
```

---

### Step 3: Deploy or Upgrade ConcertoSIEM

Once Minikube is active and the firewall rules are applied, deploy or update the `concerto-siem` Helm release:

#### First-time Installation:
```bash
helm install concerto-siem .
```

#### Upgrade Existing Installation:
```bash
helm upgrade concerto-siem .
```

---

## Management Commands

* **Check release status:**
  ```bash
  helm status concerto-siem
  ```

* **View deployed pods:**
  ```bash
  kubectl get pods
  ```

* **Uninstall release:**
  ```bash
  helm uninstall concerto-siem
  ```
