# Roadmap

## Milestone 1: browse, inspect, detect (read-only)

- Browse and search the bundled catalog, refreshed from SkillsFlow in the background
- Home: Featured, Trending, Popular, Recently Added; categories; Skills and Plugins
- Detail pages with the security view and every file, viewable before install
- Detect installed skills (`~/.claude/skills/` and added project folders) and plugins (`claude plugin list`)
- Guided setup when Claude Code isn't installed

## Milestone 2: install, update, uninstall

- Review sheet before every install: all files, security findings, what runs automatically
- Skills that belong to a plugin install that plugin, with a notice that says so and why
- Standalone skills copy into `~/.claude/skills/<name>/` with a receipt; on a name collision the user chooses to cancel or install under another name
- Plugins install through `claude plugin` at user scope
- Progress, cancel, update detection, adopt existing skill folders

## Milestone 3: polish and release

- Updates badge, menu commands, help, localization
- Sparkle self-updates, notarized releases

## Later (v2)

- Let the user choose between installing a skill's plugin and copying just the skill. In v1 a skill that belongs to a plugin always installs the plugin, so the skill's dependencies come with it.
- Install plugins at project or local scope (`claude plugin install --scope project|local`) for the project folders the user adds, and manage plugins already installed at those scopes. In v1 the app installs at user scope and shows project and local installs read-only.
