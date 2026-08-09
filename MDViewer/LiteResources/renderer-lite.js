(() => {
    "use strict";

    const aliases = {
        html: "markup",
        xml: "markup",
        sh: "bash",
        shell: "bash",
        js: "javascript",
        ts: "typescript",
        py: "python",
        rs: "rust"
    };

    window.__mdviewerEdition = {
        async enhance(root) {
            if (!window.Prism) return;
            for (const code of root.querySelectorAll("pre > code")) {
                if (code.classList.contains("language-mermaid")) continue;
                const source = code.textContent;
                code.dataset.mdviewerSource = source;
                const match = Array.from(code.classList)
                    .find((name) => name.startsWith("language-"));
                if (!match) continue;
                const requested = match.slice("language-".length).toLowerCase();
                const language = aliases[requested] || requested;
                const grammar = window.Prism.languages[language];
                if (!grammar) continue;
                try {
                    code.innerHTML = window.Prism.highlight(source, grammar, language);
                } catch {
                    code.textContent = source;
                }
            }
        }
    };
})();
