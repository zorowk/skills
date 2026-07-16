---
name: org-blog-exporter
description: Export, preview, rebuild, or explicitly publish Org notes from `~/Dropbox/notes` as static HTML through the user's Emacs exporter. Use for `setupfile.org`, blog HTML export, or publishing to `zorowk/zorowk.github.io`; publishing can clone the repository into `~/Documents/zorowk.github.io`, commit generated HTML, and push it.
---

# Org Blog Exporter

Export through the running Emacs server. Load `scripts/org-blog-exporter.el` from
this skill directory; it loads the sibling `common/scripts/skill-git.el` helper.
Call `org-blog-exporter-preflight` before export-only work.

## Workflow

1. Determine preview/export-only versus explicit publish, then select one file,
   multiple files, or a full rebuild.
2. Inspect ambiguous selections; do not publish a private draft without explicit
   authorization.
3. Use `org-blog-exporter-local-assets` when local links matter and report missing
   files. Copy assets only when requested.
4. For export-only work, call `org-blog-exporter-export-file`,
   `org-blog-exporter-export-files`, or `org-blog-exporter-export-all` and report
   returned paths and errors.
5. For an explicit publish, call `org-blog-exporter-publish-files` or
   `org-blog-exporter-publish-all`. These functions use
   `https://github.com/zorowk/zorowk.github.io.git`, clone it into
   `~/Documents/zorowk.github.io` when absent, fast-forward it, export, commit only
   changed HTML paths, and push.

Publishing refuses a dirty worktree, an unexpected remote, a non-fast-forward
update, or pre-existing unpushed commits. Do not commit, push, or clone for a
preview/export-only request. Keep reusable site code in the blog repository rather
than embedding it repeatedly in notes.
