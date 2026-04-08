# Monitoring Stack — Ansible Deployment

Production-grade monitoring stack across **3 dedicated VMs** on Proxmox,
built from zero on bare Ubuntu 22.04. No pre-installed software required.

## Stack

| Service | VM | Port | Version |
|---|---|---|---|
| **Prometheus** | prometheus-vm | 9090 | 3.8.0 |
| **Alertmanager** | prometheus-vm | 9093 | 0.27.0 |
| **Grafana** | grafana-vm | 3000 | 12.4.1 |
| **Zabbix Server** | zabbix-vm | 10051 | 7.4 |
| **Zabbix Frontend** | zabbix-vm | 8080 | 7.4 |
| **MySQL** | zabbix-vm | 3306 | 8.0 |
| **Node Exporter** | all hosts | 9100 | 1.10.2 |
| **Zabbix Agent2** | all hosts | 10050 | 7.4 |

---

## ╔══════════════════════════════════════════════════════════╗
## ║  TO DEPLOY IN A NEW LOCATION — EDIT ONLY ONE FILE       ║
## ║  inventory/hosts.yml                                     ║
## ╚══════════════════════════════════════════════════════════╝

Open `inventory/hosts.yml` and change:
1. `ansible_host` for each VM to free IPs in your subnet
2. `internal_network` to your LAN subnet
3. `ansible_user` to your SSH user

**That's it.** Every other file — datasource URLs, scrape targets,
/etc/hosts entries, firewall rules — all update automatically.

---

## Step 1 — Create VMs on Proxmox

Edit the top section of `bootstrap_proxmox.sh` (only the CONFIGURATION block):

```bash
GATEWAY="192.168.1.1"        # Your LAN gateway
DNS="8.8.8.8"                # Your DNS

PROMETHEUS_IP="192.168.1.10" # Free IP for Prometheus VM
GRAFANA_IP="192.168.1.11"    # Free IP for Grafana VM
ZABBIX_IP="192.168.1.12"     # Free IP for Zabbix VM

CT_PASSWORD="ChangeMe123!"   # Root password for containers
SSH_PUBKEY="~/.ssh/id_rsa.pub"
```

Then run it **on your Proxmox host**:
```bash
chmod +x bootstrap_proxmox.sh
./bootstrap_proxmox.sh
```

---

## Step 2 — Update inventory

Edit `inventory/hosts.yml`:

```yaml
all:
  vars:
    ansible_user: ubuntu             # ← your SSH user
    internal_network: "192.168.1.0/24"  # ← your subnet

  children:
    prometheus:
      hosts:
        prometheus-vm:
          ansible_host: 192.168.1.10   # ← your Prometheus IP

    grafana:
      hosts:
        grafana-vm:
          ansible_host: 192.168.1.11   # ← your Grafana IP

    zabbix:
      hosts:
        zabbix-vm:
          ansible_host: 192.168.1.12   # ← your Zabbix IP

    app_servers:
      hosts:
        app-server-01:
          ansible_host: 192.168.1.20   # ← servers you want to monitor
```

**Nothing else needs to change.** Prometheus scrape targets, Grafana
datasource URLs, /etc/hosts, and firewall rules all read from these IPs.

---

## Step 3 — Set passwords

Edit `group_vars/zabbix.yml`:
```yaml
mysql_root_password: "your_strong_root_password"
zabbix_db_password:  "your_strong_db_password"
```

Edit `group_vars/grafana.yml`:
```yaml
grafana_admin_password: "your_strong_grafana_password"
```

---

## Step 4 — Test SSH and deploy

```bash
# Test connectivity
ansible all -m ping

# Dry run (no changes)
make check

# Full deployment
make deploy
```

---

## Access the stack

After deployment, URLs are printed automatically by `make health`.

| Service | URL | Default credentials |
|---|---|---|
| **Grafana** | `http://<grafana-ip>:3000` | `admin` / your password |
| **Prometheus** | `http://<prometheus-ip>:9090` | no auth |
| **Alertmanager** | `http://<prometheus-ip>:9093` | no auth |
| **Zabbix** | `http://<zabbix-ip>:8080` | `Admin` / `zabbix` |

Grafana comes up with **Prometheus and Zabbix already connected** as
datasources — no manual configuration needed.

---

## Adding a new server to monitor

1. Add it to `inventory/hosts.yml` under `app_servers`
2. Run: `make agents` or `ansible-playbook playbooks/agents.yml --limit <hostname>`
3. Prometheus picks it up automatically within one scrape interval (15s)
4. In Zabbix UI: `Configuration → Hosts → Create host` with the agent IP

---

## Make targets

```
make deploy         Full stack deployment
make check          Dry-run (no changes applied)
make ping           Test SSH to all hosts
make agents         Deploy agents to all monitored hosts
make node-exporter  Node Exporter only
make zabbix-agent   Zabbix Agent2 only
make prometheus     Prometheus + Alertmanager only
make grafana        Grafana only
make zabbix         Zabbix (MySQL + server + frontend) only
make upgrade        Upgrade all services
make health         Full health check across all services
make clean          Remove temp files from remote hosts
```

---

## Redeploying to a different subnet (e.g. 10.0.0.0/24)

```bash
# 1. Edit ONLY inventory/hosts.yml:
#    - Change internal_network to "10.0.0.0/24"
#    - Change all ansible_host values to IPs in 10.0.0.x

# 2. Run bootstrap_proxmox.sh with the new IPs

# 3. Deploy:
make deploy
```

No other files need to be touched.

---

## Security

- All passwords live in `group_vars/` — encrypt for production:
  ```bash
  ansible-vault encrypt group_vars/zabbix.yml group_vars/grafana.yml
  ansible-playbook playbooks/site.yml --ask-vault-pass
  ```
- UFW on every VM: default deny, only required ports open
- All binaries run as dedicated non-root system users
- Systemd units have `NoNewPrivileges`, `ProtectSystem`, `PrivateTmp`

---

## Troubleshoot

```bash
# Service status
systemctl status prometheus alertmanager          # prometheus-vm
systemctl status grafana-server                   # grafana-vm
systemctl status mysql zabbix-server nginx        # zabbix-vm

# Logs
journalctl -u prometheus -f
journalctl -u grafana-server -f
journalctl -u zabbix-server -f

# Validate Prometheus config
promtool check config /etc/prometheus/prometheus.yml

# Check MySQL
mysql -u zabbix -p -e "SELECT COUNT(*) FROM zabbix.hosts;"

# Full health check
make health
```
