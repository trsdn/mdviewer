# Changelog

## 2.1.0

- Added an optional, collapsed-by-default Folder Navigator to Lite and Full.
- Added read-only ancestor-folder authorization, lazy direct-child loading,
  current-file reveal, and loaded-directory-only filesystem refresh.
- Added `Cmd-Shift-B`, **File > Open Folder…**, a toolbar toggle, accessible
  tree controls, and explicit unavailable, empty, loading, and truncation states.
- Bounded navigation to 12 levels, 500 children per directory, 5,000 loaded
  nodes, and a 1 MiB native tree response.
- Hardened navigation with component-wise canonical confinement and symlink,
  hidden-item, package, and unsupported-file rejection.
