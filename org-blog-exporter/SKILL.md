---
name: org-blog-exporter
description: Export, preview, rebuild, or explicitly publish Org notes from `~/Dropbox/notes` as static HTML through the user's Emacs exporter. Use for `setupfile.org`, blog HTML export, or publishing a configured blog repository; publishing can copy local media resources, commit generated files, and push them.
---

# Org Blog Exporter

Load `scripts/org-blog-exporter.el` and call its public entry points through the
running Emacs server. Treat the script and function docstrings as the implementation
and interface; inspect source only to debug or modify it.

## Workflow

1. Decide whether the request is export-only or explicit publishing, and resolve
   the requested file scope. Inspect ambiguous selections before acting.
2. For export-only work, call `org-blog-exporter-export-file`,
   `org-blog-exporter-export-files`, or `org-blog-exporter-export-all`.
3. Only with explicit publishing authorization, call
   `org-blog-exporter-publish-files` or `org-blog-exporter-publish-all`.
4. Report returned paths, publishing results, and errors. Do not bypass a program
   safety error by manually cloning, committing, or pushing.
