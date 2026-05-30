# Cloud-Init Template

Copy this to your cloud infrastructure provisioning (Azure VMs, AWS EC2, etc.)

## Azure Container Instances (CLI)

```bash
az vm create \
  --resource-group pexnode-game-nodes \
  --name game-node-1 \
  --image UbuntuLTS \
  --size Standard_D4s_v3 \
  --admin-username root \
  --generate-ssh-keys \
  --custom-data provision-wings-bootstrap.sh \
  --environment \
    PANEL_URL=https://panel.pexnode.com \
    NODE_ID=2 \
    WINGS_API_KEY=ptla_xxxxx \
    NETDATA_TOKEN=abc123 \
    SSH_PORT=2222
```

## Azure Template (ARM Template)

```json
{
  "type": "Microsoft.Compute/virtualMachines",
  "apiVersion": "2021-03-01",
  "name": "game-node-1",
  "properties": {
    "osProfile": {
      "customData": "[base64(variables('cloudInitScript'))]"
    }
  }
}
```

## AWS EC2 (CLI)

```bash
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.large \
  --user-data file://provision-wings-bootstrap.sh \
  --security-group-ids sg-xxxxxxxxx \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=game-node-1}]'
```

## DigitalOcean Droplet

```bash
doctl compute droplet create game-node-1 \
  --region sfo3 \
  --size s-2vcpu-2gb \
  --image ubuntu-22-04-x64 \
  --user-data-file provision-wings-bootstrap.sh
```

## Terraform (AWS Example)

```hcl
resource "aws_instance" "game_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.large"
  key_name               = aws_key_pair.deployer.key_name
  user_data              = file("provision-wings-bootstrap.sh")
  iam_instance_profile   = aws_iam_instance_profile.game_node.name
  security_groups        = [aws_security_group.game_node.name]

  tags = {
    Name = "game-node-1"
  }
}
```

## Manual Provisioning

If cloud-init isn't available:

```bash
# Download script
curl -fsSL https://raw.githubusercontent.com/your-org/pexnode_monitoring/main/scripts/provision-wings-node.sh \
  -o /tmp/provision.sh
chmod +x /tmp/provision.sh

# Run with environment variables
export PANEL_URL=https://panel.pexnode.com
export NODE_ID=2
export WINGS_API_KEY=ptla_xxxxx
export NETDATA_TOKEN=abc123
export SSH_PORT=2222

/tmp/provision.sh \
  "$PANEL_URL" \
  "$NODE_ID" \
  "$WINGS_API_KEY" \
  "$NETDATA_TOKEN" \
  "$SSH_PORT"
```

## Environment Variables Reference

| Variable | Example | Required | Notes |
|----------|---------|----------|-------|
| `PANEL_URL` | `https://panel.pexnode.com` | Yes | Pterodactyl panel |
| `NODE_ID` | `2` | Yes | Node ID in panel |
| `WINGS_API_KEY` | `ptla_xxxxx` | Yes | Application API key |
| `NETDATA_TOKEN` | `abc123def456` | No | Monitoring enrollment |
| `SSH_PORT` | `2222` | No | Default: 22 |

---

## Monitoring Provisioning

Check provisioning progress:

```bash
# SSH to host after ~30 seconds
ssh -p <SSH_PORT> root@<host-ip>

# Follow provisioning log
tail -f /var/log/pexnode-provision.log

# Check Wings status after provisioning completes
systemctl status wings
journalctl -u wings -f
```

## Scaling Script

If using Terraform or similar, use this wrapper:

```bash
#!/bin/bash
# provision-multiple-nodes.sh

for i in {1..5}; do
  NODE_ID=$((i))
  SSH_PORT=$((2222 + i))
  
  echo "Provisioning game-node-$i (NODE_ID=$NODE_ID, SSH_PORT=$SSH_PORT)"
  
  az vm create \
    --resource-group pexnode-game-nodes \
    --name game-node-$i \
    --image UbuntuLTS \
    --custom-data provision-wings-bootstrap.sh \
    --environment \
      NODE_ID=$NODE_ID \
      SSH_PORT=$SSH_PORT
done
```
