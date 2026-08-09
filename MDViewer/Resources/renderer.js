(() => {
    "use strict";

    const config = window.__MDVIEWER_CONFIG__ || {};
    const content = document.getElementById("content");
    const allowedImageExtensions = new Set(["png", "jpg", "jpeg", "gif", "webp"]);
    const allowedExternalSchemes = new Set(["http:", "https:", "mailto:"]);
    const colorVariables = {
        background: "--color-bg",
        foreground: "--color-fg",
        border: "--color-border",
        codeBackground: "--color-code-bg",
        codeForeground: "--color-code-fg",
        link: "--color-link",
        blockquoteForeground: "--color-blockquote-fg",
        blockquoteBorder: "--color-blockquote-border",
        horizontalRule: "--color-hr",
        selectionBackground: "--color-selection-bg",
        selectionForeground: "--color-selection-fg",
        caret: "--color-caret",
        activeLine: "--color-active-line",
        gutterBackground: "--color-gutter-bg",
        gutterForeground: "--color-gutter-fg",
        splitter: "--color-splitter",
        splitterHover: "--color-splitter-hover",
        searchMatch: "--color-search-match",
        searchMatchSelected: "--color-search-match-selected"
    };
    const syntaxVariables = {
        keyword: "--syntax-keyword",
        string: "--syntax-string",
        number: "--syntax-number",
        comment: "--syntax-comment",
        function: "--syntax-function",
        type: "--syntax-type",
        variable: "--syntax-variable",
        punctuation: "--syntax-punctuation",
        alertNote: "--alert-note",
        alertTip: "--alert-tip",
        alertImportant: "--alert-important",
        alertWarning: "--alert-warning",
        alertCaution: "--alert-caution"
    };
    const alertSymbols = {
        NOTE: "ⓘ",
        TIP: "✓",
        IMPORTANT: "◆",
        WARNING: "⚠",
        CAUTION: "⛔"
    };

    let renderCount = 0;
    let renderGeneration = 0;
    let imageViewer = null;
    let imageViewerState = null;

    if (window.markedFootnote) {
        window.marked.use(window.markedFootnote({
            sectionClass: "footnotes",
            headingClass: "sr-only",
            backRefLabel: "Back to footnote reference {0}"
        }));
    }
    window.marked.use({ gfm: true, breaks: false });

    function sanitizeMarkdownHTML(html) {
        return window.DOMPurify.sanitize(html, {
            USE_PROFILES: { html: true },
            FORBID_TAGS: [
                "script", "style", "svg", "math", "iframe", "frame", "object",
                "embed", "form", "button", "textarea", "select", "option",
                "audio", "video", "source", "track", "canvas"
            ],
            FORBID_ATTR: [
                "srcdoc", "formaction", "action", "autofocus", "contenteditable",
                "download", "ping"
            ],
            ADD_ATTR: [
                "checked", "disabled", "open", "aria-describedby", "aria-label",
                "data-footnote-ref", "data-footnote-backref", "data-footnotes"
            ],
            ALLOW_DATA_ATTR: true,
            ALLOW_ARIA_ATTR: true
        });
    }

    function safeRelativePath(value, extensions) {
        if (!value || value.length > 2048 || value.includes("\0")
            || value.includes("\\") || value.includes("?") || value.includes("#")
            || value.startsWith("/") || value.startsWith("//")) {
            return false;
        }
        let decoded;
        try {
            decoded = decodeURIComponent(value);
        } catch {
            return false;
        }
        if (!decoded || decoded.startsWith("/") || decoded.includes("\\")
            || decoded.includes("\0")) {
            return false;
        }
        const parts = decoded.split("/");
        if (parts.some((part) => !part || part === "..")) {
            return false;
        }
        const name = parts[parts.length - 1];
        const dot = name.lastIndexOf(".");
        return dot > 0 && extensions.has(name.slice(dot + 1).toLowerCase());
    }

    function isRelativeMarkdownLink(value) {
        const path = value.split("#", 1)[0];
        return safeRelativePath(path, new Set(["md", "markdown", "mdown", "mkd"]));
    }

    function normalizeLinks(root) {
        for (const anchor of root.querySelectorAll("a")) {
            const raw = anchor.getAttribute("href");
            if (!raw) {
                anchor.removeAttribute("href");
                continue;
            }
            if (raw.startsWith("#") && raw.length > 1) {
                continue;
            }
            let parsed;
            try {
                parsed = new URL(raw, "mdviewer-resource://document/");
            } catch {
                anchor.removeAttribute("href");
                continue;
            }
            if (allowedExternalSchemes.has(parsed.protocol)) {
                anchor.setAttribute("rel", "noopener noreferrer");
                continue;
            }
            if (isRelativeMarkdownLink(raw)) {
                anchor.setAttribute(
                    "href",
                    `mdviewer-document://open/${encodeURIComponent(raw)}`
                );
                continue;
            }
            anchor.removeAttribute("href");
        }
    }

    function normalizeImages(root) {
        const images = [];
        for (const image of root.querySelectorAll("img")) {
            const raw = image.getAttribute("src");
            if (!safeRelativePath(raw, allowedImageExtensions)) {
                image.removeAttribute("src");
                continue;
            }
            image.classList.add("md-zoomable");
            image.tabIndex = 0;
            image.setAttribute("role", "button");
            const label = image.getAttribute("alt") || "Image";
            image.setAttribute("aria-label", `Inspect ${label}`);
            images.push(raw);
        }
        return Array.from(new Set(images));
    }

    function removeAlertMarker(node, markerLength) {
        const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
        let remaining = markerLength;
        while (remaining > 0) {
            const text = walker.nextNode();
            if (!text) break;
            if (text.data.length <= remaining) {
                remaining -= text.data.length;
                text.data = "";
            } else {
                text.data = text.data.slice(remaining).replace(/^\s+/, "");
                remaining = 0;
            }
        }
    }

    function decorateAlerts(root) {
        for (const quote of root.querySelectorAll("blockquote")) {
            const first = quote.firstElementChild;
            if (!first) continue;
            const match = first.textContent.match(/^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*/i);
            if (!match) continue;
            const kind = match[1].toUpperCase();
            removeAlertMarker(first, match[0].length);
            if (!first.textContent.trim() && !first.children.length) first.remove();
            quote.classList.add("md-alert", `md-alert-${kind.toLowerCase()}`);
            const label = document.createElement("div");
            label.className = "md-alert-label";
            label.setAttribute("role", "heading");
            label.setAttribute("aria-level", "6");
            const symbol = document.createElement("span");
            symbol.setAttribute("aria-hidden", "true");
            symbol.textContent = alertSymbols[kind];
            const title = document.createElement("span");
            title.textContent = kind[0] + kind.slice(1).toLowerCase();
            label.append(symbol, title);
            quote.prepend(label);
        }
    }

    function decorateTaskLists(root) {
        for (const checkbox of root.querySelectorAll('input[type="checkbox"]')) {
            checkbox.disabled = true;
            checkbox.tabIndex = -1;
            checkbox.setAttribute(
                "aria-label",
                checkbox.checked ? "Completed task" : "Incomplete task"
            );
            const item = checkbox.closest("li");
            if (item) {
                item.classList.add("task-list-item");
                const list = item.parentElement;
                if (list && list.tagName === "UL") list.classList.add("contains-task-list");
            }
        }
    }

    function slugBase(value) {
        const normalized = value.normalize("NFKC").trim().toLowerCase()
            .replace(/[\u0000-\u001f\u007f]/g, "")
            .replace(/[!"#$%&'()*+,./:;<=>?@[\\\]^`{|}~]/g, "")
            .replace(/\s+/g, "-")
            .replace(/-+/g, "-")
            .replace(/^-|-$/g, "");
        return normalized || "section";
    }

    function assignHeadingIDs(root) {
        const used = new Map();
        const outline = [];
        for (const heading of root.querySelectorAll("h1, h2, h3, h4, h5, h6")) {
            if (heading.closest(".footnotes") || heading.classList.contains("sr-only")) {
                continue;
            }
            const base = slugBase(heading.textContent);
            const seen = used.get(base) || 0;
            used.set(base, seen + 1);
            const id = seen === 0 ? base : `${base}-${seen}`;
            heading.id = id;
            outline.push({
                id,
                level: Number(heading.tagName.slice(1)),
                title: heading.textContent.trim()
            });
        }
        return outline;
    }

    function languageFor(code) {
        const languageClass = Array.from(code.classList)
            .find((name) => name.startsWith("language-"));
        return languageClass ? languageClass.slice("language-".length) : "plain";
    }

    function button(label, action, pressed) {
        const element = document.createElement("button");
        element.type = "button";
        element.className = "md-code-button";
        element.textContent = label;
        element.setAttribute("aria-label", label);
        if (typeof pressed === "boolean") {
            element.setAttribute("aria-pressed", String(pressed));
        }
        element.addEventListener("click", action);
        return element;
    }

    function copySource(source, status) {
        try {
            const handler = window.webkit?.messageHandlers?.copyText;
            if (!handler) throw new Error("Clipboard unavailable");
            handler.postMessage(source);
            status.textContent = "Copied";
        } catch {
            status.textContent = "Copy failed";
        }
        window.setTimeout(() => {
            status.textContent = "";
        }, 1800);
    }

    function decorateCodeBlocks(root) {
        for (const code of root.querySelectorAll("pre > code")) {
            const pre = code.parentElement;
            if (!pre || pre.closest("figure.md-code") || pre.closest(".md-diagram")) continue;
            const source = code.dataset.mdviewerSource ?? code.textContent;
            const language = languageFor(code);
            const figure = document.createElement("figure");
            figure.className = "md-code";
            figure.dataset.wrap = "off";
            figure.dataset.lines = "off";

            const caption = document.createElement("figcaption");
            const label = document.createElement("span");
            label.className = "md-code-language";
            label.textContent = language === "plain" ? "Code" : language;
            const actions = document.createElement("span");
            actions.className = "md-code-actions";
            const status = document.createElement("span");
            status.className = "md-code-status";
            status.setAttribute("role", "status");
            status.setAttribute("aria-live", "polite");

            const wrapButton = button("Wrap", () => {
                const enabled = figure.dataset.wrap !== "on";
                figure.dataset.wrap = enabled ? "on" : "off";
                wrapButton.setAttribute("aria-pressed", String(enabled));
            }, false);
            const linesButton = button("Lines", () => {
                const enabled = figure.dataset.lines !== "on";
                figure.dataset.lines = enabled ? "on" : "off";
                linesButton.setAttribute("aria-pressed", String(enabled));
            }, false);
            const copyButton = button("Copy", () => copySource(source, status));
            if (source.length > 1_000_000) {
                copyButton.disabled = true;
                copyButton.title = "Code block is too large to copy.";
            }
            actions.append(copyButton, wrapButton, linesButton);
            caption.append(label, actions, status);

            const body = document.createElement("div");
            body.className = "md-code-body";
            const gutter = document.createElement("span");
            gutter.className = "md-code-gutter";
            gutter.setAttribute("aria-hidden", "true");
            const count = Math.max(1, source.replace(/\n$/, "").split("\n").length);
            if (count > 10_000) {
                linesButton.disabled = true;
                linesButton.title = "Line numbers are disabled for very large blocks.";
            } else {
                for (let index = 1; index <= count; index += 1) {
                    const line = document.createElement("span");
                    line.textContent = String(index);
                    gutter.append(line);
                }
            }

            pre.replaceWith(figure);
            body.append(gutter, pre);
            figure.append(caption, body);
        }
    }

    function ensureImageViewer() {
        if (imageViewer) return imageViewer;
        const overlay = document.createElement("div");
        overlay.className = "md-image-viewer";
        overlay.hidden = true;
        overlay.setAttribute("role", "dialog");
        overlay.setAttribute("aria-modal", "true");
        overlay.setAttribute("aria-label", "Image inspection");

        const toolbar = document.createElement("div");
        toolbar.className = "md-image-viewer-toolbar";
        const caption = document.createElement("span");
        caption.className = "md-image-viewer-caption";
        const stage = document.createElement("div");
        stage.className = "md-image-viewer-stage";
        const image = document.createElement("img");
        image.draggable = false;
        stage.append(image);

        const applyTransform = () => {
            const state = imageViewerState;
            if (!state) return;
            image.style.transform = `translate(${state.x}px, ${state.y}px) scale(${state.scale})`;
        };
        const fit = () => {
            if (!image.naturalWidth || !image.naturalHeight) return;
            const scale = Math.min(
                stage.clientWidth / image.naturalWidth,
                stage.clientHeight / image.naturalHeight,
                1
            );
            imageViewerState.scale = scale;
            imageViewerState.x = (stage.clientWidth - image.naturalWidth * scale) / 2;
            imageViewerState.y = (stage.clientHeight - image.naturalHeight * scale) / 2;
            applyTransform();
        };
        const zoom = (factor) => {
            const state = imageViewerState;
            if (!state) return;
            const next = Math.min(8, Math.max(0.1, state.scale * factor));
            const centerX = stage.clientWidth / 2;
            const centerY = stage.clientHeight / 2;
            state.x = centerX - ((centerX - state.x) / state.scale) * next;
            state.y = centerY - ((centerY - state.y) / state.scale) * next;
            state.scale = next;
            applyTransform();
        };
        const original = () => {
            imageViewerState.scale = 1;
            imageViewerState.x = (stage.clientWidth - image.naturalWidth) / 2;
            imageViewerState.y = (stage.clientHeight - image.naturalHeight) / 2;
            applyTransform();
        };
        const close = () => {
            if (!imageViewerState) return;
            const trigger = imageViewerState.trigger;
            overlay.hidden = true;
            image.removeAttribute("src");
            imageViewerState = null;
            trigger.focus();
        };

        toolbar.append(
            caption,
            button("Fit", fit),
            button("Zoom out", () => zoom(0.8)),
            button("Zoom in", () => zoom(1.25)),
            button("Original size", original),
            button("Close", close)
        );
        overlay.append(toolbar, stage);
        document.body.append(overlay);

        let pointer = null;
        stage.addEventListener("pointerdown", (event) => {
            if (!imageViewerState) return;
            pointer = {
                id: event.pointerId,
                x: event.clientX,
                y: event.clientY,
                originX: imageViewerState.x,
                originY: imageViewerState.y
            };
            stage.setPointerCapture(event.pointerId);
            stage.classList.add("md-panning");
        });
        stage.addEventListener("pointermove", (event) => {
            if (!pointer || event.pointerId !== pointer.id || !imageViewerState) return;
            imageViewerState.x = pointer.originX + event.clientX - pointer.x;
            imageViewerState.y = pointer.originY + event.clientY - pointer.y;
            applyTransform();
        });
        const endPointer = (event) => {
            if (!pointer || event.pointerId !== pointer.id) return;
            pointer = null;
            stage.classList.remove("md-panning");
        };
        stage.addEventListener("pointerup", endPointer);
        stage.addEventListener("pointercancel", endPointer);
        stage.addEventListener("wheel", (event) => {
            event.preventDefault();
            zoom(event.deltaY < 0 ? 1.1 : 0.9);
        }, { passive: false });
        overlay.addEventListener("keydown", (event) => {
            if (event.key === "Escape") close();
            if (event.key === "+" || event.key === "=") zoom(1.25);
            if (event.key === "-") zoom(0.8);
            if (event.key === "0") fit();
            const state = imageViewerState;
            if (!state) return;
            const step = 24;
            if (event.key === "ArrowLeft") state.x += step;
            else if (event.key === "ArrowRight") state.x -= step;
            else if (event.key === "ArrowUp") state.y += step;
            else if (event.key === "ArrowDown") state.y -= step;
            else return;
            event.preventDefault();
            applyTransform();
        });
        image.addEventListener("load", fit);
        imageViewer = { overlay, caption, stage, image, fit, close };
        return imageViewer;
    }

    function decorateImages(root) {
        const viewer = ensureImageViewer();
        const open = (image) => {
            if (!image.getAttribute("src")) return;
            imageViewerState = { trigger: image, scale: 1, x: 0, y: 0 };
            viewer.caption.textContent = image.getAttribute("alt") || "Image";
            viewer.image.alt = image.getAttribute("alt") || "";
            viewer.image.src = image.src;
            viewer.overlay.hidden = false;
            viewer.overlay.tabIndex = -1;
            viewer.overlay.focus();
        };
        for (const image of root.querySelectorAll("img.md-zoomable")) {
            image.addEventListener("click", () => open(image));
            image.addEventListener("keydown", (event) => {
                if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    open(image);
                }
            });
        }
    }

    async function renderMarkdown(markdown) {
        const generation = ++renderGeneration;
        const isCurrent = () => generation === renderGeneration;
        const staleResult = () => ({
            images: [],
            outline: [],
            edition: config.edition || "lite",
            generation,
            cancelled: true
        });
        const edition = window.__mdviewerEdition || {};
        const prepared = edition.preprocess
            ? await edition.preprocess(String(markdown))
            : { markdown: String(markdown), metadata: null };
        if (!isCurrent()) return staleResult();
        const dirty = window.marked.parse(prepared.markdown);
        const template = document.createElement("template");
        template.innerHTML = sanitizeMarkdownHTML(dirty);
        const fragment = template.content;
        normalizeLinks(fragment);
        const images = normalizeImages(fragment);
        decorateAlerts(fragment);
        decorateTaskLists(fragment);
        const outline = assignHeadingIDs(fragment);

        content.replaceChildren(fragment);
        if (edition.enhance) {
            await edition.enhance(content, {
                config,
                generation,
                isCurrent,
                metadata: prepared.metadata,
                sanitizeMarkdownHTML
            });
        }
        if (!isCurrent()) return staleResult();
        decorateCodeBlocks(content);
        decorateImages(content);
        renderCount += 1;
        window.__mdviewerRenderCount = renderCount;
        return {
            images,
            outline,
            edition: config.edition || "lite",
            generation,
            cancelled: false
        };
    }

    async function applyTheme(theme) {
        const root = document.documentElement.style;
        const colors = theme?.colors || theme || {};
        for (const [key, value] of Object.entries(colors)) {
            if (colorVariables[key]) root.setProperty(colorVariables[key], value);
        }
        for (const [key, value] of Object.entries(theme?.syntax || {})) {
            if (syntaxVariables[key]) root.setProperty(syntaxVariables[key], value);
        }
        if (window.__mdviewerEdition?.themeChanged) {
            await window.__mdviewerEdition.themeChanged(theme);
        }
        return true;
    }

    function scrollToHeading(id) {
        const value = String(id);
        const heading = document.getElementById(value)
            || document.getElementById(slugBase(value));
        if (!heading) return false;
        heading.scrollIntoView({ block: "start", behavior: "smooth" });
        heading.tabIndex = -1;
        heading.focus({ preventScroll: true });
        return true;
    }

    async function prepareForPrint() {
        if (window.__mdviewerEdition?.preparePrint) {
            await window.__mdviewerEdition.preparePrint();
        }
        return true;
    }

    window.addEventListener("beforeprint", prepareForPrint);
    window.renderMarkdown = renderMarkdown;
    window.applyTheme = applyTheme;
    window.scrollToHeading = scrollToHeading;
    window.prepareForPrint = prepareForPrint;
})();
