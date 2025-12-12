# NixOS Cache Builder & Server

Automated daily builds of NixOS configurations with binary cache serving via `nix-serve-ng`.

## Overview

This module enables a NixOS system to:
1. Clone your flake repository from GitHub daily
2. Update flake inputs to get the latest packages
3. Build NixOS configurations for all specified hosts
4. Sign and cache the built derivations
5. Serve them via a binary cache server (nix-serve-ng)
6. Restrict access to LAN only (192.168.0.0/16)

## Architecture

```
Daily at 02:00 AM:
  ┌─────────────────────────────────────┐
  │  1. Sync from GitHub (main branch) │
  └───────────────┬─────────────────────┘
                  ▼
  ┌─────────────────────────────────────┐
  │  2. nix flake update (latest deps) │
  └───────────────┬─────────────────────┘
                  ▼
  ┌─────────────────────────────────────┐
  │  3. Build all host configurations  │
  │     (nz, zanoza, mz, beez)         │
  └───────────────┬─────────────────────┘
                  ▼
  ┌─────────────────────────────────────┐
  │  4. Sign & cache results           │
  │     (/var/cache/nix-builds)        │
  └───────────────┬─────────────────────┘
                  ▼
  ┌─────────────────────────────────────┐
  │  5. Serve via nix-serve-ng         │
  │     (http://beez.sbulav.ru:5000)   │
  └─────────────────────────────────────┘
```

## Setup Instructions

### Step 1: Generate SSH Key for GitHub Access

On the builder machine (beez):

```bash
# Generate SSH key for root
sudo ssh-keygen -t ed25519 -C "root@beez" -f /root/.ssh/id_ed25519 -N ""

# Display public key
sudo cat /root/.ssh/id_ed25519.pub
```

Add the public key to GitHub:
1. Go to: https://github.com/sbulav/dotnix/settings/keys
2. Click "Add deploy key"
3. Title: "beez cache builder"
4. Paste the public key
5. **Do NOT check "Allow write access"** (read-only is safer)
6. Click "Add key"

Test SSH access:
```bash
sudo ssh -T git@github.com
# Expected: "Hi sbulav! You've successfully authenticated..."
```

### Step 2: Generate Cache Signing Keys

```bash
# Generate binary cache signing keys
sudo nix-store --generate-binary-cache-key \
  beez.sbulav.ru \
  /tmp/cache-priv-key.pem \
  /tmp/cache-pub-key.pem

# Display keys
echo "=== Private Key (keep secret) ==="
sudo cat /tmp/cache-priv-key.pem

echo ""
echo "=== Public Key (distribute to clients) ==="
sudo cat /tmp/cache-pub-key.pem
```

**IMPORTANT**: Save the public key output. You'll need it for client configuration.  
Example: `beez.sbulav.ru-1:AbCd1234...=`

### Step 3: Add Private Key to SOPS Secrets

```bash
# Edit secrets file with SOPS
sops secrets/beez/default.yaml
```

Add the private key content:
```yaml
nix-cache-priv-key: |
  beez.sbulav.ru-1:AbCd1234privatekey...
```

Save and exit. SOPS will encrypt the file.

**Clean up temporary keys:**
```bash
sudo rm /tmp/cache-priv-key.pem /tmp/cache-pub-key.pem
```

### Step 4: Enable Module on Builder (beez)

Edit `systems/x86_64-linux/beez/default.nix`:

```nix
{
  pkgs,
  lib,
  ...
}: {
  imports = [ ./hardware-configuration.nix ];

  suites.server.enable = true;

  # Enable NixOS cache builder and server
  custom.services.nix-cache-builder = {
    enable = true;
    hosts = [ "nz" "zanoza" "mz" "beez" ];
    cacheServer.enable = true;
  };

  # Enable SOPS for secrets management
  custom.security.sops = {
    enable = true;
    sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/beez/default.yaml";
  };

  # ... rest of config ...
}
```

### Step 5: Deploy to beez

```bash
# Build and deploy
sudo nixos-rebuild switch --flake .#beez

# Or if deploying remotely
nix run .#deploy.beez
```

### Step 6: Verify Services are Running

```bash
# Check sync service can run
sudo systemctl start nix-cache-builder-sync.service
sudo journalctl -u nix-cache-builder-sync.service -n 50

# Verify flake was cloned
ls -la /var/lib/nix-cache-builder/flake/

# Check timer is scheduled
systemctl list-timers nix-cache-builder

# Check cache server is running
systemctl status nix-serve

# Test cache server
curl http://localhost:5000/nix-cache-info
# Expected output:
# StoreDir: /nix/store
# WantMassQuery: 1
# Priority: 40
```

### Step 7: Trigger First Build Manually

The timer runs daily at 02:00, but you can trigger it manually for testing:

```bash
# Start the build (this will take 30min - 2+ hours)
sudo systemctl start nix-cache-builder.service

# Monitor progress in another terminal
sudo journalctl -fu nix-cache-builder.service
```

Verify build results:
```bash
ls -lh /var/cache/nix-builds/
# Should show: nz-result, zanoza-result, mz-result, beez-result
```

### Step 8: Configure Clients to Use Cache

On each client machine (nz, zanoza, mz), edit their system configuration:

**Example for `systems/x86_64-linux/nz/default.nix`:**

```nix
{
  pkgs,
  lib,
  ...
}: {
  imports = [ ./hardware-configuration.nix ];

  suites.common.enable = true;

  # Configure to use beez cache
  system.nix.cache-servers = [{
    url = "http://beez.sbulav.ru:5000";
    key = "beez.sbulav.ru-1:AbCd1234publickey...=";  # Paste your public key here
    priority = 40;
  }];

  # Ensure beez is in hosts file
  networking.hosts = {
    "192.168.92.194" = [ "beez" "beez.sbulav.ru" ];
    # ... other hosts ...
  };

  # ... rest of config ...
}
```

Repeat for `zanoza/default.nix` and `mz/default.nix`.

### Step 9: Deploy to Clients

```bash
# Deploy to all clients
nix run .#deploy.nz
nix run .#deploy.zanoza
nix run .#deploy.mz
```

### Step 10: Verify Cache is Working

On a client machine:

```bash
# Verify cache is configured
nix show-config | grep substituters
# Should show: http://beez.sbulav.ru:5000

# Test cache connectivity
curl http://beez.sbulav.ru:5000/nix-cache-info

# Test cache is being used (check logs during a rebuild)
sudo nixos-rebuild switch --flake .#nz
# Look for lines like: "copying path ... from 'http://beez.sbulav.ru:5000'"
```

## Configuration Options

### Builder Options

```nix
custom.services.nix-cache-builder = {
  enable = false;                                    # Enable the module
  
  flakePath = "/var/lib/nix-cache-builder/flake";   # Where to clone repo
  flakeRepo = "git@github.com:sbulav/dotnix.git";   # GitHub repo URL
  flakeBranch = "main";                              # Branch to track
  
  updateFlake = true;                                # Run nix flake update daily
  
  hosts = [ "nz" "zanoza" "mz" "beez" ];            # Hosts to build
  
  buildSchedule = "daily";                           # When to run
  buildTime = "02:00";                               # Specific time
  
  cacheDir = "/var/cache/nix-builds";               # Build output location
  maxCacheSize = 200;                                # Max size in GB (0 = unlimited)
  keepGenerations = 3;                               # Generations per host
  
  cacheServer = {
    enable = true;                                   # Enable nix-serve-ng
    port = 5000;                                     # Port to listen on
    priority = 40;                                   # Substituter priority
  };
};
```

### Client Options

```nix
system.nix.cache-servers = [
  {
    url = "http://beez.sbulav.ru:5000";
    key = "beez.sbulav.ru-1:base64key...";
    priority = 40;  # Lower number = higher priority
  }
];
```

## Monitoring & Maintenance

### Check Build Status

```bash
# View recent builds
sudo journalctl -u nix-cache-builder.service --since today

# Check when next build is scheduled
systemctl list-timers nix-cache-builder

# Check cache size
du -sh /var/cache/nix-builds/
```

### Manual Operations

```bash
# Trigger immediate build
sudo systemctl start nix-cache-builder.service

# Force sync from GitHub
sudo systemctl start nix-cache-builder-sync.service

# Re-sign store paths
sudo nix store sign --all --key-file /run/secrets/nix-cache-priv-key

# Clean old builds
sudo find /var/cache/nix-builds -name '*-result-*' -mtime +21 -delete

# Garbage collect unused paths
sudo nix-collect-garbage -d
```

### View Logs

```bash
# Follow build logs
sudo journalctl -fu nix-cache-builder.service

# View sync logs
sudo journalctl -u nix-cache-builder-sync.service -n 100

# View cache server logs
sudo journalctl -u nix-serve.service -n 50
```

## Troubleshooting

### Build Failures

**Problem**: Builds fail for specific host

**Solution**: Test build manually
```bash
cd /var/lib/nix-cache-builder/flake
nix build .#nixosConfigurations.nz.config.system.build.toplevel --show-trace
```

### Cache Not Accessible

**Problem**: Clients can't reach cache server

**Solution**: Check connectivity and firewall
```bash
# On builder (beez)
sudo systemctl status nix-serve
sudo iptables -L -n | grep 5000

# On client
curl http://beez.sbulav.ru:5000/nix-cache-info
ping beez.sbulav.ru
```

### SSH Key Issues

**Problem**: Can't clone from GitHub

**Solution**: Verify SSH key and permissions
```bash
# Test SSH
sudo ssh -T git@github.com

# Check key permissions
ls -la /root/.ssh/

# Verify key is added to GitHub
# Go to: https://github.com/sbulav/dotnix/settings/keys
```

### SOPS Decryption Fails

**Problem**: Can't decrypt nix-cache-priv-key

**Solution**: Verify SOPS setup
```bash
# Check age keys exist
ls -la /etc/ssh/ssh_host_ed25519_key

# Test decryption
sudo sops -d secrets/beez/default.yaml

# Verify secret is accessible
ls -la /run/secrets/nix-cache-priv-key
```

### Disk Space Issues

**Problem**: Cache fills up 200GB limit

**Solution**: Clean up manually or adjust settings
```bash
# Remove old builds
sudo find /var/cache/nix-builds -name '*-result*' -mtime +7 -delete

# Garbage collect
sudo nix-collect-garbage -d

# Adjust keepGenerations in config
custom.services.nix-cache-builder.keepGenerations = 2;
```

## Security Notes

### What's Protected

- ✅ **LAN-only access**: Firewall restricts cache to 192.168.0.0/16
- ✅ **SOPS-encrypted keys**: Private key stored securely
- ✅ **Signed store paths**: All builds are cryptographically signed
- ✅ **Root-only access**: Services run as root, secrets mode 0400
- ✅ **Read-only GitHub access**: Deploy key has no write permissions

### Security Recommendations

1. **Keep private key secure**: Never commit unencrypted key to git
2. **Rotate keys periodically**: Generate new signing keys every 6-12 months
3. **Monitor access logs**: Check nix-serve logs for suspicious activity
4. **Backup keys**: Keep offline backup of signing keys
5. **Use firewall**: Ensure only LAN can access port 5000

## Advanced Configuration

### Change Build Schedule

To build weekly instead of daily:

```nix
custom.services.nix-cache-builder = {
  buildSchedule = "weekly";  # Or use systemd calendar format
  buildTime = "Sun 02:00";   # Sunday at 2 AM
};
```

### Disable Flake Updates

To use committed flake.lock instead of daily updates:

```nix
custom.services.nix-cache-builder = {
  updateFlake = false;  # Won't run nix flake update
};
```

### Build Specific Hosts Only

```nix
custom.services.nix-cache-builder = {
  hosts = [ "nz" "beez" ];  # Only build these two
};
```

### Change Cache Size Limit

```nix
custom.services.nix-cache-builder = {
  maxCacheSize = 500;  # 500 GB limit
  # OR
  maxCacheSize = 0;    # Unlimited
};
```

## Performance Tips

1. **Build server specs**: Allocate at least 8GB RAM and 4 CPU cores for faster builds
2. **SSD recommended**: Use SSD for `/var/cache/nix-builds` for better I/O
3. **Network**: Ensure gigabit LAN for fast cache transfers
4. **Parallel builds**: Nix will automatically use all CPU cores
5. **Keep cache warm**: Regular daily builds keep cache fresh

## FAQ

**Q: Why are builds taking so long?**  
A: First build rebuilds everything. Subsequent builds are faster (only changed packages).

**Q: Can I build darwin configurations too?**  
A: Not on Linux. Darwin builds require macOS. Use separate darwin builder.

**Q: How much bandwidth does this use?**  
A: Flake update downloads ~100-500MB. Builds don't use network (except initial nixpkgs download).

**Q: What if GitHub is down?**  
A: Build will fail that day. Next timer will retry. If clone exists, uses cached copy.

**Q: Can I push flake.lock updates back to GitHub?**  
A: Yes, but requires write access on deploy key. Not recommended for security.

**Q: How do I add more hosts?**  
A: Add to `hosts` list and redeploy. Next build will include them.

## Related Documentation

- [nix-serve-ng](https://github.com/aristanetworks/nix-serve-ng)
- [NixOS Binary Cache](https://nixos.org/manual/nix/stable/package-management/binary-cache.html)
- [SOPS-nix](https://github.com/Mic92/sops-nix)
- [Snowfall Lib](https://snowfall.org/guides/lib/)

## Support

For issues or questions:
1. Check logs: `sudo journalctl -u nix-cache-builder.service`
2. Verify network: `curl http://beez.sbulav.ru:5000/nix-cache-info`
3. Test manually: `sudo systemctl start nix-cache-builder.service`
4. Review this README's troubleshooting section
