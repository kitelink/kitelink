# Design notes

What KiteLink is for, and the decisions that follow from it. Every platform's app should be recognisable from this
page.

## The story

> I got a subscription link from my provider. I want my Mac to use it, and now and then I want to change the node.

That is the whole job for most people, and it is two actions: **import** and **pick**. KiteLink is designed so that
those two are the product and everything else is a drawer you can open.

1. **Import** — first launch is one field. Paste the link, press Return. The profile is named by the provider
   (`content-disposition`), its quota and expiry come from `subscription-userinfo`, its refresh interval from
   `profile-update-interval`. There is nothing to configure before the node list appears.
2. **Pick** — the window is the list: groups on the left with what each is using, the selected group's nodes on the
   right. One click selects. Latency is already there, because a group is tested the first time it is shown.
3. **Leave** — close the window. The kite stays in the menu bar with the switch, the mode and the same node lists.

## Rules

- **The window is the node list.** No dashboard, no home page of cards. Traffic is two numbers in the footer.
- **Set-once things live in Settings**, never in the main window: ports, bypass list, launch at login, User-Agent.
- **Rare things live behind one more click**: profiles (a sheet), overrides (a sheet from there), logs and
  connections (a separate Console window).
- **Nothing is hidden for good.** Whatever a profile can express in mihomo, an override can change, and the generated
  config is a readable file.
- **Leave the Mac as we found it.** System Proxy saves the previous settings of every network service and restores
  them when it is switched off, on quit, and when the core dies. A core left over from a killed run is cleaned up on
  the next start.
- **Say what is wrong in the user's terms.** "Port 7890 is in use by another app. Quit it, or change the port in
  Settings › Proxy.", not a bind error. Background refresh failures stay on the profile row; they do not interrupt.
- **Names are data, not decoration.** The flag column is derived from the node name (flag emoji, ISO code or place
  name); when the system cannot draw a flag, the region code stands in.

## Compatibility

- **Core**: stock mihomo, run as a child process and driven through its external controller
  (`127.0.0.1:<controller port>`, a random secret per launch). The pinned version is in `core/mihomo.version`.
- **Profiles**: Clash / mihomo YAML, as served to Clash Verge Rev. Subscriptions are fetched with a User-Agent that
  starts with `ClashMeta/` — providers decide what to send from the start of that string.
- **Overrides**: the Clash Verge Rev *Merge* keys (`prepend-rules`, `append-rules`, `prepend-proxies`,
  `append-proxies`, `prepend-proxy-groups`, `append-proxy-groups`; any other top-level key replaces the profile's).
  Order: profile → global override → profile override → the keys KiteLink owns.
- **Keys KiteLink owns** (always written last): `mixed-port`, `allow-lan`, `external-controller`, `secret`, `mode`,
  `log-level`, `ipv6`, `unified-delay`, `tcp-concurrent`, `profile.store-selected`; other listeners and
  `external-ui` are removed; `tun.enable` is forced off until the helper exists.
- **Links**: `clash://install-config?url=…`, `clashmeta://…` and `kitelink://install?url=…` open the import sheet
  with the link filled in.

## Files

```
~/Library/Application Support/KiteLink/
  settings.json            app and core settings
  profiles.json            the profile list (name, link, usage, selections per group)
  profiles/<id>.yaml       each profile as the provider sent it
  overrides/global.yaml    overrides/<id>.yaml
  core/config.yaml         generated; what mihomo runs
  core/                    cache.db, geo data, mihomo.pid
  logs/core.log
  system-proxy-before.json present only while System Proxy is on
```

`KITELINK_HOME=/some/dir` points the app at another folder (development, tests).

## Structure

`packages/KiteKit` holds everything that is not UI — `Profile`, `Subscription` (fetch + headers), `ConfigBuilder`
(overrides and owned keys, on Yams nodes so key order survives), `ClashAPI` (REST and websocket streams), `NodeName`
(flag and region from a name), `VergeImport`, `Store`. It builds for macOS and iOS and has the unit tests.

`macos/KiteLink` is the SwiftUI shell: `AppModel` (the one observable object), `CoreProcess`, `SystemProxy`, the
views, and the menu bar extra. Debug builds include a small local HTTP driver (`KITELINK_DEBUG_PORT`) that dispatches
real mouse and key events, used to test the app end to end from a script.

## Next

- Privileged helper → TUN mode, and the system proxy for non-admin users
- Signed, notarised builds and in-app updates
- Share-link subscriptions (base64 lists) converted to a profile
- iOS (Network Extension) on the same KiteKit
