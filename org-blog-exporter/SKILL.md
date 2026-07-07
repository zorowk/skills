---
name: org-blog-exporter
description: Use when an AI assistant should publish, export, rebuild, or preview Org notes from `~/Dropbox/notes` as static HTML blog posts through the user's Emacs Org exporter, especially with `setupfile.org`, blog HTML export, or `~/zorowk.github.io`.
---

# Org Blog Exporter

## Purpose

Export selected Org files from `~/Dropbox/notes` to the blog directory declared by `~/Dropbox/notes/setupfile.org` (`#+BLOG_EXPORT_DIR:` preferred; fallback `~/zorowk.github.io/`). Export uses `scripts/org-blog-exporter.el` through the running Emacs session.

## Load Helper

Load the helper before calling `org-blog-exporter-preflight`,
`org-blog-exporter-local-assets`, or any export function; the functions are not
available until the script is loaded into the running Emacs server.

```elisp
(let ((skill-root (or (getenv "SKILL_ROOT")
                      (expand-file-name "~/Documents/Code/skills/org-blog-exporter"))))
  (load-file (expand-file-name "scripts/org-blog-exporter.el" skill-root)))
```

If the skill is installed somewhere else, set `SKILL_ROOT` to this skill's
directory before evaluating the load form.

## Preflight

Before exporting, call `org-blog-exporter-preflight` or verify notes dir, setupfile, and output dir. Use file-reading/search tools for inspection; use Emacs only for Org HTML export.

If the output directory is missing, ask before creating it unless the user explicitly requested export/rebuild with missing-directory creation.

## Workflow

1. Determine one file, multiple files, or full rebuild.
2. Run preflight.
3. Inspect ambiguous requests; do not publish private drafts unless explicit.
4. For local image/attachment/`file:` links, call `org-blog-exporter-local-assets` and report missing assets. Do not copy assets unless asked.
5. Export with `org-blog-exporter-export-file`, `org-blog-exporter-export-files`, or `org-blog-exporter-export-all`.
6. Report exported HTML paths plus skipped files/errors.

## Key Helpers

| Need | Call |
|---|---|
| Preflight | `org-blog-exporter-preflight` |
| Candidate files | `org-blog-exporter-list-candidates` |
| Local assets | `org-blog-exporter-local-assets` |
| Export one/many | `org-blog-exporter-export-file`, `org-blog-exporter-export-files` |
| Full rebuild | `org-blog-exporter-export-all` |

The helper skips setupfile, private/draft/noexport files, backup/hidden files, and excluded directories.

## Rules

- Preserve relative output paths under the blog root.
- Keep reusable JavaScript in the blog repo and reference it from Org export blocks.
- After export, verify at least one generated file exists and contains HTML; for rebuilds summarize counts.
- Do not run `git add`, `git commit`, or deploy unless the user asks.
