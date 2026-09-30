# Digest — D2 paradigms — round 2 — assistant 1
Accessed: 2026-09-30

Budget used: 5 sources fetched and read (Tailscale KB 1153, Tailscale KB 1312,
PP forum thread 27334, Wealthfolio mobile guide, Wealthfolio Connect guide); one
further fetch failed (AppBrain, HTTP 403) and is not counted as read. 20 tool
calls including this write. Every claim not backed by one of the five fetched
pages rests on a search-engine extract and is graded down accordingly.

Freshness treatment: the two Tailscale KB pages are the pages Tailscale serves
today, but their "last validated" stamps (2025-12-10, 2026-01-20) are older than
the 3-month feature bar. They are recorded as stale-by-bar with medium
confidence rather than discarded. The PP forum announcement (2024-02-21) is
stale and is used only as launch-state evidence for the verification items.

## Claims
| # | claim | source URL | publisher | pub_date (YYYY-MM[-DD] or "undated") | confidence (high/medium/low) | class (capability/pricing/positioning/sentiment/traction/trajectory) |
|---|---|---|---|---|---|---|
| 1 | Tailscale can obtain Let's Encrypt TLS certificates for tailnet machines under their `*.ts.net` names, completing the DNS-01 challenge through a TXT record Tailscale creates (`tailscale cert`). | https://tailscale.com/kb/1153/enabling-https | Tailscale (official KB) | 2025-12-10 (last validated; live page, stale by 3-month bar) | medium | capability |
| 2 | HTTPS certificates are switched on in the admin console's DNS page and require MagicDNS to be enabled first. | https://tailscale.com/kb/1153/enabling-https | Tailscale (official KB) | 2025-12-10 (stale by bar) | medium | capability |
| 3 | Tailscale warns that issued certificates publish the devices' fully qualified names in public Certificate Transparency logs, and says "Do not enable the HTTPS feature if any of your machine names contain sensitive information." | https://tailscale.com/kb/1153/enabling-https | Tailscale (official KB) | 2025-12-10 (stale by bar) | medium | capability |
| 4 | These certificates expire after 90 days; when delivered as files on disk the user is responsible for renewal, while Tailscale's Caddy integration renews automatically. | https://tailscale.com/kb/1153/enabling-https | Tailscale (official KB) | 2025-12-10 (stale by bar) | medium | capability |
| 5 | Tailscale Serve routes traffic from other devices on the tailnet to a local service and shares it only with the tailnet, while Funnel is the variant that makes a service public. | https://tailscale.com/kb/1312/serve | Tailscale (official KB) | 2026-01-20 (last validated; stale by bar) | medium | capability |
| 6 | Once HTTPS certificates are enabled for the tailnet, Serve automatically provisions TLS certificates for the machine's tailnet DNS name. | https://tailscale.com/kb/1312/serve | Tailscale (official KB) | 2026-01-20 (stale by bar) | medium | capability |
| 7 | Serve works as a reverse proxy to a local HTTP port; the documented example `tailscale serve 3000` proxies to `http://127.0.0.1:3000`. | https://tailscale.com/kb/1312/serve | Tailscale (official KB) | 2026-01-20 (stale by bar) | medium | capability |
| 8 | Serve adds the identity headers `Tailscale-User-Login`, `Tailscale-User-Name` and `Tailscale-User-Profile-Pic` to proxied requests. | https://tailscale.com/kb/1312/serve | Tailscale (official KB) | 2026-01-20 (stale by bar) | medium | capability |
| 9 | Serve's clients must be on the tailnet, and its DNS names are restricted to the tailnet's own domain name. | https://tailscale.com/kb/1312/serve | Tailscale (official KB) | 2026-01-20 (stale by bar) | medium | capability |
| 10 | Immich's official remote-access guide presents a VPN (WireGuard/OpenVPN), Tailscale and a reverse proxy as the options, and calls Tailscale a good option if you cannot open a port on your router because it mediates a peer-to-peer WireGuard tunnel even behind NAT. | https://docs.immich.app/guides/remote-access/ | Immich (official docs) | undated, accessed 2026-09-30 (search-engine extract; page not fetched) | medium | positioning |
| 11 | The same guide lists Tailscale's advantages as minimal configuration and protection against zero-day vulnerabilities in Immich, and its drawbacks as a client that usually runs as root, a paid service with a free tier for personal use, and the need to run it on both server and client. | https://docs.immich.app/guides/remote-access/ | Immich (official docs) | undated, accessed 2026-09-30 (search-engine extract) | medium | positioning |
| 12 | Open WebUI's official docs carry pages titled "HTTPS using Tailscale" and "Use it from your phone", autobrr's docs carry a "tailscale serve" reverse-proxy installation page, and Dashy's docs carry a Tailscale authentication page. | https://docs.openwebui.com/reference/https/tailscale.md ; https://docs.openwebui.com/ecosystem/computer/phone-and-remote.md ; https://autobrr.com/installation/reverse-proxy/tailscale-serve ; https://dashy.to/docs/authentication/tailscale | Open WebUI; autobrr; Dashy (official docs) | undated (titles in search results only) | low | positioning |
| 13 | PP's maintainer announced the mobile app on 2024-02-21 as "a mobile companion to the desktop application" that reads the same data files, adding "You cannot (yet) make changes in the app". | https://forum.portfolio-performance.info/t/portfolio-performance-app-the-first-version/27334 | Portfolio Performance forum (post by maintainer AndreasB) | 2024-02-21 (stale; launch-state evidence) | high | capability |
| 14 | The announcement states "All calculations are performed solely on your device." | https://forum.portfolio-performance.info/t/portfolio-performance-app-the-first-version/27334 | Portfolio Performance forum | 2024-02-21 (stale) | high | capability |
| 15 | The announcement tells users to "Store your file in binary format on a cloud storage service, e.g., iCloud, Google Drive, OneDrive", and names no Dropbox, WebDAV or Nextcloud option and no server. | https://forum.portfolio-performance.info/t/portfolio-performance-app-the-first-version/27334 | Portfolio Performance forum | 2024-02-21 (stale) | high | capability |
| 16 | The announcement says the statement of assets, performance calculations, charts and earnings are free, and "using the dashboards requires a subscription". | https://forum.portfolio-performance.info/t/portfolio-performance-app-the-first-version/27334 | Portfolio Performance forum | 2024-02-21 (stale) | high | pricing |
| 17 | Vendor release text for Android version 1.2, as mirrored by APKMirror, adds opening files directly from OneDrive, Dropbox, Google Drive and WebDAV, plus support for 29 of the 46 desktop dashboard widgets. | https://www.apkmirror.com/?p=7045076 | APKMirror (copy of vendor Play text) | undated (search-engine extract; not fetched) | low | capability |
| 18 | The store description as surfaced by search says Premium unlocks viewing all desktop dashboards and creating and editing mobile dashboards, that transactions are edited and maintained on the desktop, and that a password-protected file is AES-256 encrypted. | https://apkmirror.com/apk/msm-mannheimer-software-manufaktur-ug/portfolio-performance ; https://www.appbrain.com/app/portfolio-performance/software.msm.portfolio_performance | APKMirror; AppBrain (copies of vendor text) | undated (search-engine extract) | low | pricing |
| 19 | An Android app directory lists the app (package `software.msm.portfolio_performance`, developer MSM Mannheimer Software-Manufaktur UG) at version 1.13.0, last updated July 8, 2026. | https://www.appbrain.com/app/portfolio-performance/software.msm.portfolio_performance | AppBrain | 2026-07-08 (from a search-engine summary citing this page; direct fetch returned HTTP 403) | medium | trajectory |
| 20 | Wealthfolio's mobile guide says "Each iOS device runs its own SQLite database in the app's sandbox storage." | https://wealthfolio.app/docs/guide/mobile/ | Wealthfolio (official docs) | 2026-09-30 (last updated) | high | capability |
| 21 | The mobile guide says changes flow between devices as end-to-end-encrypted blobs through Wealthfolio Connect, and documents no direct sync path between the phone and a self-hosted server. | https://wealthfolio.app/docs/guide/mobile/ | Wealthfolio (official docs) | 2026-09-30 | medium (fetch-summary paraphrase plus absence) | capability |
| 22 | The mobile guide says "There's no native Android app yet. It's planned". | https://wealthfolio.app/docs/guide/mobile/ | Wealthfolio (official docs) | 2026-09-30 | high | trajectory |
| 23 | The mobile guide presents a self-hosted instance as usable in a phone's browser as a Progressive Web App, separate from device sync. | https://wealthfolio.app/docs/guide/mobile/ | Wealthfolio (official docs) | 2026-09-30 | medium (paraphrase; no verbatim quote captured) | capability |
| 24 | Wealthfolio's Connect guide lists self-hosted instances as sync peers: "Sign into Connect on each device (desktop, iOS, self-hosted)." | https://wealthfolio.app/docs/guide/connect-broker-sync/ | Wealthfolio (official docs) | 2026-09-30 | high | capability |
| 25 | The Connect guide says changes are "encrypted on-device with your account key and pushed to Connect's storage tier. We can't read the encrypted blobs." and "E2E means we cannot recover your portfolio for you." | https://wealthfolio.app/docs/guide/connect-broker-sync/ | Wealthfolio (official docs) | 2026-09-30 | high | capability |
| 26 | The Connect guide names no plan, price or device limit and points to wealthfolio.app/connect to subscribe. | https://wealthfolio.app/docs/guide/connect-broker-sync/ | Wealthfolio (official docs) | 2026-09-30 | high | pricing |
| 27 | Wealthfolio's FAQ and self-hosting pages, as extracted by search, say Connect is optional and only needed for broker sync via SnapTrade or end-to-end-encrypted device sync, and that self-hosting with manual imports needs nothing else. | https://wealthfolio.app/docs/faq/ ; https://wealthfolio.app/docs/guide/self-hosting/ | Wealthfolio (official docs) | undated (search-engine extract; not fetched) | medium | positioning |
| 28 | An unaffiliated GitHub project, wealthfolio-connect-self-hosted, describes itself as a self-hosted companion server for the Wealthfolio web edition "for users who can't or won't use a hosted sync service", not endorsed by the Wealthfolio team. | https://github.com/festivities/wealthfolio-connect-self-hosted | GitHub (festivities) | undated (search-engine extract) | low | traction |
| 29 | Cloudflare says its Access service verifies user access to applications against Zero Trust policies such as identity and device posture, and can force self-hosted apps into an isolated remote browser without installing its client. | https://www.cloudflare.com/it-it/lp/application-isolation-beta/ | Cloudflare (landing page, marketing register) | undated (search-engine extract) | medium | capability |
| 30 | A blog titled "Cloudflare Tunnel and TLS: What Cloudflare Can See" describes two separate encrypted legs, with Cloudflare's edge decrypting the full request — URL, cookies, headers and body including login credentials — before re-encrypting to the origin. | https://pluggie.io/blog/cloudflare-tunnel-tls-privacy | Pluggie (blog; publisher's commercial interest not checked) | undated (search-engine extract; attribution inferred from the summary) | low | capability |
| 31 | The same search summary says edge TLS termination is what makes Cloudflare's DDoS protection, WAF rules, caching and Access policies work, and calls its traffic visibility a significant limitation for GDPR/HIPAA-style data-residency needs. | https://pluggie.io/blog/cloudflare-tunnel-tls-privacy ; https://contabo.com/blog/pangolin-vs-cloudflare-tunnels-vs-tailscale/ | Pluggie; Contabo (VPS vendor blog) | undated (search-engine extract; attribution unclear) | low | positioning |
| 32 | A Nextcloud community-forum reply says a Cloudflare Tunnel implies all TLS connections are decrypted by Cloudflare and exist in plain text on its servers, and advises terminating TLS on your own premises. | https://help.nextcloud.com/t/is-cloudflare-tunnel-safe-privacy-focused/150268 | Nextcloud community forum | date not retrieved (treat as stale) | medium | sentiment |
| 33 | An r/selfhosted thread contrasts Cloudflare Tunnel's TLS termination with Tailscale HTTPS/Funnel, where the certificate is generated locally and signed by Let's Encrypt so no third party holds the private key. | https://nyc1.lr.ggtyler.dev/r/selfhosted/comments/133rr6n/about_cloudflare_tunnels/ | Reddit r/selfhosted (via Redlib mirror) | 2023-04-30 (stale) | low | sentiment |
| 34 | The TLS-termination concern has its own discussion items: a Hacker News "Ask HN: Are you concerned by TLS-terminating proxies like Cloudflare Tunnels?" and an XDA article "I stopped using Cloudflare Tunnels for everything, and here's what I use instead". | https://news.ycombinator.com/item?id=47918989 ; https://www.xda-developers.com/stopped-using-cloudflare-tunnels-for-everything-heres-what-use-instead/ | Hacker News; XDA Developers | dates not retrieved (titles only) | low | sentiment |

## Verification outcomes

### Item 3 — Portfolio Performance mobile app

Independent source checked: PP's own forum announcement by the maintainer
(2024-02-21, fetched). It is a different channel with different underlying
information from the round-1 App Store listing (a launch announcement rather
than store copy), but the same vendor, so independence is partial. Android
directory pages (APKMirror, AppBrain) were reached only through search
extracts; they copy vendor text and are not independent on capability, but
AppBrain's version/date record is Android-side data the App Store listing does
not carry.

| Round-1 claim | Outcome | Claims |
|---|---|---|
| Reads the same data file as the desktop version | verified | #13, #18 |
| Opens it from a cloud drive: iCloud, Google Drive, OneDrive | verified | #15 |
| … and from Dropbox and WebDAV | unverified — vendor-authored text only, consistent across the iOS listing and the Android 1.2 release text | #17 |
| Computes locally | verified | #14 |
| Leaves editing to the desktop | verified for launch ("cannot (yet) make changes"); current store copy still places editing on the desktop | #13, #18 |
| Premium unlocks only dashboards | verified, with a nuance: current store copy adds creating and editing mobile dashboards to Premium | #16, #18 |
| Version "1.13.0, July 9" with no year | verified as version 1.13.0 released July 2026 (Android record 2026-07-08); the exact iOS day and year were not independently re-read | #19 |
| WebDAV usable with Nextcloud or other self-hosted storage | unverified — no source found names Nextcloud; WebDAV itself rests on vendor text | #15, #17 |

Also new: the launch announcement asks for the file in **binary format** (#15),
and the Android listing names the publisher as MSM Mannheimer
Software-Manufaktur UG (#19).

### Item 4 — Wealthfolio

Source checked: Wealthfolio's own docs (mobile guide and Connect guide, both
updated 2026-09-30), as the brief asked. Same vendor as round 1's /connect page,
so this is a docs-versus-marketing check, not an independent publisher.

| Round-1 claim | Outcome | Claims |
|---|---|---|
| Connect gives end-to-end-encrypted sync including self-hosted instances | verified | #24, #25 |
| Plan "Connect Basic", $2.99/month, up to 6 devices | unverified — the docs name no plan, price or device limit | #26 |
| The phone app keeps its own local database | verified | #20 |
| Can the phone sync with a self-hosted instance directly? | only through Connect (a hosted relay storing ciphertext); no direct path documented; the documented non-Connect route is the self-hosted web UI as a PWA in the phone browser | #21, #23, #24 |

Correction to round 1's wording: "the phone app" is iOS only — the docs say
there is no native Android app yet (#22). Conflict note: the fetch summary of the
mobile guide also read "self-hosted sync not supported", which contradicts the
verbatim Connect-guide quote (#24); resolved in favour of the verbatim quote
(same publisher, same date) and read as "no direct phone-to-server sync".

## Patterns: phone access to a self-hosted server
- **Tailnet-only HTTPS is a documented, low-configuration path.** Serve
  auto-provisions a Let's Encrypt certificate for the machine's `*.ts.net` name,
  reverse-proxies a local port, and keeps the service inside the tailnet (#1,
  #2, #5, #6, #7, #9). Its costs: every phone must run Tailscale and join the
  tailnet (#9, #11); machine names become public in Certificate Transparency
  logs (#3); names are fixed to the tailnet domain (#9); and the coordination
  service is itself a hosted, paid-with-free-tier product (#11).
- **Comparable self-hosted apps present Tailscale as one recommended option,
  not the only one**, especially when a router port cannot be opened, and cite
  not exposing the app to zero-days as the gain (#10, #11). Dedicated Tailscale
  pages exist in other apps' docs (#12, titles only). Nothing was found for Home
  Assistant, Paperless-ngx, Vaultwarden or Actual Budget (see below).
- **The one comparable portfolio app answers with a hosted end-to-end-encrypted
  relay, not with phone-to-server access.** In Wealthfolio the self-hosted
  server and the iOS app are peers that each hold a full local database and sync
  ciphertext through Connect (#20, #21, #24, #25); the self-hosted web UI as a
  mobile PWA is the only documented route without Connect (#23); a third-party
  project re-implements the relay for self-hosting, a demand signal (#28).
- **PP's status quo needs no server and no VPN at all:** a file on a consumer
  cloud drive, a read-only phone companion computing locally, dashboards paid
  (#13, #14, #15, #16, #18). A self-hosted server asks this user for an extra
  step — a VPN app on the phone or a third party in the path — that the status
  quo does not.
- **Cloudflare Tunnel plus Access removes the VPN app and adds an identity gate
  (#29), at the price of TLS terminating at Cloudflare**, which can then read
  requests in plain text, credentials included (#30, #31, #32, #33). Community
  voices treat this as the decisive objection for private data (#32, #33, #34),
  but every sentiment source here is stale or undated.
- **Unverified belief, not evidenced this run:** a Cloudflare setup is a
  `cloudflared` connector on the host dialing out to Cloudflare, a public
  hostname on a Cloudflare-managed domain routed to the local port, and an Access
  application with an identity policy in front of it. Cloudflare's own setup docs
  were not read.
- **Not evidenced either way:** whether a PWA installed from a Serve `*.ts.net`
  URL works normally on iOS Safari and Android Chrome, and how iOS's VPN slot,
  battery use and offline behaviour affect it.

## Leads worth chasing
- Tailscale's newer docs tree (search surfaced
  https://tailscale.com/docs/how-to/set-up-https-certificates.md): re-validate
  #1–#9 inside the 3-month bar and find the iOS VPN-coexistence, battery and
  VPN On Demand pages.
- A doc or test of installing a PWA from a Serve URL on iOS Safari and Android
  Chrome; Open WebUI's "Use it from your phone" page (#12) is the nearest
  candidate.
- Serve's identity headers (#8) as an app-level sign-in inside the tailnet:
  check Tailscale's guidance on when those headers can be trusted.
- Headscale (self-hosted Tailscale control server; search surfaced its
  Apple-client docs) for a variant with no hosted coordination service.
- Pangolin (surfaced by the Contabo comparison, #31) as a self-hostable tunnel
  where TLS terminates on the operator's own VPS instead of at Cloudflare.
- Cloudflare's own Tunnel and Access setup docs and the Zero Trust free-tier
  limits (an SEO article title claims "Free vs $7/User [2026]" — unverified).
- Wealthfolio: re-read /connect for the $2.99 and 6-device figures; check the
  third-party relay's (#28) stars and activity as a traction measure.
- PP: the Google Play listing for `software.msm.portfolio_performance`
  ("What's new" for 1.13.0) and a PP forum search for WebDAV/Nextcloud user
  reports.
- Fetch the Immich guide (#10, #11) for verbatim wording; check the Home
  Assistant, Paperless-ngx, Vaultwarden and Actual Budget docs.

## Looked for, could not find
- Any official or community statement that a PWA installed from a Tailscale
  Serve URL works on iOS Safari or Android Chrome; only generic "Add to Home
  Screen" instructions surfaced.
- Tailscale statements on iOS allowing one active VPN, on battery impact, or on
  offline behaviour — not on the two KB pages read.
- Actual Budget official docs recommending Tailscale — only a personal blog
  (https://stfn.pl/blog/75-actual-budget-lxc/) and an Armbian docs page surfaced.
- Wealthfolio docs stating Connect's price, plan name or device limit (#26).
- Any PP source naming Nextcloud; any non-vendor confirmation of PP's Dropbox or
  WebDAV support.
- Dated community sentiment within 12 months on Cloudflare Tunnel for sensitive
  data: candidates found (#30, #34) but their dates were not retrieved; the one
  dated item is stale (#33).
- The AppBrain page itself (HTTP 403); #19 rests on a search-engine summary.
