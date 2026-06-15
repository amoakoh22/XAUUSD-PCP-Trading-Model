# Claude Code on Android via Termux — Runbook

Tested on: Android (ARM64), Termux from F-Droid, Claude Code v2.1.177

---

## Why This Is Non-Trivial

Claude Code ships native binaries for `linux-arm64` and `linux-arm64-musl`, but
Android is detected as `linux-arm64-android` — a platform not supported by the
installer. The native binaries are also compiled as non-PIE (`ET_EXEC`) which
Android's dynamic linker rejects. The workaround is to run Claude Code inside a
real Linux environment (Ubuntu) via `proot-distro`.

---

## Prerequisites

- Android phone (ARM64 / 64-bit)
- **Termux installed from F-Droid** — NOT the Google Play Store version (abandoned)
  - https://f-droid.org/app/com.termux
- A Claude account (Pro, Max, Team, or Enterprise) or Anthropic API key

---

## Step 1 — Update Termux

```bash
pkg update && pkg upgrade
```

---

## Step 2 — Install proot-distro and Ubuntu

```bash
pkg install proot-distro
proot-distro install ubuntu
```

The Ubuntu download takes a few minutes.

---

## Step 3 — Log into Ubuntu

```bash
proot-distro login ubuntu
```

Your prompt changes to `root@localhost:~#`. All remaining steps run inside here.

---

## Step 4 — Install NVM and Node.js 20

Do **not** use Ubuntu's system Node.js (`apt install nodejs`) — it installs old
package versions that conflict with Claude Code's dependencies.

```bash
apt install -y curl
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 20
```

NVM automatically adds itself to `~/.bashrc`, so it persists across sessions.

---

## Step 5 — Install Claude Code

```bash
npm install -g @anthropic-ai/claude-code
```

You should see `Checksums matched!` confirming the native binary downloaded.

Verify:
```bash
claude --version
# Expected: 2.1.177 (Claude Code)
```

---

## Step 6 — Authenticate

```bash
claude
```

When the login URL appears:
- Press `c` to copy it (or read it from the screen)
- Open it in your Android browser
- Log in with your Claude account
- Return to Termux — you are now authenticated

---

## Step 7 — Fix PATH and Clean Up (one-time)

Run the built-in diagnostics:
```
/doctor
```

Press `f` to let Claude auto-fix the two issues it finds:

1. **`~/.local/bin` not in PATH** — adds `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc`
2. **Leftover npm installation** — runs `npm -g uninstall @anthropic-ai/claude-code` to remove the duplicate

After fixes are applied, exit and re-login to pick up the PATH change:
```bash
exit                        # leave Ubuntu
proot-distro login ubuntu   # re-enter
which claude                # should show /root/.local/bin/claude
```

---

## Daily Workflow

Every time you want to use Claude Code on your Android:

```bash
# In Termux:
proot-distro login ubuntu

# Inside Ubuntu:
claude
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `linux-arm64-android are not available` | Android detected instead of Linux | Use proot-distro Ubuntu (this runbook) |
| `has unexpected e_type: 2` | Non-PIE binary rejected by Android | Use proot-distro Ubuntu (this runbook) |
| `Cannot find module '.../glob/dist/cjs/src/index.js'` | Ubuntu system Node.js too old | Use NVM (Step 4) instead of `apt install nodejs` |
| `claude: command not found` after re-login | NVM not sourced | Run: `source ~/.bashrc` |
| `which claude` shows Termux path | Old PATH in current session | Exit and re-login to Ubuntu |

---

## What Does NOT Work (and Why)

- **Direct Termux install** (`npm install -g @anthropic-ai/claude-code`): installer detects `linux-arm64-android`, refuses to download binary
- **Force-installing the ARM64 musl binary**: binary is non-PIE (`ET_EXEC`), Android dynamic linker rejects it with `unexpected e_type: 2`
- **Setting `ANTHROPIC_CLAUDE_CODE_PLATFORM` env var**: the install script ignores it
- **Ubuntu system Node.js** (`apt install nodejs`): installs glob v7 which lacks `dist/cjs/src/` structure required by Claude Code
