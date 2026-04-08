# =============================================================================
#  Makefile — Monitoring Stack shortcuts
#  Usage: make <target>
# =============================================================================

.PHONY: help deploy check ping bootstrap prometheus grafana zabbix \
        agents node-exporter zabbix-agent upgrade health lint clean facts

ANSIBLE_OPTS ?=

help:   ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

ping:   ## Test SSH connectivity to all hosts
	ansible all -m ping

facts:   ## Show IP addresses of all hosts
	ansible all -m setup -a "filter=ansible_default_ipv4"

deploy:   ## Deploy the complete monitoring stack
	ansible-playbook playbooks/site.yml $(ANSIBLE_OPTS)

check:   ## Dry-run — show what would change without applying
	ansible-playbook playbooks/site.yml --check --diff $(ANSIBLE_OPTS)

prometheus:   ## Deploy Prometheus + Alertmanager only
	ansible-playbook playbooks/prometheus.yml $(ANSIBLE_OPTS)

grafana:   ## Deploy Grafana only
	ansible-playbook playbooks/grafana.yml $(ANSIBLE_OPTS)

zabbix:   ## Deploy Zabbix (MySQL + server + frontend) only
	ansible-playbook playbooks/zabbix.yml $(ANSIBLE_OPTS)

agents:   ## Deploy agents (node_exporter + zabbix_agent2) to all monitored hosts
	ansible-playbook playbooks/agents.yml $(ANSIBLE_OPTS)

node-exporter:   ## Deploy Node Exporter only
	ansible-playbook playbooks/agents.yml --tags node_exporter $(ANSIBLE_OPTS)

zabbix-agent:   ## Deploy Zabbix Agent2 only
	ansible-playbook playbooks/agents.yml --tags zabbix_agent $(ANSIBLE_OPTS)

upgrade:   ## Upgrade all services to pinned versions
	ansible-playbook playbooks/upgrade.yml $(ANSIBLE_OPTS)

health:   ## Run full health check across all services
	ansible-playbook playbooks/health_check.yml -v $(ANSIBLE_OPTS)

lint:   ## Lint all playbooks
	ansible-lint playbooks/site.yml

clean:   ## Remove downloaded temp files from remote hosts
	ansible all -m shell -b -a "rm -f /tmp/prometheus*.tar.gz /tmp/node_exporter*.tar.gz /tmp/alertmanager*.tar.gz /tmp/zabbix-release.deb /tmp/mysql-apt-config.deb"
