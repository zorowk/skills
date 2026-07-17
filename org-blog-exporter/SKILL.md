---
name: org-blog-exporter
description: Export, preview, rebuild, or explicitly publish Org notes from `~/Dropbox/notes` as static HTML through the user's Emacs exporter. Use for `setupfile.org`, blog HTML export, or publishing a configured blog repository; publishing can copy local media resources, commit generated files, and push them.
---

# Org Blog Exporter

Load `scripts/org-blog-exporter.el` and call its public entry points through the
running Emacs server. Treat the script and function docstrings as the implementation
and interface; inspect source only to debug or modify it.

Resolve an ambiguous file selection before acting. For export-only work, call
`org-blog-exporter-export`; pass nil files for all public notes. Only with explicit
publishing authorization call `org-blog-exporter-publish`, again using nil for all
public notes. Report its returned paths, publishing results, and errors. Do not
bypass a program safety error by manually cloning, committing, or pushing.
