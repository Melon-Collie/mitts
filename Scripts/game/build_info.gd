extends Node

# Build version, baked in at export time. Local editor runs stay as "dev" so
# the update notifier skips its network check. The deploy workflow (.github/
# workflows/deploy.yml) rewrites VERSION to "0.1.<git rev-list --count HEAD>"
# before running the Godot export, and passes the same string as the GitHub
# Release name so the notifier can compare against it.

const VERSION: String = "dev"

const RELEASE_TAG: String = "latest"
const REPO: String = "melon-collie/hockey-game"
