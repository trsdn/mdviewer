# Third-party notices

MDViewer 2.1.0 bundles the following third-party
software. Every asset is vendored from the pinned upstream release listed
below by `scripts/vendor_web_assets.mjs`; nothing is downloaded at runtime.

`common` assets ship in both editions. `lite` assets ship only in MDViewer
Lite. `full` assets ship only in MDViewer Full and are physically absent
from Lite artifacts.

| Package | Version | License | Edition | Bundled bytes |
| --- | --- | --- | --- | --- |
| [marked](https://github.com/markedjs/marked) | 18.0.9 | MIT | common | 46,763 |
| [dompurify](https://github.com/cure53/DOMPurify) | 3.4.12 | Apache-2.0 OR MPL-2.0 | common | 57,293 |
| [marked-footnote](https://github.com/bent10/marked-extensions/tree/main/packages/footnote) | 1.4.0 | MIT | common | 4,091 |
| [prismjs](https://github.com/PrismJS/prism) | 1.30.0 | MIT | lite | 11,126 |
| [@highlightjs/cdn-assets](https://github.com/highlightjs/highlight.js) | 11.11.1 | BSD-3-Clause | full | 128,908 |
| [js-yaml](https://github.com/nodeca/js-yaml) | 5.2.3 | MIT | full | 115,694 |
| [mermaid](https://github.com/mermaid-js/mermaid) | 11.16.0 | MIT | full | 3,687,143 |
| [svg-pan-zoom](https://github.com/bumbu/svg-pan-zoom) | 3.6.2 | BSD-2-Clause | full | 31,106 |

## Assets and checksums

### marked 18.0.9 (common)

- License: MIT
- Source: https://github.com/markedjs/marked/releases/tag/v18.0.9
- Note: Retained browser distribution shipped since MDViewer 1.0. The exact build is committed to this repository and pinned by SHA-256 rather than refetched, so vendoring never silently changes the parser.

| File | SHA-256 |
| --- | --- |
| `MDViewer/Resources/MARKED-LICENSE.txt` | `8e3a3f82f59a60958f56ca08f445647c32a4733dc7ca6c2c46f6eb898471ab9c` |
| `MDViewer/Resources/marked.umd.js` | `ba65f1c8948e6b01321399800843e9048b31e1c197652d4b0fafae840b30e32b` |

### dompurify 3.4.12 (common)

- License: Apache-2.0 OR MPL-2.0
- Source: https://registry.npmjs.org/dompurify/-/dompurify-3.4.12.tgz

| File | SHA-256 |
| --- | --- |
| `MDViewer/Resources/DOMPURIFY-APACHE-LICENSE.txt` | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `MDViewer/Resources/DOMPURIFY-MPL-LICENSE.txt` | `fab3dd6bdab226f1c08630b1dd917e11fcb4ec5e1e020e2c16f83a0a13863e85` |
| `MDViewer/Resources/dompurify.min.js` | `c45ba939765574f96cbf35ee9b6d89f73756a17921814425e74b82f7c54603ce` |

### marked-footnote 1.4.0 (common)

- License: MIT
- Source: https://registry.npmjs.org/marked-footnote/-/marked-footnote-1.4.0.tgz

| File | SHA-256 |
| --- | --- |
| `MDViewer/Resources/MARKED-FOOTNOTE-LICENSE.txt` | `9359f7399b808813111a91c5d28656d5843d8f6d337168541938286dbf273a32` |
| `MDViewer/Resources/marked-footnote.umd.js` | `3ff8fd955edbe6a76eaae32ec8628caf29dbb103cfe6743654090153b833dcec` |

### prismjs 1.30.0 (lite)

- License: MIT
- Source: https://registry.npmjs.org/prismjs/-/prismjs-1.30.0.tgz
- Note: Custom build: Prism core plus compact MDViewer grammars for HTML, CSS, JavaScript, TypeScript, JSON, Bash, Python, Rust, Swift (under 10 KB minified).

| File | SHA-256 |
| --- | --- |
| `MDViewer/LiteResources/PRISM-LICENSE.txt` | `2b947f0901a7ffcf08a89957da9783c0e9c6e72cb6ce8e959f501ab5409e4d2b` |
| `MDViewer/LiteResources/prism.min.js` | `6bfa17723fe5c4e250fac74171ca12c7f4f15de16536a99eb89d39006fddd293` |

### @highlightjs/cdn-assets 11.11.1 (full)

- License: BSD-3-Clause
- Source: https://registry.npmjs.org/@highlightjs/cdn-assets/-/cdn-assets-11.11.1.tgz
- Note: ESM common build, lazily imported only when code fences exist.

| File | SHA-256 |
| --- | --- |
| `MDViewer/FullResources/HIGHLIGHTJS-LICENSE.txt` | `6c081431591d9df696c82dc598fe1423765b8a299b200ed00b281afd0f64c490` |
| `MDViewer/FullResources/WebModules/highlight/highlight.min.mjs` | `7865839949f0764d9e0a21e311a4e2c42633eeaee8ca5ec127b86438565731fe` |

### js-yaml 5.2.3 (full)

- License: MIT
- Source: https://registry.npmjs.org/js-yaml/-/js-yaml-5.2.3.tgz
- Note: ESM build, lazily imported only for a valid frontmatter delimiter.

| File | SHA-256 |
| --- | --- |
| `MDViewer/FullResources/JS-YAML-LICENSE.txt` | `a07bc24468b9654ce76a547d47a2db282d07733b715db4c73a98bd63961f9550` |
| `MDViewer/FullResources/WebModules/js-yaml/js-yaml.mjs` | `4c743c6486a71faa2cad75390173ab9a582283d8e2c108b9c17eae6de905df6b` |

### mermaid 11.16.0 (full)

- License: MIT
- Source: https://registry.npmjs.org/mermaid/-/mermaid-11.16.0.tgz
- Note: Official modular ESM distribution (minified entry plus every diagram chunk) so all supported diagram types render offline. The generated transitive notice file covers the complete installed dependency closure.
- Transitive dependency closure: 104 pinned packages; exact names, versions, licenses, and sources are recorded in `third-party/manifest.json` and their license texts are bundled in `MDViewer/FullResources/MERMAID-TRANSITIVE-NOTICES.txt`.

106 files, 3,687,143 bytes.
Per-file SHA-256 checksums are recorded in `third-party/manifest.json`.

### svg-pan-zoom 3.6.2 (full)

- License: BSD-2-Clause
- Source: https://registry.npmjs.org/svg-pan-zoom/-/svg-pan-zoom-3.6.2.tgz
- Note: Lazily imported only after a diagram renders successfully.

| File | SHA-256 |
| --- | --- |
| `MDViewer/FullResources/SVG-PAN-ZOOM-LICENSE.txt` | `a4fbaf0b818914459316cb22e1a9d01e0f8786fc10cfe355077cca048daa028a` |
| `MDViewer/FullResources/WebModules/svg-pan-zoom/svg-pan-zoom.min.js` | `9c8fc41b3359e699990766dd7a943595d234a80c880a90dfc14b920a273b99d8` |

Regenerate this file with `./scripts/vendor_web_assets.sh` and verify it in
CI with `./scripts/vendor_web_assets.sh --check`.
