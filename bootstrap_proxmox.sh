#!/usr/bin/env bash
# =============================================================================
#  bootstrap_proxmox.sh
#  Run this DIRECTLY on your Proxmox host to create all 3 LXC containers
#  and prepare them for Ansible (SSH + Python3 ready to go).
#
#  Usage:
#    chmod +x bootstrap_proxmox.sh
#    ./bootstrap_proxmox.sh
#
#  Download Ubuntu 22.04 template first (if not already):
#    pveam update
#    pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst
# =============================================================================

set -euo pipefail

# =============================================================================
#  ╔══════════════════════════════════════════════════════════════════════╗
#  ║  EDIT THIS SECTION TO MATCH YOUR ENVIRONMENT                        ║
#  ╚══════════════════════════════════════════════════════════════════════╝
# =============================================================================

# ── Proxmox storage and network ───────────────────────────────────────────────
STORAGE="local-lvm"       # Proxmox storage pool for CT disks
TEMPLATE_STORAGE="local"  # Where the LXC template is stored
BRIDGE="vmbr0"            # Proxmox network bridge

# ── Your network ──────────────────────────────────────────────────────────────
GATEWAY="192.168.1.1"     # ← Your LAN gateway
DNS="8.8.8.8"             # ← Your DNS server

# ── Container IPs — set to any free addresses in your subnet ─────────────────
PROMETHEUS_IP="192.168.1.10"   # ← Pick a free IP for Prometheus
GRAFANA_IP="192.168.1.11"      # ← Pick a free IP for Grafana
ZABBIX_IP="192.168.1.12"       # ← Pick a free IP for Zabbix

# ── Container IDs — must be unique in your Proxmox cluster ───────────────────
PROMETHEUS_CT_ID=200
GRAFANA_CT_ID=201
ZABBIX_CT_ID=202

# ── Root password for all containers ─────────────────────────────────────────
CT_PASSWORD="ChangeMe123!"     # ← CHANGE THIS

# ── Your SSH public key (injected into containers for Ansible access) ─────────
SSH_PUBKEY="$HOME/.ssh/id_rsa.pub"   # ← Path to your public key

# =============================================================================
#  END OF CONFIGURATION — do not edit below this line
# =============================================================================

# Build container list from the variables above
CONTAINERS=(
  "${PROMETHEUS_CT_ID}:prometheus:${PROMETHEUS_IP}:4096:40:2"
  "${GRAFANA_CT_ID}:grafana:${GRAFANA_IP}:2048:10:2"
  "${ZABBIX_CT_ID}:zabbix:${ZABBIX_IP}:4096:30:2"
)

# ── Detect Ubuntu 22.04 template ──────────────────────────────────────────────
TEMPLATE=$(pveam list ${TEMPLATE_STORAGE} | grep "ubuntu-22.04" | tail -1 | awk '{print $1}')
if [[ -z "${TEMPLATE}" ]]; then
  echo "ERROR: Ubuntu 22.04 template not found in ${TEMPLATE_STORAGE}."
  echo "Run: pveam update && pveam download ${TEMPLATE_STORAGE} ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  exit 1
fi
echo "✔ Template : ${TEMPLATE}"
echo "✔ Network  : gateway=${GATEWAY} dns=${DNS}"
echo "✔ VMs      : prometheus=${PROMETHEUS_IP} grafana=${GRAFANA_IP} zabbix=${ZABBIX_IP}"
echo ""

# ── Create and bootstrap each container ───────────────────────────────────────
for CT_DEF in "${CONTAINERS[@]}"; do
  IFS=':' read -r CT_ID HOSTNAME IP RAM DISK CORES <<< "${CT_DEF}"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " CT ${CT_ID} — ${HOSTNAME} — ${IP}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if pct status "${CT_ID}" &>/dev/null; then
    echo "  ⚠  CT ${CT_ID} already exists — skipping creation"
  else
    pct create "${CT_ID}" "${TEMPLATE}" \
      --hostname  "${HOSTNAME}" \
      --memory    "${RAM}" \
      --swap      512 \
      --cores     "${CORES}" \
      --rootfs    "${STORAGE}:${DISK}" \
      --net0      "name=eth0,bridge=${BRIDGE},ip=${IP}/24,gw=${GATEWAY}" \
      --nameserver "${DNS}" \
      --searchdomain "local" \
      --unprivileged 1 \
      --features  "nesting=1" \
      --ostype    ubuntu \
      --password  "${CT_PASSWORD}" \
      --start     0
    echo "  ✔ Created"
  fi

  # Start if not running
  if [[ "$(pct status "${CT_ID}" | awk '{print $2}')" != "running" ]]; then
    echo "  ▶ Starting..."
    pct start "${CT_ID}"
    sleep 8
  fi

  # Bootstrap: OpenSSH + Python3 + sudo
  echo "  🔧 Installing OpenSSH + Python3..."
  pct exec "${CT_ID}" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq openssh-server python3 python3-pip sudo 2>/dev/null
    systemctl enable ssh --quiet
    systemctl start ssh
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    systemctl restart ssh
  " 2>&1 | sed "s/^/    /"

  # Inject SSH public key
  if [[ -f "${SSH_PUBKEY}" ]]; then
    PUBKEY_CONTENT=$(cat "${SSH_PUBKEY}")
    pct exec "${CT_ID}" -- bash -c "
      mkdir -p /root/.ssh
      chmod 700 /root/.ssh
      echo '${PUBKEY_CONTENT}' >> /root/.ssh/authorized_keys
      chmod 600 /root/.ssh/authorized_keys
    "
    echo "  ✔ SSH public key injected"
  else
    echo "  ⚠  SSH key not found at ${SSH_PUBKEY} — using password auth"
  fi

  echo "  ✔ CT ${CT_ID} (${HOSTNAME}) ready at ${IP}"
  echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " All containers are running!"
echo ""
printf "   %-12s %-20s %s\n" "Service" "Hostname" "IP"
printf "   %-12s %-20s %s\n" "-------" "--------" "--"
printf "   %-12s %-20s %s\n" "Prometheus" "prometheus" "${PROMETHEUS_IP}"
printf "   %-12s %-20s %s\n" "Grafana" "grafana" "${GRAFANA_IP}"
printf "   %-12s %-20s %s\n" "Zabbix" "zabbix" "${ZABBIX_IP}"
echo ""
echo " Next steps — on your Ansible control machine:"
echo ""
echo "   # 1. Update inventory/hosts.yml with these IPs:"
echo "   #    prometheus-vm: ansible_host: ${PROMETHEUS_IP}"
echo "   #    grafana-vm:    ansible_host: ${GRAFANA_IP}"
echo "   #    zabbix-vm:     ansible_host: ${ZABBIX_IP}"
echo ""
echo "   # 2. Copy your SSH key (if not already injected above):"
echo "   ssh-copy-id root@${PROMETHEUS_IP}"
echo "   ssh-copy-id root@${GRAFANA_IP}"
echo "   ssh-copy-id root@${ZABBIX_IP}"
echo ""
echo "   # 3. Test connectivity:"
echo "   ansible all -m ping"
echo ""
echo "   # 4. Deploy:"
echo "   make deploy"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
