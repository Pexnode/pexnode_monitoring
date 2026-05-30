# Auto-Enrollment Guide

## Overview

New servers can automatically enroll in monitoring without manual intervention.

## For New Game Node Servers

During your Pterodactyl provisioning workflow, include:

### Option 1: Cloud-Init (Recommended)

Add to your cloud-init script:

```bash
#!/bin/bash
# Set monitoring credentials (from secure source)
export NETDATA_CLAIM_TOKEN="<your-token>"
export NETDATA_CLAIM_URL="https://app.netdata.cloud"

# Run auto-enrollment
curl -s https://raw.githubusercontent.com/your-org/pexnode_monitoring/main/scripts/auto-enroll-onboot.sh | bash
```

### Option 2: Ansible Playbook

Add to your provisioning playbook:

```yaml
- name: Setup Netdata monitoring
  hosts: all
  become: yes
  vars:
    netdata_claim_token: "{{ lookup('env', 'NETDATA_CLAIM_TOKEN') }}"
    netdata_claim_url: "https://app.netdata.cloud"
  roles:
    - role: geerlingguy.docker
    - role: netdata-child
      vars:
        netdata_claim_only: yes
        netdata_telemetry: no
```

### Option 3: Docker Image

Bake into your server image:

```dockerfile
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y curl

# Install Docker
RUN curl -fsSL https://get.docker.com | sh

# Copy enrollment script
COPY scripts/auto-enroll-onboot.sh /opt/pexnode-monitoring/
RUN chmod +x /opt/pexnode-monitoring/auto-enroll-onboot.sh

# Create systemd service
COPY systemd/pexnode-netdata-child.service /etc/systemd/system/
RUN systemctl enable pexnode-netdata-child.service

ENTRYPOINT ["/opt/pexnode-monitoring/auto-enroll-onboot.sh"]
```

## For Existing Servers

Manual enrollment:

```bash
./scripts/enroll-host.sh <host-ip> <claim-token>
```

## Verification

After server boots, verify enrollment:

```bash
# On the server
docker ps | grep netdata-child
docker logs netdata-child

# In Netdata Cloud
# Dashboard → Space Overview → Node appears within 1-2 minutes
```

## Troubleshooting Auto-Enrollment

### Service Status

```bash
systemctl status pexnode-netdata-child.service
journalctl -u pexnode-netdata-child.service -f
```

### Container Logs

```bash
docker logs netdata-child
docker logs netdata-child --tail 50
```

### Retry Manually

```bash
/opt/pexnode-monitoring/enroll-child.sh
```

### Re-enroll

```bash
docker stop netdata-child
docker rm netdata-child
/opt/pexnode-monitoring/enroll-child.sh
```
