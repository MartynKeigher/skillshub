# SkillsHub

A native macOS app store for [Claude Skills](https://code.claude.com/docs/en/skills) and [Claude Code plugins](https://code.claude.com/docs/en/plugins/overview). Browse and search thousands of skills and plugins, see exactly what each one contains and what it runs before you install it, and keep track of what's installed.

SkillsHub is modeled on [CaskHub](https://github.com/alielsokary/CaskHub), the SwiftUI app store for Homebrew casks. Its architecture is the template for this app.

## Status

Milestone 1, read-only: browsing, detail pages with the security view and every file, and detection of what's installed. Installing, updating and uninstalling come in milestone 2. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Features

### Discover

- **Home**: featured picks, trending, popular and recently added shelves, and categories
- **Search** across names, descriptions, authors, repositories and tags, with filters for kind, risk and source
- **Grid and list views**, light, dark and system themes

### Inspect before installing

- **Security first**: every item shows its risk level, findings grouped by rule, and for plugins, the exact commands its hooks, MCP and LSP servers, monitors and mods run once enabled
- **Every file, readable**: browse the item's files at the indexed commit, with findings marked on the lines they're on. Each file is checked against the hash in the catalog.
- **Who made it**: made by Anthropic, listed in Anthropic's marketplace, or community. Being in Anthropic's marketplace doesn't mean Anthropic made or reviewed it, and SkillsHub says so.

### Installed

- Skills in `~/.claude/skills` and in project folders you add
- Plugins as `claude plugin list` reports them
- Skill folders that match a catalog skill, and ones that don't

## How it works

SkillsHub talks to Claude Code the way CaskHub talks to Homebrew:

1. **The catalog** comes from [SkillsFlow](https://github.com/MartynKeigher/skillsflow), which crawls skill repositories and plugin marketplaces daily, scans every file, and publishes the result. A copy ships inside the app, so it opens instantly and works offline, and it refreshes in the background.
2. **Installed state** is read from where Claude Code keeps it: skill folders on disk and the `claude` CLI. SkillsHub keeps no separate record of what's installed.
3. **Installs** (milestone 2) will run through the real `claude plugin` commands, or copy a skill folder at the indexed commit with a small receipt inside it, so everything matches the terminal.

Browsing works without Claude Code. If it isn't installed, SkillsHub shows how to set it up.

## Requirements

- macOS 15.6 or later
- [Claude Code](https://code.claude.com/docs/en/setup) 2.1.268 or later, to see installed plugins (browsing works without it)

## Architecture

- **SwiftUI + MVVM** with `@Observable` view models and `@MainActor` isolation, as in CaskHub
- **`Packages/SkillsHubCore`**: the catalog models, queries and services, Foundation-only and protocol-based so they can be tested with stand-ins. `IndexClient` takes the place of CaskHub's `BrewAPIClient`, and `LocalSkillsService` of its `LocalHomebrewService`.
- **No third-party dependencies** yet. Sparkle for self-updates will come later.

## Building

You need Xcode 26 or later.

```bash
git clone https://github.com/MartynKeigher/skillshub.git
```

```bash
open skillshub/SkillsHub.xcodeproj
```

Run the **SkillsHub** scheme (⌘R). To test:

```bash
xcodebuild -project SkillsHub.xcodeproj -scheme SkillsHub -destination 'platform=macOS' test
```

```bash
cd Packages/SkillsHubCore && swift test
```

The core package's tests also run on Linux. Before a release, refresh the bundled catalog:

```bash
./Scripts/update_bundled_catalog.sh
```

## Acknowledgements

- [CaskHub](https://github.com/alielsokary/CaskHub) by Ali Elsokary: the app this one is modeled on. Files adapted from it say so in their header, and its MIT notice is in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- [SkillsFlow](https://github.com/MartynKeigher/skillsflow): the catalog pipeline behind SkillsHub, modeled on CaskHub's CaskFlow

## License

MIT. See [LICENSE](LICENSE).
