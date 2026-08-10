#!/usr/bin/env node
// Deterministic vendoring of pinned upstream web assets for MDViewer.
//
// Usage: node scripts/vendor_web_assets.mjs [--check]
//
// Copies only the exact files MDViewer ships, assigns each to an edition
// (common / lite / full), records package, version, source, license and
// SHA-256 in third-party/manifest.json, and regenerates the bundled web
// module allowlist plus the human-readable notices document.
//
// Source maps, tests, TypeScript declarations, package-manager state and
// unrelated modules are never copied.

import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import {
  cp,
  mkdir,
  readFile,
  readdir,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const vendorRoot = path.join(repoRoot, "vendor");
const modulesRoot = path.join(vendorRoot, "node_modules");

const COMMON = path.join(repoRoot, "MDViewer", "Resources");
const LITE = path.join(repoRoot, "MDViewer", "LiteResources");
const FULL = path.join(repoRoot, "MDViewer", "FullResources");
const WEB_MODULES = path.join(FULL, "WebModules");
const MANIFEST = path.join(repoRoot, "third-party", "manifest.json");
const NOTICES = path.join(repoRoot, "docs", "THIRD-PARTY-NOTICES.md");

const checkOnly = process.argv.includes("--check");

/** Languages included in the Lite custom Prism build. */
const PRISM_LANGUAGES = [
  "HTML",
  "CSS",
  "JavaScript",
  "TypeScript",
  "JSON",
  "Bash",
  "Python",
  "Rust",
  "Swift",
];

/**
 * Packages MDViewer vendors. `files` entries are copied verbatim.
 * `edition` decides which resource group physically receives the asset.
 */
const PACKAGES = [
  {
    name: "marked",
    version: "18.0.9",
    license: "MIT",
    source: "https://github.com/markedjs/marked/releases/tag/v18.0.9",
    homepage: "https://github.com/markedjs/marked",
    edition: "common",
    note:
      "Retained browser distribution shipped since MDViewer 1.0. The exact " +
      "build is committed to this repository and pinned by SHA-256 rather " +
      "than refetched, so vendoring never silently changes the parser.",
    retained: [
      {
        at: [COMMON, "marked.umd.js"],
        sha256:
          "ba65f1c8948e6b01321399800843e9048b31e1c197652d4b0fafae840b30e32b",
      },
      {
        at: [COMMON, "MARKED-LICENSE.txt"],
        sha256:
          "8e3a3f82f59a60958f56ca08f445647c32a4733dc7ca6c2c46f6eb898471ab9c",
      },
    ],
  },
  {
    name: "dompurify",
    version: "3.4.12",
    license: "Apache-2.0 OR MPL-2.0",
    source: "https://registry.npmjs.org/dompurify/-/dompurify-3.4.12.tgz",
    homepage: "https://github.com/cure53/DOMPurify",
    edition: "common",
    files: [
      { from: "dompurify/dist/purify.min.js", to: [COMMON, "dompurify.min.js"] },
      { from: "dompurify/LICENSE", to: [COMMON, "DOMPURIFY-APACHE-LICENSE.txt"] },
      {
        from: "dompurify/LICENSE-MPL",
        to: [COMMON, "DOMPURIFY-MPL-LICENSE.txt"],
      },
    ],
  },
  {
    name: "marked-footnote",
    version: "1.4.0",
    license: "MIT",
    source:
      "https://registry.npmjs.org/marked-footnote/-/marked-footnote-1.4.0.tgz",
    homepage:
      "https://github.com/bent10/marked-extensions/tree/main/packages/footnote",
    edition: "common",
    files: [
      {
        from: "marked-footnote/dist/index.umd.js",
        to: [COMMON, "marked-footnote.umd.js"],
      },
    ],
    remote: [
      {
        url: "https://raw.githubusercontent.com/bent10/marked-extensions/main/license",
        to: [COMMON, "MARKED-FOOTNOTE-LICENSE.txt"],
        sha256:
          "9359f7399b808813111a91c5d28656d5843d8f6d337168541938286dbf273a32",
      },
    ],
  },
  {
    name: "prismjs",
    version: "1.30.0",
    license: "MIT",
    source: "https://registry.npmjs.org/prismjs/-/prismjs-1.30.0.tgz",
    homepage: "https://github.com/PrismJS/prism",
    edition: "lite",
    note:
      `Custom build: Prism core plus compact MDViewer grammars for ` +
      `${PRISM_LANGUAGES.join(", ")} (under 10 KB minified).`,
    files: [{ from: "prismjs/LICENSE", to: [LITE, "PRISM-LICENSE.txt"] }],
    generated: [{ to: [LITE, "prism.min.js"], build: buildPrismBundle }],
  },
  {
    name: "@highlightjs/cdn-assets",
    version: "11.11.1",
    license: "BSD-3-Clause",
    source:
      "https://registry.npmjs.org/@highlightjs/cdn-assets/-/cdn-assets-11.11.1.tgz",
    homepage: "https://github.com/highlightjs/highlight.js",
    edition: "full",
    note: "ESM common build, lazily imported only when code fences exist.",
    files: [
      {
        from: "@highlightjs/cdn-assets/es/highlight.min.js",
        to: [WEB_MODULES, "highlight", "highlight.min.mjs"],
      },
      {
        from: "@highlightjs/cdn-assets/LICENSE",
        to: [FULL, "HIGHLIGHTJS-LICENSE.txt"],
      },
    ],
  },
  {
    name: "js-yaml",
    version: "5.2.3",
    license: "MIT",
    source: "https://registry.npmjs.org/js-yaml/-/js-yaml-5.2.3.tgz",
    homepage: "https://github.com/nodeca/js-yaml",
    edition: "full",
    note: "ESM build, lazily imported only for a valid frontmatter delimiter.",
    files: [
      {
        from: "js-yaml/dist/js-yaml.mjs",
        to: [WEB_MODULES, "js-yaml", "js-yaml.mjs"],
      },
      { from: "js-yaml/LICENSE", to: [FULL, "JS-YAML-LICENSE.txt"] },
    ],
  },
  {
    name: "mermaid",
    version: "11.16.0",
    license: "MIT",
    source: "https://registry.npmjs.org/mermaid/-/mermaid-11.16.0.tgz",
    homepage: "https://github.com/mermaid-js/mermaid",
    edition: "full",
    note:
      "Official modular ESM distribution (minified entry plus every diagram " +
      "chunk) so all supported diagram types render offline. The generated " +
      "transitive notice file covers the complete installed dependency closure.",
    componentClosure: "mermaid",
    files: [
      {
        from: "mermaid/dist/mermaid.esm.min.mjs",
        to: [WEB_MODULES, "mermaid", "mermaid.esm.min.mjs"],
      },
      { from: "mermaid/LICENSE", to: [FULL, "MERMAID-LICENSE.txt"] },
    ],
    directories: [
      {
        from: "mermaid/dist/chunks/mermaid.esm.min",
        to: [WEB_MODULES, "mermaid", "chunks", "mermaid.esm.min"],
        include: /\.mjs$/,
      },
    ],
    generated: [
      {
        to: [FULL, "MERMAID-TRANSITIVE-NOTICES.txt"],
        build: buildMermaidTransitiveNotices,
      },
    ],
  },
  {
    name: "svg-pan-zoom",
    version: "3.6.2",
    license: "BSD-2-Clause",
    source:
      "https://registry.npmjs.org/svg-pan-zoom/-/svg-pan-zoom-3.6.2.tgz",
    homepage: "https://github.com/bumbu/svg-pan-zoom",
    edition: "full",
    note: "Lazily imported only after a diagram renders successfully.",
    files: [
      {
        from: "svg-pan-zoom/dist/svg-pan-zoom.min.js",
        to: [WEB_MODULES, "svg-pan-zoom", "svg-pan-zoom.min.js"],
      },
      { from: "svg-pan-zoom/LICENSE", to: [FULL, "SVG-PAN-ZOOM-LICENSE.txt"] },
    ],
  },
];

async function buildPrismBundle() {
  const core = await readFile(
    path.join(modulesRoot, "prismjs", "components", "prism-core.min.js"),
    "utf8",
  );
  const grammars =
    String.raw`(function(P){const c=k=>({comment:[/\/\*[\s\S]*?\*\//,/\/\/.*/],string:{pattern:/(["'])(?:\\.|(?!\1)[^\\\r\n])*\1/,greedy:!0},keyword:k,boolean:/\b(?:false|true)\b/,function:/\b[a-z_]\w*(?=\s*\()/i,number:/\b(?:0x[\da-f]+|\d+(?:\.\d+)?)\b/i,operator:/[-+*/%=!<>&|^~?:]+/,punctuation:/[{}[\];(),.:]/});P.languages.markup={comment:/<!--[\s\S]*?-->/,tag:{pattern:/<\/?[a-z][^>]*>/i,inside:{"attr-name":/\s[a-z:-]+(?=\s*=)/i,string:/"[^"]*"|'[^']*'/,punctuation:/<\/?|\/?>|=/}},entity:/&[\da-z#]+;/i};P.languages.html=P.languages.markup;P.languages.css={comment:/\/\*[\s\S]*?\*\//,string:/(["'])(?:\\.|(?!\1)[^\\\r\n])*\1/,atrule:/@[a-z-]+/i,selector:/[^{}\s][^{}]*(?=\s*\{)/,property:/[-a-z]+(?=\s*:)/i,number:/\b\d+(?:\.\d+)?(?:%|[a-z]+)?\b/i,important:/!important\b/i,punctuation:/[{}:;(),]/};P.languages.javascript=c(/\b(?:async|await|break|case|catch|class|const|continue|default|delete|do|else|export|extends|finally|for|from|function|if|import|in|instanceof|let|new|of|return|static|super|switch|this|throw|try|typeof|var|void|while|yield)\b/);P.languages.js=P.languages.javascript;P.languages.typescript=P.languages.javascript;P.languages.ts=P.languages.javascript;P.languages.json={property:{pattern:/(^|[,{]\s*)"(?:\\.|[^"\\])*"(?=\s*:)/,lookbehind:!0},string:/"(?:\\.|[^"\\])*"/,number:/-?\b\d+(?:\.\d+)?(?:e[+-]?\d+)?\b/i,punctuation:/[{}[\],]/,operator:/:/,boolean:/\b(?:false|true|null)\b/};P.languages.bash={comment:/#.*/,string:[/"(?:\\.|[^"\\])*"/,/'[^']*'/],variable:/\$(?:\w+|\{[^}]+\})/,keyword:/\b(?:case|do|done|elif|else|esac|export|fi|for|function|if|in|local|then|until|while)\b/,operator:/&&?|\|\|?|;;?|[<>]=?/,punctuation:/[()[\]{}]/};P.languages.shell=P.languages.bash;P.languages.python=c(/\b(?:False|None|True|and|as|assert|async|await|break|class|continue|def|elif|else|except|finally|for|from|if|import|in|is|lambda|not|or|pass|raise|return|try|while|with|yield)\b/);P.languages.py=P.languages.python;P.languages.rust=c(/\b(?:Self|as|async|await|break|const|continue|crate|dyn|else|enum|extern|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|static|struct|super|trait|type|unsafe|use|where|while)\b/);P.languages.rs=P.languages.rust;P.languages.swift=c(/\b(?:Self|actor|as|async|await|break|case|catch|class|continue|default|defer|do|else|enum|extension|for|func|guard|if|import|in|init|inout|internal|is|let|mutating|nil|nonisolated|open|operator|override|private|protocol|public|repeat|return|self|some|static|struct|subscript|super|switch|throws|try|typealias|var|weak|where|while)\b/)})(Prism);`;
  return [
    "/*! MDViewer Prism 1.30.0 core + compact grammars; MIT */",
    core.trim(),
    grammars,
    "",
  ].join("\n");
}

async function dependencyClosure(rootName) {
  const seen = new Map();

  async function visit(name) {
    if (seen.has(name)) return;
    const packageDirectory = path.join(modulesRoot, ...name.split("/"));
    const packageJSONPath = path.join(packageDirectory, "package.json");
    if (!existsSync(packageJSONPath)) {
      throw new Error(`Missing dependency package: ${name}`);
    }
    const metadata = JSON.parse(await readFile(packageJSONPath, "utf8"));
    const licenseFiles = (await readdir(packageDirectory))
      .filter(
        (filename) =>
          /^licen[cs]e(?:[.-].*)?$/i.test(filename) &&
          !filename.toLowerCase().includes("update"),
      )
      .sort();
    if (!licenseFiles.length) {
      throw new Error(`No license file found for ${name}@${metadata.version}`);
    }
    seen.set(name, {
      name,
      version: metadata.version,
      license: metadata.license ?? "See bundled license text",
      source:
        `https://registry.npmjs.org/${encodeURIComponent(name)}/-/` +
        `${name.split("/").pop()}-${metadata.version}.tgz`,
      directory: packageDirectory,
      licenseFiles,
    });
    const dependencies = {
      ...(metadata.dependencies ?? {}),
      ...(metadata.optionalDependencies ?? {}),
    };
    for (const dependency of Object.keys(dependencies).sort()) {
      await visit(dependency);
    }
  }

  await visit(rootName);
  return [...seen.values()].sort((lhs, rhs) =>
    lhs.name.localeCompare(rhs.name),
  );
}

async function buildMermaidTransitiveNotices() {
  const components = await dependencyClosure("mermaid");
  const lines = [
    "MERMAID DISTRIBUTION TRANSITIVE DEPENDENCY NOTICES",
    "",
    "Generated by scripts/vendor_web_assets.mjs from the pinned installed",
    "dependency closure used to produce Mermaid 11.16.0's modular ESM files.",
    "The list may conservatively include package metadata used by the upstream",
    "distribution build in addition to code reached by a particular diagram.",
    "",
  ];
  for (const component of components) {
    lines.push(
      "=".repeat(78),
      `${component.name} ${component.version}`,
      `Declared license: ${component.license}`,
      `Source: ${component.source}`,
      "",
    );
    for (const filename of component.licenseFiles) {
      lines.push(
        `--- ${filename} ---`,
        (await readFile(path.join(component.directory, filename), "utf8"))
          .trim(),
        "",
      );
    }
  }
  return lines.join("\n") + "\n";
}

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

async function download(url) {
  const response = await fetch(url, { redirect: "follow" });
  if (!response.ok) {
    throw new Error(`Failed to download ${url}: HTTP ${response.status}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

function relative(target) {
  return path.relative(repoRoot, target).split(path.sep).join("/");
}

async function collect(directory, include) {
  const found = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      found.push(...(await collect(full, include)));
    } else if (include.test(entry.name)) {
      found.push(full);
    }
  }
  return found.sort();
}

async function writeAsset(destination, contents) {
  await mkdir(path.dirname(destination), { recursive: true });
  if (checkOnly) {
    const existing = existsSync(destination)
      ? await readFile(destination)
      : null;
    if (existing === null || !existing.equals(contents)) {
      throw new Error(`Vendored asset is stale: ${relative(destination)}`);
    }
    return;
  }
  await writeFile(destination, contents);
}

async function main() {
  if (!existsSync(modulesRoot)) {
    throw new Error(
      "vendor/node_modules is missing. Run `npm ci --prefix vendor` first.",
    );
  }

  if (!checkOnly) {
    await rm(WEB_MODULES, { recursive: true, force: true });
  }
  await mkdir(LITE, { recursive: true });
  await mkdir(FULL, { recursive: true });
  await mkdir(WEB_MODULES, { recursive: true });

  const manifestPackages = [];

  for (const pkg of PACKAGES) {
    if (!pkg.retained) {
      const installed = JSON.parse(
        await readFile(
          path.join(modulesRoot, pkg.name, "package.json"),
          "utf8",
        ),
      );
      if (installed.version !== pkg.version) {
        throw new Error(
          `${pkg.name} is pinned to ${pkg.version} but ${installed.version} is installed.`,
        );
      }
    }

    const assets = [];

    for (const retained of pkg.retained ?? []) {
      const destination = path.join(...retained.at);
      if (!existsSync(destination)) {
        throw new Error(
          `Retained asset is missing: ${relative(destination)}`,
        );
      }
      const contents = await readFile(destination);
      const digest = sha256(contents);
      if (digest !== retained.sha256) {
        throw new Error(
          `Retained asset ${relative(destination)} has SHA-256 ${digest}, expected ${retained.sha256}.`,
        );
      }
      assets.push({
        path: relative(destination),
        bytes: contents.byteLength,
        sha256: digest,
        retained: true,
      });
    }

    for (const remote of pkg.remote ?? []) {
      const destination = path.join(...remote.to);
      let contents = existsSync(destination)
        ? await readFile(destination)
        : null;
      if (contents === null || sha256(contents) !== remote.sha256) {
        contents = Buffer.from(await download(remote.url));
      }
      const digest = sha256(contents);
      if (remote.sha256 !== "" && digest !== remote.sha256) {
        throw new Error(
          `Remote asset ${remote.url} has SHA-256 ${digest}, expected ${remote.sha256}.`,
        );
      }
      await writeAsset(destination, contents);
      assets.push({
        path: relative(destination),
        bytes: contents.byteLength,
        sha256: digest,
      });
    }

    for (const file of pkg.files ?? []) {
      const source = path.join(modulesRoot, file.from);
      if (!existsSync(source)) {
        if (file.optional) continue;
        throw new Error(`Missing upstream file: ${file.from}`);
      }
      const contents = await readFile(source);
      const destination = path.join(...file.to);
      await writeAsset(destination, contents);
      assets.push({
        path: relative(destination),
        bytes: contents.byteLength,
        sha256: sha256(contents),
      });
    }

    for (const directory of pkg.directories ?? []) {
      const from = path.join(modulesRoot, directory.from);
      for (const source of await collect(from, directory.include)) {
        const contents = await readFile(source);
        const destination = path.join(
          ...directory.to,
          path.relative(from, source),
        );
        await writeAsset(destination, contents);
        assets.push({
          path: relative(destination),
          bytes: contents.byteLength,
          sha256: sha256(contents),
        });
      }
    }

    for (const generated of pkg.generated ?? []) {
      const contents = Buffer.from(await generated.build(), "utf8");
      const destination = path.join(...generated.to);
      await writeAsset(destination, contents);
      assets.push({
        path: relative(destination),
        bytes: contents.byteLength,
        sha256: sha256(contents),
        generated: true,
      });
    }

    assets.sort((a, b) => a.path.localeCompare(b.path));
    const components = pkg.componentClosure
      ? (await dependencyClosure(pkg.componentClosure)).map(
          ({ name, version, license, source }) => ({
            name,
            version,
            license,
            source,
          }),
        )
      : undefined;
    manifestPackages.push({
      name: pkg.name,
      version: pkg.version,
      license: pkg.license,
      source: pkg.source,
      homepage: pkg.homepage,
      edition: pkg.edition,
      ...(pkg.note ? { note: pkg.note } : {}),
      ...(components ? { components } : {}),
      totalBytes: assets.reduce((sum, asset) => sum + asset.bytes, 0),
      assets,
    });
  }

  // Bundle-only ESM allowlist consumed by MarkdownWebModuleResolver.
  const moduleAssets = manifestPackages
    .flatMap((pkg) => pkg.assets)
    .filter((asset) => asset.path.includes("/FullResources/WebModules/"))
    .map((asset) => ({
      path: asset.path.split("/FullResources/WebModules/")[1],
      sha256: asset.sha256,
      bytes: asset.bytes,
    }))
    .sort((a, b) => a.path.localeCompare(b.path));

  await writeAsset(
    path.join(WEB_MODULES, "web-modules.json"),
    Buffer.from(
      JSON.stringify(
        {
          generatedBy: "scripts/vendor_web_assets.mjs",
          edition: "full",
          modules: moduleAssets,
        },
        null,
        2,
      ) + "\n",
      "utf8",
    ),
  );

  const manifest = {
    schema: 1,
    generatedBy: "scripts/vendor_web_assets.mjs",
    product: "MDViewer",
    productVersion: "2.0.1",
    editions: {
      lite: ["common", "lite"],
      full: ["common", "full"],
    },
    packages: manifestPackages,
  };
  await writeAsset(
    MANIFEST,
    Buffer.from(JSON.stringify(manifest, null, 2) + "\n", "utf8"),
  );
  await writeAsset(NOTICES, Buffer.from(renderNotices(manifest), "utf8"));

  const totals = { common: 0, lite: 0, full: 0 };
  for (const pkg of manifestPackages) {
    totals[pkg.edition] += pkg.totalBytes;
  }
  const kb = (bytes) => `${(bytes / 1024).toFixed(1)} KB`;
  process.stdout.write(
    [
      checkOnly ? "Vendored assets are up to date." : "Vendored assets written.",
      `  common: ${kb(totals.common)}`,
      `  lite:   ${kb(totals.lite)}`,
      `  full:   ${kb(totals.full)}`,
      `  modules allowlisted: ${moduleAssets.length}`,
      "",
    ].join("\n"),
  );
}

function renderNotices(manifest) {
  const lines = [
    "# Third-party notices",
    "",
    `MDViewer ${manifest.productVersion} bundles the following third-party`,
    "software. Every asset is vendored from the pinned upstream release listed",
    "below by `scripts/vendor_web_assets.mjs`; nothing is downloaded at runtime.",
    "",
    "`common` assets ship in both editions. `lite` assets ship only in MDViewer",
    "Lite. `full` assets ship only in MDViewer Full and are physically absent",
    "from Lite artifacts.",
    "",
    "| Package | Version | License | Edition | Bundled bytes |",
    "| --- | --- | --- | --- | --- |",
  ];
  for (const pkg of manifest.packages) {
    lines.push(
      `| [${pkg.name}](${pkg.homepage}) | ${pkg.version} | ${pkg.license} | ${pkg.edition} | ${pkg.totalBytes.toLocaleString("en-US")} |`,
    );
  }
  lines.push("", "## Assets and checksums", "");
  for (const pkg of manifest.packages) {
    lines.push(`### ${pkg.name} ${pkg.version} (${pkg.edition})`, "");
    lines.push(`- License: ${pkg.license}`);
    lines.push(`- Source: ${pkg.source}`);
    if (pkg.note) lines.push(`- Note: ${pkg.note}`);
    if (pkg.components) {
      lines.push(
        `- Transitive dependency closure: ${pkg.components.length} pinned packages; exact names, versions, licenses, and sources are recorded in \`third-party/manifest.json\` and their license texts are bundled in \`MDViewer/FullResources/MERMAID-TRANSITIVE-NOTICES.txt\`.`,
      );
    }
    lines.push("");
    if (pkg.assets.length > 12) {
      const total = pkg.assets.reduce((sum, asset) => sum + asset.bytes, 0);
      lines.push(
        `${pkg.assets.length} files, ${total.toLocaleString("en-US")} bytes.`,
        "Per-file SHA-256 checksums are recorded in `third-party/manifest.json`.",
        "",
      );
      continue;
    }
    lines.push("| File | SHA-256 |", "| --- | --- |");
    for (const asset of pkg.assets) {
      lines.push(`| \`${asset.path}\` | \`${asset.sha256}\` |`);
    }
    lines.push("");
  }
  lines.push(
    "Regenerate this file with `./scripts/vendor_web_assets.sh` and verify it in",
    "CI with `./scripts/vendor_web_assets.sh --check`.",
    "",
  );
  return lines.join("\n");
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
