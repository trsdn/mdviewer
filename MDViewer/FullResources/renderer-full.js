(() => {
    "use strict";

    const config = window.__MDVIEWER_CONFIG__ || {};
    const moduleBase = config.moduleBase || "";
    const limits = {
        frontmatterBytes: 65536,
        frontmatterLines: 500,
        frontmatterDepth: 6,
        frontmatterEntries: 50,
        diagramBytes: 50000,
        diagrams: 20,
        autoHighlightBytes: 100000
    };
    let highlightPromise = null;
    let yamlPromise = null;
    let mermaidPromise = null;
    let panZoomPromise = null;
    let currentTheme = null;
    const renderedDiagrams = new Set();
    const diagnostics = {
        highlightLoaded: false,
        yamlLoaded: false,
        mermaidLoaded: false,
        panZoomLoaded: false,
        diagramRenderMilliseconds: []
    };
    window.__mdviewerFullDiagnostics = diagnostics;

    function importModule(path) {
        return import(`${moduleBase}${path}`);
    }

    function frontmatterSource(markdown) {
        if (!(markdown.startsWith("---\n") || markdown.startsWith("---\r\n"))) return null;
        const lines = markdown.split(/\r?\n/);
        let closing = -1;
        for (let index = 1; index < Math.min(lines.length, limits.frontmatterLines); index += 1) {
            if (lines[index] === "---" || lines[index] === "...") {
                closing = index;
                break;
            }
        }
        if (closing < 0) {
            return {
                source: "",
                body: lines.slice(1).join("\n"),
                error: "Metadata is missing a closing delimiter."
            };
        }
        const source = lines.slice(1, closing).join("\n");
        return {
            source,
            body: lines.slice(closing + 1).join("\n")
        };
    }

    function inspectMetadata(value, depth = 0, state = { entries: 0 }) {
        if (depth > limits.frontmatterDepth) throw new Error("Metadata is nested too deeply.");
        if (value === null || ["string", "number", "boolean"].includes(typeof value)) return;
        if (Array.isArray(value)) {
            if (value.length > limits.frontmatterEntries) throw new Error("Metadata contains too many values.");
            for (const item of value) inspectMetadata(item, depth + 1, state);
            return;
        }
        if (typeof value !== "object" || Object.getPrototypeOf(value) !== Object.prototype) {
            throw new Error("Metadata contains an unsupported value.");
        }
        for (const [key, child] of Object.entries(value)) {
            state.entries += 1;
            if (state.entries > limits.frontmatterEntries) throw new Error("Metadata contains too many entries.");
            if (["__proto__", "prototype", "constructor"].includes(key)) {
                throw new Error("Metadata contains a reserved key.");
            }
            inspectMetadata(child, depth + 1, state);
        }
    }

    async function parseFrontmatter(source) {
        if (new TextEncoder().encode(source).length > limits.frontmatterBytes) {
            throw new Error("Metadata is too large.");
        }
        if (/(^|\s)[&*!][^\s]+/m.test(source) || /<<\s*:/m.test(source)) {
            throw new Error("Metadata aliases and custom tags are not supported.");
        }
        if (/^\s*(?:__proto__|prototype|constructor)\s*:/mi.test(source)) {
            throw new Error("Metadata contains a reserved key.");
        }
        yamlPromise ||= importModule("js-yaml/js-yaml.mjs");
        const yaml = await yamlPromise;
        diagnostics.yamlLoaded = true;
        const value = yaml.load(source, {
            schema: yaml.FAILSAFE_SCHEMA,
            json: true
        });
        if (value !== undefined && (value === null || Array.isArray(value)
            || typeof value !== "object")) {
            throw new Error("Metadata must be a key-value map.");
        }
        const result = value || {};
        inspectMetadata(result);
        return result;
    }

    function appendValue(parent, value, depth = 0) {
        if (value === null) {
            parent.append(document.createTextNode("null"));
            return;
        }
        if (Array.isArray(value)) {
            const list = document.createElement("ul");
            for (const item of value.slice(0, limits.frontmatterEntries)) {
                const row = document.createElement("li");
                appendValue(row, item, depth + 1);
                list.append(row);
            }
            parent.append(list);
            return;
        }
        if (typeof value === "object") {
            const list = document.createElement("ul");
            for (const key of Object.keys(value).sort()) {
                const row = document.createElement("li");
                const name = document.createElement("strong");
                name.textContent = `${key}: `;
                row.append(name);
                appendValue(row, value[key], depth + 1);
                list.append(row);
            }
            parent.append(list);
            return;
        }
        parent.append(document.createTextNode(String(value)));
    }

    function insertFrontmatterCard(root, metadata) {
        if (!metadata) return;
        const card = document.createElement("details");
        card.className = "md-frontmatter";
        const summary = document.createElement("summary");
        summary.textContent = "Document metadata";
        card.append(summary);
        if (metadata.error) {
            const error = document.createElement("div");
            error.className = "md-frontmatter-error";
            error.setAttribute("role", "status");
            error.textContent = metadata.error;
            card.append(error);
        } else {
            const list = document.createElement("dl");
            for (const key of Object.keys(metadata.value).sort()) {
                const term = document.createElement("dt");
                term.textContent = key;
                const definition = document.createElement("dd");
                appendValue(definition, metadata.value[key]);
                list.append(term, definition);
            }
            card.append(list);
        }
        root.prepend(card);
    }

    function languageFor(code) {
        const match = Array.from(code.classList)
            .find((name) => name.startsWith("language-"));
        return match ? match.slice("language-".length).toLowerCase() : "";
    }

    async function highlightCode(root) {
        const blocks = Array.from(root.querySelectorAll("pre > code"))
            .filter((code) => !code.classList.contains("language-mermaid"));
        if (!blocks.length) return;
        highlightPromise ||= importModule("highlight/highlight.min.mjs");
        let highlighter;
        try {
            highlighter = (await highlightPromise).default;
            diagnostics.highlightLoaded = true;
        } catch {
            return;
        }
        for (const code of blocks) {
            const source = code.textContent;
            code.dataset.mdviewerSource = source;
            const language = languageFor(code);
            try {
                let result;
                if (language && highlighter.getLanguage(language)) {
                    result = highlighter.highlight(source, {
                        language,
                        ignoreIllegals: true
                    });
                } else if (!language && source.length <= limits.autoHighlightBytes) {
                    result = highlighter.highlightAuto(source);
                } else {
                    continue;
                }
                code.innerHTML = window.DOMPurify.sanitize(result.value, {
                    ALLOWED_TAGS: ["span"],
                    ALLOWED_ATTR: ["class"],
                    KEEP_CONTENT: true
                });
                code.classList.add("hljs");
            } catch {
                code.textContent = source;
            }
        }
    }

    function diagramButton(label, action) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "md-code-button";
        button.textContent = label;
        button.setAttribute("aria-label", label);
        button.addEventListener("click", action);
        return button;
    }

    function sanitizeSVG(svg) {
        const clean = window.DOMPurify.sanitize(svg, {
            USE_PROFILES: { svg: true, svgFilters: false },
            FORBID_TAGS: ["script", "style", "foreignObject", "iframe", "a"],
            FORBID_ATTR: [
                "onload", "onclick", "onerror", "href", "xlink:href",
                "style", "formaction"
            ]
        });
        const template = document.createElement("template");
        template.innerHTML = clean;
        for (const element of template.content.querySelectorAll("*")) {
            for (const attribute of Array.from(element.attributes)) {
                if (attribute.name.toLowerCase().startsWith("on")
                    || /url\s*\(/i.test(attribute.value)
                    || /https?:|data:|javascript:/i.test(attribute.value)) {
                    element.removeAttribute(attribute.name);
                }
            }
        }
        return template.innerHTML;
    }

    async function panZoomFor(svg) {
        panZoomPromise ||= importModule("svg-pan-zoom/svg-pan-zoom.min.js");
        try {
            await panZoomPromise;
            diagnostics.panZoomLoaded = true;
            if (!window.svgPanZoom) return null;
            return window.svgPanZoom(svg, {
                controlIconsEnabled: false,
                zoomEnabled: true,
                panEnabled: true,
                dblClickZoomEnabled: false,
                mouseWheelZoomEnabled: true,
                preventMouseEventsDefault: false,
                fit: true,
                center: true,
                minZoom: 0.1,
                maxZoom: 10
            });
        } catch {
            return null;
        }
    }

    async function renderDiagram(container) {
        if (container.dataset.state === "rendering") return;
        container.dataset.state = "rendering";
        const surface = container.querySelector(".md-diagram-surface");
        const error = container.querySelector(".md-diagram-error");
        const source = container.dataset.source || "";
        const started = performance.now();
        try {
            mermaidPromise ||= importModule("mermaid/mermaid.esm.min.mjs");
            const mermaid = (await mermaidPromise).default;
            diagnostics.mermaidLoaded = true;
            mermaid.initialize({
                startOnLoad: false,
                securityLevel: "strict",
                htmlLabels: false,
                suppressErrorRendering: true,
                theme: currentTheme?.category === "dark" ? "dark" : "default",
                flowchart: { htmlLabels: false },
                sequence: { useMaxWidth: true }
            });
            const id = `mdviewer-diagram-${Math.random().toString(36).slice(2)}`;
            const result = await mermaid.render(id, source);
            const clean = sanitizeSVG(result.svg);
            if (!clean.includes("<svg")) throw new Error("Diagram output was rejected.");
            surface.innerHTML = clean;
            const svg = surface.querySelector("svg");
            if (!svg) throw new Error("Diagram output is missing.");
            container._panZoom?.destroy?.();
            container._panZoom = await panZoomFor(svg);
            error.hidden = true;
            error.textContent = "";
            container.dataset.state = "rendered";
            renderedDiagrams.add(container);
            diagnostics.diagramRenderMilliseconds.push(performance.now() - started);
        } catch (reason) {
            surface.replaceChildren();
            const fallback = document.createElement("pre");
            const code = document.createElement("code");
            code.className = "language-mermaid";
            code.textContent = source;
            fallback.append(code);
            surface.append(fallback);
            error.hidden = false;
            error.textContent = `Diagram could not be rendered: ${reason?.message || "Invalid diagram"}`;
            container.dataset.state = "failed";
        }
    }

    function makeDiagram(code) {
        const source = code.textContent;
        const container = document.createElement("figure");
        container.className = "md-diagram";
        container.dataset.source = source;
        container.dataset.state = "pending";
        const toolbar = document.createElement("figcaption");
        toolbar.className = "md-diagram-toolbar";
        const title = document.createElement("span");
        title.className = "md-diagram-title";
        title.textContent = "Mermaid diagram";
        const surface = document.createElement("div");
        surface.className = "md-diagram-surface";
        const pending = document.createElement("div");
        pending.className = "md-diagram-pending";
        pending.textContent = "Diagram will render when visible.";
        surface.append(pending);
        const error = document.createElement("div");
        error.className = "md-diagram-error";
        error.setAttribute("role", "status");
        error.hidden = true;
        toolbar.append(
            title,
            diagramButton("Zoom out", () => container._panZoom?.zoomOut()),
            diagramButton("Zoom in", () => container._panZoom?.zoomIn()),
            diagramButton("Fit", () => {
                container._panZoom?.resize();
                container._panZoom?.fit();
                container._panZoom?.center();
            }),
            diagramButton("Reset", () => container._panZoom?.reset())
        );
        container.append(toolbar, surface, error);
        return container;
    }

    function prepareDiagrams(root) {
        const blocks = Array.from(root.querySelectorAll("pre > code.language-mermaid"));
        const observer = "IntersectionObserver" in window
            ? new IntersectionObserver((entries, current) => {
                for (const entry of entries) {
                    if (!entry.isIntersecting) continue;
                    current.unobserve(entry.target);
                    renderDiagram(entry.target);
                }
            }, { rootMargin: "300px" })
            : null;
        blocks.forEach((code, index) => {
            const sourceBytes = new TextEncoder().encode(code.textContent).length;
            if (index >= limits.diagrams || sourceBytes > limits.diagramBytes) return;
            const pre = code.parentElement;
            const diagram = makeDiagram(code);
            pre.replaceWith(diagram);
            if (observer) observer.observe(diagram);
            else renderDiagram(diagram);
        });
    }

    async function rerenderDiagrams() {
        for (const diagram of Array.from(renderedDiagrams)) {
            if (!diagram.isConnected) {
                renderedDiagrams.delete(diagram);
                continue;
            }
            diagram.dataset.state = "pending";
            await renderDiagram(diagram);
        }
    }

    window.__mdviewerEdition = {
        async preprocess(markdown) {
            const frontmatter = frontmatterSource(markdown);
            if (!frontmatter) return { markdown, metadata: null };
            if (frontmatter.error) {
                return {
                    markdown: frontmatter.body,
                    metadata: { error: frontmatter.error }
                };
            }
            try {
                return {
                    markdown: frontmatter.body,
                    metadata: { value: await parseFrontmatter(frontmatter.source) }
                };
            } catch (error) {
                return {
                    markdown: frontmatter.body,
                    metadata: { error: error?.message || "Metadata could not be parsed." }
                };
            }
        },
        async enhance(root, context) {
            insertFrontmatterCard(root, context.metadata);
            prepareDiagrams(root);
            await highlightCode(root);
        },
        async themeChanged(theme) {
            currentTheme = theme;
            if (renderedDiagrams.size) await rerenderDiagrams();
        },
        async preparePrint() {
            for (const card of document.querySelectorAll(".md-frontmatter")) card.open = true;
            const diagrams = Array.from(document.querySelectorAll(".md-diagram"));
            await Promise.all(diagrams.map(async (diagram) => {
                if (diagram.dataset.state !== "rendered") await renderDiagram(diagram);
                diagram._panZoom?.resize();
                diagram._panZoom?.fit();
                diagram._panZoom?.center();
            }));
        }
    };
})();
