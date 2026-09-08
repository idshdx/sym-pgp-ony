---
name: connect-ssh
description: Connect from the local machine to the Oracle VPS Ubuntu server via SSH using the project key.
---

# Connect to Oracle VPS

Use this skill when you need to SSH into the production Oracle VPS.

## Commands

### Bash / Linux / macOS
```bash
ssh -i ~/.ssh/ssh-key-oracle.key ubuntu@129.159.7.42
```

### Windows PowerShell
```powershell
ssh -i "$HOME\.ssh\ssh-key-oracle.key" ubuntu@129.159.7.42
```

### Non-Interactive / Batch Mode
To run one-off remote commands without interactive prompts:
```bash
ssh -i ~/.ssh/ssh-key-oracle.key -o StrictHostKeyChecking=accept-new -o BatchMode=yes ubuntu@129.159.7.42 "<command>"
```

## Quick Health Checks

```bash
# Check Docker container status
ssh -i ~/.ssh/ssh-key-oracle.key ubuntu@129.159.7.42 "cd /opt/lockpost && docker compose -f docker-compose.prod.yml ps"

# Check HTTP endpoints
ssh -i ~/.ssh/ssh-key-oracle.key ubuntu@129.159.7.42 "curl -sI http://127.0.0.1:80/ | head -5"
```

## File Transfer (SCP)

```bash
# Upload a file to the VPS
scp -i ~/.ssh/ssh-key-oracle.key <local-path> ubuntu@129.159.7.42:/opt/lockpost/<remote-path>

# Download a file from the VPS
scp -i ~/.ssh/ssh-key-oracle.key ubuntu@129.159.7.42:/opt/lockpost/<remote-path> <local-path>
```

## Notes

- The key file is `ssh-key-oracle.key` (not the `.pub` file).
- The remote user is `ubuntu`.
- The production app code is located at `/opt/lockpost`.
- Key files on the host are at `/opt/lockpost/config/pgp/` and are owned by `www-data` with mode `700`.

