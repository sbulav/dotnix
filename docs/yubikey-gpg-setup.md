# YubiKey GPG Setup Guide

This guide walks you through setting up your YubiKey for GPG commit signing with automatic detection and fallback to your existing password-based GPG key.

## Overview

After completing this setup:
- **YubiKey inserted**: Commits will be signed with your YubiKey's GPG key (no password needed, just PIN)
- **YubiKey removed**: Commits will be signed with your existing key (7C43420F61CEC7FB) using password
- **Automatic detection**: No manual switching required - the system detects YubiKey presence automatically

## Prerequisites

1. **YubiKey hardware** (YubiKey 4, 5, or newer with OpenPGP support)
2. **NixOS configuration applied** with:
   - `hardware.yubikey.enable = true`
   - `hardware.yubikey.smartcard.enable = true`
   - `custom.security.gpg.enable = true`
   - `custom.tools.git` configured with `gpg-smart-sign`
3. **System rebuilt**: `sudo nixos-rebuild switch --flake .#mz`

## Step 1: Verify YubiKey Detection

First, ensure your YubiKey is properly detected:

```bash
# Insert YubiKey and check if it's detected
gpg --card-status
```

Expected output should show:
```
Reader ...........: 1050:0407:X:0
Application ID ...: D2760001240100000006XXXXXXXXXX
Application type .: OpenPGP
Version ..........: 3.4
Manufacturer .....: Yubico
Serial number ....: XXXXXXXX
...
```

If you see an error, check:
```bash
# Verify pcscd service is running
systemctl status pcscd

# Check if YubiKey is detected by system
lsusb | grep -i yubi
```

## Step 2: Check YubiKey PINs

YubiKey comes with default PINs that you should change:

**Default PINs:**
- User PIN: `123456`
- Admin PIN: `12345678`

**Change PINs (IMPORTANT for security):**

```bash
gpg --card-edit

# At the gpg/card> prompt:
admin          # Enter admin mode
passwd         # Change PINs
# Select option 1 to change User PIN
# Select option 3 to change Admin PIN
quit
```

**WRITE DOWN YOUR NEW PINs** - if you forget them, you'll need to reset the entire YubiKey!

## Step 3: Generate GPG Key on YubiKey

Now we'll generate a GPG key directly on the YubiKey (recommended approach - key never leaves device):

```bash
gpg --card-edit

# At the gpg/card> prompt:
admin                # Enter admin mode
generate            # Start key generation

# You'll be asked several questions:
# 1. "Make off-card backup?" - Answer: n (for maximum security)
# 2. "Key validity" - Recommend: 2y (2 years) or as needed
# 3. "Real name" - Enter: Sergei Bulavintsev
# 4. "Email address" - Enter: bulavintsev.sergey@gmail.com
# 5. "Comment" - Enter: YubiKey or leave empty
```

**Recommended key algorithm:** The system will use ed25519 (Curve 25519) by default, which is:
- Fast and efficient
- Strong security (equivalent to RSA 3072-bit)
- Well-supported by GitHub and modern systems

The key generation takes 20-30 seconds. During this time, the YubiKey LED will blink.

## Step 4: Verify Key Creation

After generation completes:

```bash
# Still in gpg --card-edit:
list            # View key information

# You should see:
# Signature key ....: [KEY_ID]
# Encryption key....: [KEY_ID]
# Authentication key: [KEY_ID]

quit
```

Also verify from command line:

```bash
# Show card status with keys
gpg --card-status

# List GPG keys (should include your YubiKey key)
gpg --list-keys
gpg --list-secret-keys
```

## Step 5: Export Public Key

Export your YubiKey's public key to add to GitHub:

```bash
# Find your YubiKey key ID from previous step
# It's the long hex string shown in "Signature key"

# Export public key (replace KEY_ID with your actual key)
gpg --armor --export KEY_ID > ~/yubikey-pubkey.asc

# View the public key
cat ~/yubikey-pubkey.asc
```

You'll see output like:
```
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF... [long base64 string]
-----END PGP PUBLIC KEY BLOCK-----
```

## Step 6: Add Public Key to GitHub

1. Copy the entire contents of `~/yubikey-pubkey.asc` (including BEGIN and END lines)
2. Go to GitHub: https://github.com/settings/keys
3. Click "New GPG key"
4. Paste your public key
5. Click "Add GPG key"

**Keep both keys in GitHub:**
- Your existing key: `7C43420F61CEC7FB` (fallback)
- Your new YubiKey key (primary)

This allows commits signed with either key to show "Verified" ✓

## Step 7: Configure Git to Prefer YubiKey Key

Update your home configuration to use the YubiKey key as primary:

```nix
# In homes/x86_64-linux/sab@mz/default.nix

custom.tools.git = {
  enable = true;
  enableSigning = true;
  gpgProgram = "${pkgs.custom.gpg-smart-sign}/bin/gpg-smart-sign";
  signingKey = "YOUR_YUBIKEY_KEY_ID";  # Update this with your YubiKey key ID
};
```

Rebuild your configuration:
```bash
home-manager switch --flake .#sab@mz
```

## Step 8: Set Cardholder Information (Optional)

You can store additional info on the YubiKey card:

```bash
gpg --card-edit

admin
name            # Set cardholder name
# Enter surname: Bulavintsev
# Enter given name: Sergei

login           # Set login (email)
# Enter: bulavintsev.sergey@gmail.com

url             # Set URL to public key (optional)
# Example: https://github.com/USERNAME.gpg

quit
```

## Step 9: Test Signing

### Test 1: With YubiKey Inserted

```bash
# Create test repository
mkdir -p /tmp/test-yubikey-sign
cd /tmp/test-yubikey-sign
git init

# Create and commit a test file
echo "Test YubiKey signing" > test.txt
git add test.txt
git commit -m "Test YubiKey commit signing"

# Verify signature
git log --show-signature -1
```

**Expected behavior:**
- YubiKey LED blinks
- PIN prompt appears (via pinentry-gnome3)
- Commit is signed with YubiKey key
- Output shows "Good signature from 'Sergei Bulavintsev <bulavintsev.sergey@gmail.com>'"

### Test 2: Without YubiKey (Fallback)

```bash
# Still in /tmp/test-yubikey-sign

# REMOVE YubiKey from USB port

# Create another commit
echo "Test fallback signing" >> test.txt
git add test.txt
git commit -m "Test fallback commit signing"

# Verify signature
git log --show-signature -1
```

**Expected behavior:**
- No YubiKey LED (removed)
- Password prompt appears (for key 7C43420F61CEC7FB)
- Commit is signed with fallback key
- Output shows "Good signature from 'Sergei Bulavintsev <bulavintsev.sergey@gmail.com>'"

### Test 3: Push to GitHub and Verify

```bash
# Create a test repository on GitHub or use existing one
git remote add origin git@github.com:USERNAME/REPO.git
git push -u origin master

# Check commits on GitHub - they should show "Verified" ✓
```

## Troubleshooting

### Issue: "No secret key" error

**Solution:**
```bash
# Check if GPG sees the card
gpg --card-status

# Restart GPG agent
gpgconf --kill gpg-agent
gpgconf --launch gpg-agent

# Try again
```

### Issue: PIN entry doesn't appear

**Solution:**
```bash
# Check which pinentry is configured
gpg-agent --version

# Verify pinentry-gnome3 is installed
which pinentry-gnome3

# Restart GPG agent
gpgconf --kill gpg-agent
```

### Issue: YubiKey not detected

**Solution:**
```bash
# Check pcscd service
systemctl status pcscd

# Restart pcscd
sudo systemctl restart pcscd

# Remove and reinsert YubiKey

# Check USB detection
lsusb | grep -i yubi
```

### Issue: "Card error" or timeout

**Solution:**
```bash
# Kill any stuck processes
gpgconf --kill all

# Remove YubiKey, wait 5 seconds, reinsert

# Try again
gpg --card-status
```

### Issue: Signing takes too long or times out

**Cause:** The `gpg-smart-sign` wrapper checks for YubiKey on every commit.

**Solution:**
If detection is slow, you can add caching:
1. Check `/tmp/gpg-yubikey-present` file exists
2. Add timeout to wrapper (advanced - contact maintainer)

### Issue: Wrong key being used

**Debug which key is selected:**
```bash
# Set debug mode
export GPG_TTY=$(tty)
export GPG_DEBUG=1

# Try a commit
git commit --amend --no-edit

# Check which key was attempted
gpg --list-keys
```

## Advanced: Key Backup

### Backup YubiKey Public Key

**IMPORTANT:** Always keep a backup of your public key!

```bash
# Export public key to multiple locations
gpg --armor --export YOUR_YUBIKEY_KEY_ID > ~/yubikey-public-$(date +%Y%m%d).asc

# Backup to secure location
cp ~/yubikey-public-*.asc /path/to/secure/backup/
```

### Recovery Scenario

If you lose your YubiKey:

1. **Commits signed with YubiKey**: Will still show "Verified" on GitHub (public key is stored)
2. **New commits**: Will use fallback key (7C43420F61CEC7FB) automatically
3. **Get new YubiKey**: Follow this guide again to set up a new key
4. **Revoke old key**: If YubiKey is lost/stolen:
   ```bash
   # You cannot revoke without the YubiKey, but you can remove from GitHub
   # Go to GitHub Settings → GPG keys → Delete the lost YubiKey's public key
   ```

## PIN Retry Counter

YubiKey has a retry counter for PINs:

- **User PIN**: 3 attempts before blocking
- **Admin PIN**: 3 attempts before permanent lock

**If User PIN is blocked:**
```bash
gpg --card-edit
admin
unblock     # Use Admin PIN to unblock User PIN
```

**If Admin PIN is blocked:**
- YubiKey OpenPGP applet must be fully reset (all keys lost!)
- Use `ykman openpgp reset` (requires physical confirmation)

## Security Best Practices

1. **Always use unique PINs** (not defaults!)
2. **Keep backup of public key** in secure location
3. **Add both keys to GitHub** (YubiKey + fallback)
4. **Don't share YubiKey** - it's personal authentication device
5. **Use key expiration** (2 years recommended)
6. **Physical security**: Keep YubiKey on keychain or secure location
7. **Regular testing**: Test both YubiKey and fallback monthly

## Key Information Reference

After setup, document your key details:

```bash
# YubiKey Key Details
# ====================
# Key ID: [Your YubiKey key ID]
# Created: [Date]
# Expires: [Date]
# Algorithm: ed25519
# Serial Number: [YubiKey serial from gpg --card-status]
#
# Fallback Key Details
# ====================
# Key ID: 7C43420F61CEC7FB
# Created: 2022-04-19
# Algorithm: ed25519
#
# PINs Changed: [Date]
# Public Key Backup: [Location]
# GitHub Keys Added: [Date]
```

## Questions?

If you encounter issues not covered here:

1. Check NixOS module configuration in `modules/nixos/hardware/yubikey/default.nix`
2. Verify home configuration in `homes/x86_64-linux/sab@mz/default.nix`
3. Review wrapper logic in `packages/gpg-smart-sign/default.nix`
4. Check GPG agent logs: `journalctl --user -u gpg-agent`

## Next Steps

Once setup is complete:
1. ✓ Test both signing modes (with/without YubiKey)
2. ✓ Verify GitHub shows "Verified" on commits
3. ✓ Backup public key to secure location
4. ✓ Document your YubiKey serial and key IDs
5. ✓ Set calendar reminder to renew key before expiration

Happy secure signing! 🔐✨
