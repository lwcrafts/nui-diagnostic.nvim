# Changelog

## [0.2.0] - 2026-09-24

### Added
- Added syntax highlighting to the diagnostic popup via `extmarks`, utilizing standard Neovim diagnostic highlight groups (e.g., `DiagnosticError`, `DiagnosticWarn`).

### Changed
- **Breaking:** Switched from `nui.nvim` to native Neovim floating windows (`nvim_open_win`) for rendering popups.
- Simplified the diagnostic message format by removing the explicit severity and source text prefixes, relying instead on the new highlighting features for context.
- Hide the `code_action` popup completely when there are no code actions available, instead of displaying "No code actions".

### Removed
- Removed the dependency on `nui.nvim`. The plugin is now dependency-free.

## [0.1.0] - 2026-07-4

### Added
- Initial release of `nui-diagnostic.nvim`.
- Jump between LSP diagnostics and seamlessly show the current diagnostic along with available code actions in a floating popup.
- Configurable severity mappings and max items display.
