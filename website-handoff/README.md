# JZB Apps static handoff

Prepared locally for **https://jzbapps.com/apps/icue-memory-guard/**. This handoff does not deploy or modify the live site.

## Upload

Copy `dist/apps/icue-memory-guard/` to the site's `/apps/icue-memory-guard/` directory. It contains the page and all of its assets. Keep its relative `assets/` directory intact. No build, server-side code or package installation is required.

All downloads and source links point directly to GitHub. Do not upload installers, checksums, certificates, source archives or modified vendor files to the site.

The installer URL is:

```text
https://github.com/jb14813/iCUE-Memory-Guard/releases/download/v0.1.0/iCUEMemoryGuard-Setup-0.1.0.exe
```

The release URL is:

```text
https://github.com/jb14813/iCUE-Memory-Guard/releases/tag/v0.1.0
```

Before upload, confirm that the public release assets and `main` documentation links resolve. Test the final page at desktop and mobile sizes, including its navigation, theme toggle and FAQ controls. Confirm that every download still goes to GitHub.

## Apps listing

Insert the `app-card.html` fragment alongside the existing app rows on `/apps/` and, if desired, the homepage. It uses the established site classes and links to the new page. Add an **iCUE Memory Guard** link to the existing Projects footer using `/apps/icue-memory-guard/`. Preserve other pages and links.

If the site is generated, add this page and card to its source/templates so a later build retains them. The handoff is a static addition; it does not require a framework or a website download proxy.

## Design and assets

The page uses the established JZB Apps monogram, wordmark, Manrope typeface, navy `#193148`, blue `#2859df`, white `#ffffff` and pale blue `#f5f8fc`, with the existing dark theme. A split introduction places the experimental warning and download beside the tested file pair; subsequent sections cover recovery, update behavior and finite validation. Content stays left-aligned and the layout becomes one column on mobile.

JZB site styles and scripts are included under this page's own `assets/` directory to avoid replacing shared site files. The font license is included there as `Manrope-LICENSE.txt`. The theme toggle has a synchronized accessible label; no analytics or external runtime is added. Existing theme preference uses the `jzb-theme` local-storage key.
