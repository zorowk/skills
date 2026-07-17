---
name: org-blog-exporter
description: Export, preview, rebuild, or explicitly publish Org notes from `~/Dropbox/notes` as static HTML through the user's Emacs exporter. Use for `setupfile.org`, blog HTML export, or publishing a configured blog repository; publishing can copy local media resources, commit generated files, and push them.
---

# Org Blog Exporter

Load `scripts/org-blog-exporter.el` and call `org-blog-exporter-run` through the
running Emacs server. Keep compact results unless complete path lists are necessary.

Resolve ambiguous files before acting. Export needs no external authorization.
Publish only after an explicit user request and pass `:authorization explicit`;
nil `:files` means all public notes. Never bypass a program safety error manually.
