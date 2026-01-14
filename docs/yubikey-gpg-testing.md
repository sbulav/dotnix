# YubiKey GPG Signing - Testing Procedure

This document provides a comprehensive testing workflow to verify your YubiKey GPG signing implementation is working correctly.

## Prerequisites

Before testing, ensure:
1. ✅ Configuration has been rebuilt: `sudo nixos-rebuild switch --flake .#mz`
2. ✅ Home Manager has been applied: `home-manager switch --flake .#sab@mz`
3. ✅ YubiKey is physically available (for insertion/removal tests)
4. ✅ You have completed key generation from `docs/yubikey-gpg-setup.md`

## Test Suite

### Test 1: Verify System Services

**Purpose:** Ensure all required services are running

```bash
# Check pcscd service status
systemctl status pcscd

# Expected: Active (running)
# If not running:
sudo systemctl start pcscd
```

**Expected Output:**
```
● pcscd.service - PC/SC Smart Card Daemon
     Loaded: loaded (/etc/systemd/system/pcscd.service; enabled; preset: enabled)
     Active: active (running) since [DATE]
```

### Test 2: Verify YubiKey Detection

**Purpose:** Confirm YubiKey is properly recognized as smartcard

```bash
# Insert YubiKey into USB port

# Check card status
gpg --card-status
```

**Expected Output:**
```
Reader ...........: Yubico YubiKey
Application ID ...: D2760001240100000006XXXXXXXX
Application type .: OpenPGP
Version ..........: 3.4
Manufacturer .....: Yubico
Serial number ....: XXXXXXXX
Signature key ....: [KEY_ID]  (should NOT be "[none]")
Encryption key....: [KEY_ID]
Authentication key: [KEY_ID]
```

**If Signature key shows "[none]":**
- You need to generate a key on the YubiKey
- Follow Step 3 in `docs/yubikey-gpg-setup.md`

### Test 3: Verify GPG Configuration

**Purpose:** Check GPG and GPG agent are properly configured

```bash
# Check GPG environment variables
echo $GPG_TTY
echo $SSH_AUTH_SOCK

# Check GPG agent is running
gpgconf --list-components | grep gpg-agent

# Check GPG configuration files
cat ~/.gnupg/gpg.conf
cat ~/.gnupg/gpg-agent.conf
```

**Expected Output:**
```
# GPG_TTY should show: /dev/pts/X (terminal device)
# SSH_AUTH_SOCK should show: /run/user/1000/gnupg/S.gpg-agent.ssh

# gpg.conf should contain:
use-agent
pinentry-mode loopback

# gpg-agent.conf should contain:
enable-ssh-support
default-cache-ttl 28800
max-cache-ttl 28800
allow-loopback-pinentry
```

### Test 4: Verify Git Configuration

**Purpose:** Ensure Git is configured for GPG signing with smart wrapper

```bash
# Check Git GPG configuration
git config --get user.signingkey
git config --get commit.gpgsign
git config --get gpg.program

# List GPG keys
gpg --list-keys
gpg --list-secret-keys
```

**Expected Output:**
```
# user.signingkey: 7C43420F61CEC7FB (or your fallback key)
# commit.gpgsign: true
# gpg.program: /nix/store/...-gpg-smart-sign-1.0.0/bin/gpg-smart-sign

# GPG keys should list:
# - Your YubiKey key (with card-no)
# - Your fallback key (7C43420F61CEC7FB)
```

### Test 5: Test YubiKey Signing (WITH YubiKey)

**Purpose:** Verify commits are signed with YubiKey when present

```bash
# Ensure YubiKey is INSERTED
# Create test repository
mkdir -p /tmp/test-yubikey-signing
cd /tmp/test-yubikey-signing
git init

# Configure git for test repo
git config user.name "Sergei Bulavintsev"
git config user.email "bulavintsev.sergey@gmail.com"

# Create and commit test file
echo "Test YubiKey signing" > test.txt
git add test.txt
git commit -m "Test: YubiKey signature"

# Verify signature
git log --show-signature -1
```

**Expected Behavior:**
1. YubiKey LED blinks
2. PIN prompt appears (pinentry-gnome3 GUI)
3. After entering PIN, commit succeeds
4. Signature verification shows:
   ```
   gpg: Signature made [DATE]
   gpg:                using EDDSA key [YUBIKEY_KEY_ID]
   gpg: Good signature from "Sergei Bulavintsev <bulavintsev.sergey@gmail.com>"
   ```

**Check which key was used:**
```bash
git log --format="%G? %GK %GS" -1

# Expected output:
# G [YUBIKEY_KEY_ID] Sergei Bulavintsev <bulavintsev.sergey@gmail.com>
# 
# Where:
# - G = Good signature
# - [YUBIKEY_KEY_ID] = Your YubiKey key ID (NOT 7C43420F61CEC7FB)
```

### Test 6: Test Fallback Signing (WITHOUT YubiKey)

**Purpose:** Verify commits use fallback key when YubiKey is removed

```bash
# Still in /tmp/test-yubikey-signing

# REMOVE YubiKey from USB port (important!)

# Verify YubiKey is gone
gpg --card-status
# Expected: "gpg: selecting card failed: No such device"

# Create another commit
echo "Test fallback signing" >> test.txt
git add test.txt
git commit -m "Test: Fallback signature"

# Verify signature
git log --show-signature -1
```

**Expected Behavior:**
1. No YubiKey LED (it's removed)
2. Password prompt appears (for key 7C43420F61CEC7FB)
3. After entering password, commit succeeds
4. Signature verification shows:
   ```
   gpg: Signature made [DATE]
   gpg:                using EDDSA key 0EC40FA888BF149D8A449B547C43420F61CEC7FB
   gpg: Good signature from "Sergei Bulavintsev <bulavintsev.sergey@gmail.com>"
   ```

**Check which key was used:**
```bash
git log --format="%G? %GK %GS" -1

# Expected output:
# G 7C43420F61CEC7FB Sergei Bulavintsev <bulavintsev.sergey@gmail.com>
#
# Note: Key ID should be 7C43420F61CEC7FB (fallback key)
```

### Test 7: Test Key Switching

**Purpose:** Verify automatic switching between keys

```bash
# Still in /tmp/test-yubikey-signing

# Test 7a: Insert YubiKey
# INSERT YubiKey

# Create commit
echo "Switch test 1" >> test.txt
git add test.txt
git commit -m "Test: Switch to YubiKey"

# Check key used
git log --format="%G? %GK" -1
# Expected: YubiKey key ID

# Test 7b: Remove YubiKey
# REMOVE YubiKey

# Create commit
echo "Switch test 2" >> test.txt
git add test.txt
git commit -m "Test: Switch to fallback"

# Check key used
git log --format="%G? %GK" -1
# Expected: 7C43420F61CEC7FB

# Test 7c: Reinsert YubiKey
# INSERT YubiKey

# Create commit
echo "Switch test 3" >> test.txt
git add test.txt
git commit -m "Test: Switch back to YubiKey"

# Check key used
git log --format="%G? %GK" -1
# Expected: YubiKey key ID
```

**Expected Result:**
All three commits should succeed with correct key selection:
1. First commit: YubiKey key
2. Second commit: Fallback key (7C43420F61CEC7FB)
3. Third commit: YubiKey key

### Test 8: GitHub Verification

**Purpose:** Ensure GitHub recognizes signatures as verified

**Prerequisites:**
- Both public keys added to GitHub (YubiKey + fallback)
- Test repository pushed to GitHub

```bash
# In /tmp/test-yubikey-signing

# Add remote (replace with your test repo)
git remote add origin git@github.com:USERNAME/test-yubikey.git

# Push commits
git push -u origin master

# Open GitHub in browser
# Check each commit shows "Verified" badge ✓
```

**Expected on GitHub:**
- All commits show green "Verified" badge
- Clicking badge shows:
  - Commit signed with: [YubiKey key OR fallback key]
  - Verified signature from Sergei Bulavintsev

**If NOT verified:**
1. Check public keys are in GitHub Settings → GPG keys
2. Verify email matches: `bulavintsev.sergey@gmail.com`
3. Check key IDs match those in your GPG keyring

### Test 9: Performance Test

**Purpose:** Verify signing doesn't cause noticeable delays

```bash
# Time a series of commits with YubiKey
cd /tmp/test-yubikey-signing

# INSERT YubiKey

for i in {1..5}; do
  echo "Commit $i" >> test.txt
  git add test.txt
  time git commit -m "Performance test $i"
done
```

**Expected:**
- First commit: 2-5 seconds (PIN entry)
- Subsequent commits: <1 second (PIN cached)
- No timeouts or hanging

**Acceptable performance:**
- Detection overhead: <100ms
- PIN entry (first time): User-dependent
- Cached signing: <1 second

### Test 10: Wrapper Functionality Test

**Purpose:** Verify gpg-smart-sign wrapper works correctly

```bash
# Check wrapper exists and is executable
which gpg-smart-sign
ls -la $(which gpg-smart-sign)

# Test wrapper directly
# WITH YubiKey inserted:
echo "test" | gpg-smart-sign --clearsign

# WITHOUT YubiKey:
# (Remove YubiKey)
echo "test" | gpg-smart-sign --clearsign
```

**Expected:**
- Wrapper should be in `/nix/store/.../bin/gpg-smart-sign`
- Both tests should succeed
- WITH YubiKey: Uses YubiKey key (PIN prompt)
- WITHOUT YubiKey: Uses fallback key (password prompt)

### Test 11: Error Handling

**Purpose:** Verify graceful handling of error conditions

```bash
cd /tmp/test-yubikey-signing

# Test 11a: Wrong PIN (YubiKey)
# INSERT YubiKey
# Kill GPG agent to clear PIN cache
gpgconf --kill gpg-agent

echo "error test" >> test.txt
git add test.txt
git commit -m "Test: Wrong PIN"
# Enter WRONG PIN intentionally

# Expected: Error message, retry prompt
# Enter correct PIN on retry
# Commit should succeed

# Test 11b: YubiKey removed during commit
# This is hard to test manually, but wrapper should handle gracefully
# If you remove YubiKey during PIN entry, it should fall back

# Test 11c: GPG agent crash recovery
gpgconf --kill all
# Try to commit
echo "recovery test" >> test.txt
git add test.txt
git commit -m "Test: Agent recovery"

# Expected: GPG agent restarts automatically, commit succeeds
```

## Troubleshooting Test Failures

### Test 1 Failed: pcscd not running

**Fix:**
```bash
sudo systemctl start pcscd
sudo systemctl enable pcscd
```

### Test 2 Failed: YubiKey not detected

**Fix:**
```bash
# Check USB connection
lsusb | grep -i yubi

# Restart pcscd
sudo systemctl restart pcscd

# Remove and reinsert YubiKey
```

### Test 5 Failed: Wrong key used

**Debug:**
```bash
# Check what gpg-smart-sign is detecting
export GPG_DEBUG=1
git commit --amend --no-edit

# Check GPG agent status
gpgconf --list-dirs
ps aux | grep gpg-agent

# Check which keys GPG sees
gpg --card-status
gpg --list-secret-keys
```

### Test 6 Failed: Fallback not working

**Fix:**
```bash
# Verify fallback key exists
gpg --list-secret-keys 7C43420F61CEC7FB

# Check if key is accessible
echo "test" | gpg --default-key 7C43420F61CEC7FB --clearsign

# If key is missing or expired, it won't work
```

### Test 8 Failed: GitHub not verifying

**Fix:**
1. Export public keys:
   ```bash
   # YubiKey key
   gpg --armor --export YOUR_YUBIKEY_KEY_ID > yubikey.asc
   
   # Fallback key
   gpg --armor --export 7C43420F61CEC7FB > fallback.asc
   ```

2. Add both to GitHub: Settings → GPG keys → New GPG key

3. Verify email matches:
   ```bash
   git config user.email
   # Should be: bulavintsev.sergey@gmail.com
   ```

## Test Results Checklist

After completing all tests, verify:

- [ ] ✅ Test 1: pcscd service running
- [ ] ✅ Test 2: YubiKey detected by GPG
- [ ] ✅ Test 3: GPG configuration correct
- [ ] ✅ Test 4: Git configuration correct
- [ ] ✅ Test 5: YubiKey signing works (with PIN)
- [ ] ✅ Test 6: Fallback signing works (with password)
- [ ] ✅ Test 7: Automatic key switching works
- [ ] ✅ Test 8: GitHub verification works for both keys
- [ ] ✅ Test 9: Performance is acceptable
- [ ] ✅ Test 10: Wrapper functions correctly
- [ ] ✅ Test 11: Error handling is graceful

## Post-Testing

Once all tests pass:

1. **Clean up test repository:**
   ```bash
   rm -rf /tmp/test-yubikey-signing
   ```

2. **Document your keys:**
   ```bash
   # YubiKey Key ID: [YOUR_YUBIKEY_KEY_ID]
   # Fallback Key ID: 7C43420F61CEC7FB
   # Both keys added to GitHub: [DATE]
   # Testing completed: [DATE]
   ```

3. **Regular testing schedule:**
   - Test YubiKey signing: Weekly
   - Test fallback: Monthly
   - Test GitHub verification: After any key changes

## Maintenance

### Monthly Checks

- Verify pcscd service is running
- Test YubiKey detection
- Verify both keys haven't expired
- Check GitHub keys are still valid

### When to Re-test

- After NixOS system updates
- After changing GPG configuration
- If YubiKey firmware updated
- If experiencing signing issues
- Before important commits/releases

## Support

If tests fail after following this guide:
1. Check module configurations in `modules/`
2. Review `docs/yubikey-gpg-setup.md`
3. Check GPG agent logs: `journalctl --user -u gpg-agent`
4. Verify YubiKey firmware version: `ykman info`

## Success Criteria

Your YubiKey GPG signing implementation is working correctly if:

✅ All 11 tests pass
✅ YubiKey signing is transparent and automatic
✅ Fallback key works when YubiKey is removed
✅ GitHub shows "Verified" on all commits
✅ Performance is acceptable (no noticeable delays)
✅ Error handling is graceful (no crashes)

Happy signing! 🔐✨
