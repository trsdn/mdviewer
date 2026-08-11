# Lite artifact size baseline

The bundle audit measures the Lite `.app` with `scripts/check_artifact_size.py`.
It creates an in-memory, sorted ZIP with fixed timestamps and compression level
9, so ordinary CI is reproducible and does not download release assets.

`config/artifact-size-baselines.json` records the measurement extracted from
the published v2.0.1 Lite DMG. The audit fails only when the current compressed
measurement exceeds that baseline by both 512 KiB and 2%. Refresh the checked-in
baseline only from a published release of the same platform and package format.

Release targets enable Xcode deployment postprocessing. Xcode therefore strips
the installed executable before its normal CodeSign build step; release scripts
must not strip an already signed bundle. Signed builds retain the configured
entitlements and hardened runtime and are verified after copying to `dist`.
