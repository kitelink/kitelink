# KiteLink brand

<p><img src="icon.svg" width="160" alt="App icon"> &nbsp; <img src="mark.svg" width="160" alt="Mark"> &nbsp; <img src="mark-mono-256.png" width="80" alt="Menu bar glyph, on"> <img src="mark-mono-off-256.png" width="80" alt="Menu bar glyph, off"></p>

## Idea

A kite is the simplest way to reach somewhere you cannot go yourself. The mark is the kite itself, whole and already
flying, with one ring where its spars cross: the node, the point everything is linked through. No line, no tail. That
is how the app should feel: light, already flying, nothing to operate — and you pick the node.

**Tagline:** Paste a link, pick a node, fly.

## Mark

A diamond kite's sail with its two spars and a ring where they cross.

- **Shape.** The kite's diamond with the two leading edges bowed out by the wind and the trailing edges full, so it
  reads as cloth under tension rather than a flat rhombus. Top and bottom stay sharp.
- **Spars.** The spine and a bowed cross spar, drawn as thin white lines that stop short of the ring.
- **Node.** A white ring with a rose centre where the spars cross. It is the "Link": the point everything passes
  through, and the thing you pick in the app.
- **Colour.** One sweep across the whole sail, nose to tail: peach, rose, lilac, sky.
- **Tilt.** 16° clockwise: nose up and to the right, climbing.
- **App icon.** The mark on a pale dawn sky inside the macOS rounded square (824/1024).
- **Menu bar glyph.** One colour. On: the sail with the spars and the ring cut out of it. Off: the outline and the ring.

`render.swift` is the source of truth: it draws every size from geometry (no scaling) and writes the Xcode asset
catalog, the PNGs here and both SVGs.

```sh
swift brand/render.swift macos/KiteLink/Assets.xcassets brand
```

## Colour — Dawn

| | Hex | Use |
|---|---|---|
| Peach | `#FFC2B0` | the sail's sweep, at the nose |
| Rose | `#FF8FA8` | the sweep (38%) and the node's centre |
| Lilac | `#B79CFF` | the sweep (68%) |
| Sky | `#6F94FF` | the sweep, at the tail |
| **Dawn Violet** | `#6D74F4` (light) · `#828AFC` (dark) | the accent: selection, switches, primary buttons |
| Dawn sky | `#FFF8F3` → `#FFE3EC` | icon background, top to bottom |

In the apps, everything except the accent follows the system appearance (light and dark). The rose-to-violet sweep
appears only where something is drawn rather than a system control (the quota bar). Latency uses the system green /
orange / red — status colours are never brand colours.

## Type

The system typeface on every platform (SF Pro on Apple platforms). The wordmark is **KiteLink** — one word, capital K
and L — in the system semibold with slightly tight tracking (−0.2 at 14 pt). Numbers that change (latency, traffic,
ports) and protocol tags are monospaced.

## Voice

Plain and short. Say what happened and what to do: "Port 7890 is in use by another app. Quit it, or change the port
in Settings › Proxy." Name things the way the provider and the core do (profile, group, node, rule). No exclamation
marks, no jargon the user did not bring.

## Don'ts

- Don't add a line or a tail to the kite, or split the sail into separate pieces.
- Don't set it upright or mirror it; the tilt is the climb.
- Don't recolour the sweep outside the Dawn palette, or drop the node (one colour is black or white only).
- Don't use the icon's background as a UI colour.
