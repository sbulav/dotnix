# Corporate proxy topology, shared by the Claude Code and opencode wrappers.
# External SaaS (api.anthropic.com, api.openai.com, github.com, ...) is only
# reachable through fwdproxy; internal gateways, work infra, and the homelab
# must be reached directly. Both wrappers --set these so spawned subagents
# inherit a correct env no matter which tool dispatched them.
{
  httpProxy = "http://fwdproxy.pyn.ru:4443";
  # Dotless entries match the domain and all subdomains in curl, Go (kubectl),
  # and Node/Bun alike; leading-dot forms are subdomain-only in Go.
  noProxy = "localhost,127.0.0.1,::1,pyn.ru,hhdev.ru,hh.ru,sbulav.ru";
  # The homelab sing-box mixed inbound (SOCKS5+HTTP) on zanoza, fronting the
  # VLESS+REALITY exits with automatic failover. fwdproxy stalls CONNECT
  # chatgpt.com and direct chatgpt.com is Cloudflare-challenged from this
  # network, so the Codex limits collector routes its codex app-server child
  # through here instead; socks5h so DNS resolves at the exit.
  vlessProxy = "socks5h://192.168.89.207:20170";
}
