---
name: org-blog-exporter
description: Use when an AI assistant should publish, export, rebuild, or preview Org notes from `~/Dropbox/notes` as static HTML blog posts through the user's Emacs Org exporter, especially with `setupfile.org`, blog HTML export, or `~/zorowk.github.io`.
---

# Org Blog Exporter

Export through the running Emacs server. Load `scripts/org-blog-exporter.el` from
this skill directory, then call `org-blog-exporter-preflight`.

## Workflow

1. Determine one file, multiple files, or full rebuild.
2. Inspect ambiguous selections; do not publish a private draft without explicit
   authorization.
3. Use `org-blog-exporter-local-assets` when local links matter and report missing
   files. Copy assets only when requested.
4. Call `org-blog-exporter-export-file`, `org-blog-exporter-export-files`, or
   `org-blog-exporter-export-all` and report returned paths and errors.

Do not commit, deploy, or create an unrequested output repository. Keep reusable
site code in the blog repository rather than embedding it repeatedly in notes.
