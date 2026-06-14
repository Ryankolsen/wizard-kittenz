# Browser MCP setup (Claude Code)

> In practice you don't run most of this yourself — you ask Claude and it runs
> the terminal commands for you. The only steps that truly need *you* are the
> ones in Chrome (installing the extension, clicking Connect) and restarting
> Claude Code.

Each step is marked **[You]** (manual — browser/GUI) or **[Ask Claude]**
(Claude can run it for you in the terminal).

## Prerequisites
- Claude Code installed and working in your terminal
- Google Chrome (or a supported Chromium browser)
- Node.js for `npx` — **[Ask Claude]** "check my node version" (runs `node --version`)

## Step 1 — Install the Chrome extension · **[You]**
1. Go to https://browsermcp.io → **Install extension** (opens the Chrome Web Store listing for "Browser MCP").
2. Add to Chrome, then pin it (puzzle-piece icon → pin) so Connect is one click away.

*This one is unavoidably manual — Claude can't install a browser extension for you.*

## Step 2 — Register the MCP server · **[Ask Claude]**
Just ask Claude: *"add the Browser MCP server to my user config."* It runs:

```
claude mcp add browsermcp -s user -- npx @browsermcp/mcp@latest
```

- `-s user` → available in all your projects. Use `-s local` to scope it to just this project.
- Then ask *"list my MCP servers"* → Claude runs `claude mcp list` and confirms `browsermcp ... ✓ Connected`.

## Step 3 — Restart Claude Code · **[You]**
MCP tools load at startup, so quit and reopen your Claude Code session. (You can
check the loaded servers anytime with the `/mcp` command.)

## Step 4 — Connect a tab · **[You]**
1. Open the page you want Claude to work with (e.g. your local site).
2. Click the Browser MCP extension icon **in that tab**.
3. Click **Connect**. That tab is now controllable.

## Step 5 — Try it · **[Ask Claude]**
> Open http://localhost and take a screenshot, then tell me if the header looks right.

Claude drives the connected tab and reports back.

## Good to know (what actually happens)
- **One tab at a time.** Connecting a different tab switches control; the old one disconnects.
- **It drives your real, visible tab** — expect it to navigate while Claude works. Use a dedicated window if you don't want it touching your main browsing.
- **It reuses your session** — whatever you're logged into (admin, etc.) Claude inherits. No separate login, and locally-trusted HTTPS certs work.
- **First run is slow** — `npx @browsermcp/mcp@latest` downloads the package the first time.
- **Disconnects happen** — if tools stop responding, re-click **Connect** in the tab; if they vanish entirely, restart Claude Code.
- **Security** — it's a third-party extension handing an AI control of a browser tab. Use it on sites you trust (local/dev), and disconnect when done.
