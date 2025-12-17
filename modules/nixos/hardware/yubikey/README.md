# YubiKey Authentication Module

## How It Works

When both YubiKey and fingerprint modules are enabled, authentication follows this priority order across **all PAM services** (system login, swaylock, sudo, etc.):

### Authentication Flow

1. **YubiKey prompt appears first** - "Please touch the device"
   - If YubiKey is inserted → Touch it → Authentication succeeds ✅
   - If YubiKey is NOT inserted → Wait for timeout (~15 seconds) → Falls through to step 2

2. **Fingerprint reader activates**
   - If fingerprint enrolled → Scan finger → Authentication succeeds ✅
   - If fingerprint fails → Falls through to step 3

3. **Password prompt** (final fallback)
   - Type your password → Authentication succeeds ✅

### PAM Stack Order

```bash
# From /etc/pam.d/login, /etc/pam.d/swaylock, /etc/pam.d/sudo, etc.
auth sufficient pam_u2f.so          # order 10900 (YubiKey - FIRST)
auth sufficient pam_fprintd.so      # order 11400 (Fingerprint - SECOND)  
auth sufficient pam_unix.so         # order 11600 (Password - LAST)
```

## Testing the Configuration

Apply changes:
```bash
cd /home/sab/dotnix
sudo nixos-rebuild switch --flake .#nz
```

### Test 1: With YubiKey (Fastest)
1. Lock screen (Super+Shift+L) or logout
2. You should see "Please touch the device" prompt
3. Insert YubiKey if not already inserted
4. Touch the YubiKey → Unlocks immediately ✅

### Test 2: Without YubiKey (Fingerprint Fallback)
1. Remove YubiKey from USB port
2. Lock screen or logout
3. Wait for YubiKey timeout (~15 seconds)
4. Fingerprint reader activates automatically
5. Scan your finger → Unlocks ✅

### Test 3: Password Fallback
1. Don't insert YubiKey
2. Wait through fingerprint timeout or press Ctrl+C to skip
3. Password prompt appears
4. Type password → Unlocks ✅

## Configuration Options

### Adjusting YubiKey Timeout

The default timeout is ~15 seconds. To reduce it to 5 seconds, edit `modules/nixos/hardware/yubikey/default.nix`:

```nix
security.pam.u2f = {
  enable = true;
  control = "sufficient";
  
  settings = {
    cue = true;
    authpending_file = "/var/run/user/%u/pam-u2f-authpending";
    # Reduce timeout to 5 seconds
    max_devices = 1;
    prompt_timeout = 5;
  };
};
```

### Disabling Debug Output

Debug output is disabled by default. To enable for troubleshooting:

```nix
settings = {
  cue = true;
  debug = true;  # Enable debug logging
  authpending_file = "/var/run/user/%u/pam-u2f-authpending";
};
```

## Setup Requirements

### 1. Register Your YubiKey

You must register your YubiKey for U2F authentication:

```bash
# Create the configuration directory
mkdir -p ~/.config/Yubico

# Register your YubiKey (insert it first)
pamu2fcfg > ~/.config/Yubico/u2f_keys

# Register additional YubiKeys (append to file)
pamu2fcfg -n >> ~/.config/Yubico/u2f_keys
```

### 2. Verify Registration

```bash
cat ~/.config/Yubico/u2f_keys
# Should show: username:KeyHandle,PublicKey,CoseType,Options
```

### 3. Test Authentication

```bash
# Test with sudo
sudo -v
# Should prompt for YubiKey touch

# Test with screen lock
swaylock
# Should prompt for YubiKey touch
```

## Troubleshooting

### YubiKey Not Detected

1. Check if YubiKey is properly inserted
2. Verify U2F keys file exists: `ls -la ~/.config/Yubico/u2f_keys`
3. Check PAM logs: `journalctl -u systemd-logind -n 50`

### Timeout Too Long

- See "Adjusting YubiKey Timeout" section above
- Default is ~15 seconds, can be reduced to 5-10 seconds

### Fingerprint Activates Instead of YubiKey

- This means YubiKey authentication is not configured
- Check `/etc/pam.d/swaylock` for `pam_u2f.so` line
- Verify YubiKey module is enabled: `hardware.yubikey.enable = true;`

## Implementation Notes

- **Consistent across all PAM services**: YubiKey works the same way for login, swaylock, sudo, etc.
- **No manual PAM overrides**: NixOS automatically configures PAM ordering based on module priorities
- **Graceful fallback**: If YubiKey is absent, authentication continues to fingerprint/password seamlessly
