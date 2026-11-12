# Contributing

Thanks for looking. A few things that keep KiteLink what it is:

- Read [docs/DESIGN.md](docs/DESIGN.md) first. A change to the main window has to make *import* or *pick* better;
  anything else belongs in Settings, a sheet or the Console.
- Logic that is not UI goes in `packages/KiteKit` with a test (`swift test`), so the next platform gets it for free.
- The macOS project is generated: edit `macos/project.yml`, never the `.xcodeproj`.
- To change the bundled core, update `core/mihomo.version` (tag, asset name, sha256 of the unpacked binary).
- Test against a throwaway data folder: `KITELINK_HOME=/tmp/kl ./macos/build/KiteLink.app/Contents/MacOS/KiteLink`.
  `docs/sample-profile.yaml` runs without a subscription.
- Never commit a real subscription link, node list or screenshot of one.

New platforms live in their own top-level directory and follow the same design notes, file layout and override
format.
