# YubiKey GPG Setup - Final Steps

## 🎉 Current Status

✅ **YubiKey GPG key generated successfully!**
- Key ID: `15DB4B4A58D027CB73D0E911D06334BAEC6DC034`
- Type: RSA 2048
- Created: 2026-01-14
- Expires: 2031-01-13
- Card Serial: 0006 16936125

✅ **Fallback key available:**
- Key ID: `7C43420F61CEC7FB`
- Type: ed25519
- Created: 2022-04-19

✅ **Configuration ready:**
- GPG wrapper installed: `gpg-smart-sign`
- Git signing enabled
- Smart card support active
- Automatic key detection configured

## 🔧 Issue Fixed

**Problem:** `pinentry-mode loopback` was preventing interactive passphrase entry

**Solution:** Removed loopback mode to enable GUI pinentry (pinentry-gnome3)

## 📝 Final Steps to Complete Setup

### Step 1: Apply Fixed Configuration

```bash
# Rebuild NixOS with fixed GPG config
sudo nixos-rebuild switch --flake .#mz

# Restart GPG services
gpgconf --kill all

# Verify services
systemctl status pcscd
```

**What this does:**
- Updates GPG config to use interactive pinentry
- Updates git config to prefer YubiKey key (15DB4B4A...)
- Fixes scdaemon config for better YubiKey support
- Restarts all GPG-related services

### Step 2: Export YubiKey Public Key

```bash
# Export your YubiKey's public key
gpg --armor --export 15DB4B4A58D027CB73D0E911D06334BAEC6DC034 > ~/yubikey-pubkey-2026.asc

# View the key
cat ~/yubikey-pubkey-2026.asc
```

### Step 3: Add Both Keys to GitHub

1. Go to: https://github.com/settings/keys
2. Click "New GPG key"
3. Add YubiKey public key (from Step 2)
4. Verify both keys are listed:
   - ✅ YubiKey key: `15DB4B4A58D027CB73D0E911D06334BAEC6DC034`
   - ✅ Fallback key: `7C43420F61CEC7FB` (should already be there)

**Why both keys?**
- YubiKey key used when YubiKey is inserted (primary)
- Fallback key used when YubiKey is not available
- Both will show "Verified" ✓ on GitHub commits

### Step 4: Test YubiKey Signing

```bash
# Create test repository
mkdir -p /tmp/test-yubikey-final
cd /tmp/test-yubikey-final
git init

# Configure git
git config user.name "Sergei Bulavintsev"
git config user.email "bulavintsev.sergey@gmail.com"

# Create and commit test file
echo "Testing YubiKey GPG signing" > test.txt
git add test.txt
git commit -m "Test: YubiKey signature"

# Expected behavior:
# 1. YubiKey LED blinks
# 2. PIN prompt appears (GUI dialog via pinentry-gnome3)
# 3. Enter your YubiKey PIN (6 digits)
# 4. Commit succeeds

# Verify signature
git log --show-signature -1
```

**Expected output:**
```
gpg: Signature made [DATE]
gpg:                using RSA key 15DB4B4A58D027CB73D0E911D06334BAEC6DC034
gpg: Good signature from "Sergei Bulavintsev <bulavintsev.sergey@gmail.com>"
```

**Check which key was used:**
```bash
git log --format="%G? %GK %GS" -1

# Should show:
# G 15DB4B4A58D027CB73D0E911D06334BAEC6DC034 Sergei Bulavintsev
```

### Step 5: Test Fallback Signing

```bash
# Still in /tmp/test-yubikey-final

# REMOVE YubiKey from USB port

# Verify YubiKey is gone
gpg --card-status
# Expected: "gpg: selecting card failed: No such device"

# Create another commit
echo "Testing fallback signing" >> test.txt
git add test.txt
git commit -m "Test: Fallback signature"

# Expected behavior:
# 1. No YubiKey LED (removed)
# 2. Password prompt appears (GUI dialog)
# 3. Enter password for key 7C43420F61CEC7FB
# 4. Commit succeeds

# Verify signature
git log --show-signature -1
```

**Expected output:**
```
gpg: Signature made [DATE]
gpg:                using EDDSA key 0EC40FA888BF149D8A449B547C43420F61CEC7FB
gpg: Good signature from "Sergei Bulavintsev <bulavintsev.sergey@gmail.com>"
```

**Check which key was used:**
```bash
git log --format="%G? %GK" -1

# Should show:
# G 7C43420F61CEC7FB
```

### Step 6: Test Automatic Switching

```bash
# Test rapid switching between keys

# INSERT YubiKey
echo "YubiKey test 1" >> test.txt
git add test.txt && git commit -m "YubiKey commit 1"
git log --format="%GK" -1  # Should show: 15DB4B4A...

# REMOVE YubiKey
echo "Fallback test 1" >> test.txt
git add test.txt && git commit -m "Fallback commit 1"
git log --format="%GK" -1  # Should show: 7C43420F61CEC7FB

# INSERT YubiKey again
echo "YubiKey test 2" >> test.txt
git add test.txt && git commit -m "YubiKey commit 2"
git log --format="%GK" -1  # Should show: 15DB4B4A...

# View all signatures
git log --format="%h %GK %s" -5
```

**Expected:** Commits alternate between YubiKey and fallback keys

### Step 7: Push to GitHub and Verify

```bash
# Create a test repository on GitHub (or use existing)
git remote add origin git@github.com:USERNAME/REPO.git
git branch -M master
git push -u origin master

# Check commits on GitHub
# All commits should show "Verified" ✓ badge
```

## 🎯 Expected Workflow

### Normal Usage (YubiKey Inserted):
1. You make changes and run `git commit`
2. Wrapper detects YubiKey automatically
3. YubiKey LED blinks
4. PIN dialog appears (first time, or after cache expires)
5. Enter 6-digit PIN
6. Commit signed with YubiKey key
7. GitHub shows "Verified" ✓

### Fallback Mode (YubiKey Not Available):
1. You make changes and run `git commit`
2. Wrapper detects no YubiKey
3. Password dialog appears
4. Enter GPG passphrase
5. Commit signed with fallback key
6. GitHub shows "Verified" ✓

**Zero manual intervention required!** 🎉

## 📊 Configuration Summary

### System Config (`systems/x86_64-linux/mz/default.nix`)
```nix
hardware.yubikey = {
  enable = true;
  smartcard.enable = true;  # Enables pcscd, udev rules, etc.
};
```

### Home Config (`homes/x86_64-linux/sab@mz/default.nix`)
```nix
custom.security.gpg = {
  enable = true;
  agentTimeout = 5;
  yubikeyKeyId = "15DB4B4A58D027CB73D0E911D06334BAEC6DC034";
  fallbackKeyId = "7C43420F61CEC7FB";
};

custom.tools.git = {
  enable = true;
  enableSigning = true;
  gpgProgram = "${pkgs.custom.gpg-smart-sign}/bin/gpg-smart-sign";
  signingKey = "15DB4B4A58D027CB73D0E911D06334BAEC6DC034";  # YubiKey key
};
```

## 🔐 Security Best Practices

### PIN Management
- ✅ Change default YubiKey PINs (if not done yet):
  ```bash
  gpg --card-edit
  admin
  passwd
  # Change User PIN (option 1)
  # Change Admin PIN (option 3)
  quit
  ```
- ✅ Default User PIN: `123456` → Change it!
- ✅ Default Admin PIN: `12345678` → Change it!
- ⚠️ 3 failed attempts = PIN blocked
- ⚠️ If User PIN blocked: Unblock with Admin PIN
- ⚠️ If Admin PIN blocked: YubiKey must be reset (all keys lost!)

### Key Backup
- ✅ Export and backup YubiKey public key (Step 2 above)
- ✅ Store backup in secure location (password manager, encrypted drive)
- ✅ Keep fallback key passphrase in password manager
- ❌ NEVER backup YubiKey private keys (they can't be extracted anyway!)

### Key Expiration
- ✅ YubiKey key expires: 2031-01-13 (5 years)
- ✅ Set calendar reminder for 2030 to renew key
- ✅ Fallback key: No expiration (consider adding one)

### GitHub Keys
- ✅ Both keys added to GitHub
- ✅ Verify signatures work for both keys
- ✅ If YubiKey lost/stolen: Delete public key from GitHub immediately
- ✅ Fallback key remains valid and working

## 🐛 Troubleshooting

### Issue: "Bad passphrase" error
**Cause:** Old config cached or pinentry not working
**Fix:**
```bash
gpgconf --kill all
cat ~/.gnupg/gpg.conf  # Should NOT have: pinentry-mode loopback
sudo nixos-rebuild switch --flake .#mz
```

### Issue: No PIN/password prompt appears
**Cause:** pinentry not configured correctly
**Fix:**
```bash
gpgconf --list-components | grep pinentry
# Should show: pinentry-gnome3

# Restart GPG agent
gpgconf --kill gpg-agent
```

### Issue: YubiKey not detected
**Cause:** pcscd not running or USB issue
**Fix:**
```bash
systemctl status pcscd
lsusb | grep -i yubi
gpg --card-status
```

### Issue: Wrong key being used
**Cause:** Wrapper not detecting YubiKey correctly
**Fix:**
```bash
# Check YubiKey has key
gpg --card-status | grep "Signature key"
# Should NOT be: [none]

# Check wrapper is being used
git config --get gpg.program
# Should be: /nix/store/.../gpg-smart-sign

# Test wrapper directly
gpg-smart-sign --version
```

### Issue: Commits not showing "Verified" on GitHub
**Cause:** Public key not in GitHub or email mismatch
**Fix:**
1. Check email in git config matches GPG key email
2. Add public key to GitHub: https://github.com/settings/keys
3. Wait 1-2 minutes for GitHub to process

## 📚 Documentation Reference

- **Setup Guide**: `docs/yubikey-gpg-setup.md`
- **Testing Guide**: `docs/yubikey-gpg-testing.md`
- **This Document**: `docs/yubikey-gpg-final-steps.md`

## ✅ Success Checklist

After completing all steps, verify:

- [ ] Configuration rebuilt: `sudo nixos-rebuild switch --flake .#mz`
- [ ] GPG config has no loopback mode: `cat ~/.gnupg/gpg.conf`
- [ ] YubiKey public key exported and backed up
- [ ] Both keys added to GitHub
- [ ] Test commit with YubiKey works (PIN prompt)
- [ ] Test commit without YubiKey works (password prompt)
- [ ] Automatic switching works (insert/remove YubiKey)
- [ ] GitHub shows "Verified" ✓ on all commits
- [ ] YubiKey PINs changed from defaults
- [ ] Backup created for public key

## 🎊 You're Done!

Your YubiKey GPG signing setup is complete! Enjoy secure, transparent, automatic commit signing with hardware token support and fallback capability.

**Remember:**
- YubiKey = Primary signing method (when inserted)
- Password key = Fallback (when YubiKey not available)
- Both work seamlessly, automatically
- Both show "Verified" on GitHub

Happy secure coding! 🔐✨
