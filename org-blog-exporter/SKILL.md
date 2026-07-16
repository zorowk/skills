---
name: org-blog-exporter
description: Export, preview, rebuild, or explicitly publish Org notes from `~/Dropbox/notes` as static HTML through the user's Emacs exporter. Use for `setupfile.org`, blog HTML export, or publishing a configured blog repository; publishing can clone the configured repository, commit generated HTML, and push it.
---

# Org Blog Exporter

Export through the running Emacs server. Load `scripts/org-blog-exporter.el` from
this skill directory; it loads the sibling `common/scripts/skill-git.el` helper.
Call `org-blog-exporter-preflight` before export-only work.
Treat bundled scripts as executable implementations: during normal use, load and
call documented entry points without reading source. Inspect source only when
debugging, modifying a script, or resolving undocumented behavior.

## Workflow

1. Determine preview/export-only versus explicit publish, then select one file,
   multiple files, or a full rebuild.
2. Inspect ambiguous selections; do not publish a private draft without explicit
   authorization.
3. Use `org-blog-exporter-local-assets` when local links matter and report missing
   files. Copy assets only when requested.
4. For export-only work, call `org-blog-exporter-export-file`,
   `org-blog-exporter-export-files`, or `org-blog-exporter-export-all` and report
   returned paths and errors. During export, recognized assessment properties are
   rendered as a visible `assessment-summary` in the temporary export buffer; the
   source Org file remains unchanged. Supported properties are `STATUS`,
   `CREDIBILITY`, `MATURITY`, `HYWIKI_CANDIDATE`, `REVIEW_PERIOD`,
   `QUESTION_STATUS`, and `REVIEW_DATE`.
5. For an explicit publish, call `org-blog-exporter-publish-files` or
   `org-blog-exporter-publish-all`. These functions read `BLOG_REPOSITORY_URL`
   and `BLOG_EXPORT_DIR` from `setupfile.org`, clone the repository when absent,
   fast-forward it, export, merge published posts into `index.html`, commit only
   changed HTML paths, and push. Explicit function arguments override setupfile
   values; Elisp defaults are the final fallback.

Publishing refuses a dirty worktree, an unexpected remote, a non-fast-forward
update, or pre-existing unpushed commits. Do not commit, push, or clone for a
preview/export-only request. Keep reusable site code in the blog repository rather
than embedding it repeatedly in notes.
