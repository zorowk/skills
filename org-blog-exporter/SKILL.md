---
name: org-blog-exporter
description: Export Org-mode notes from ~/Dropbox/notes to static HTML blog files using the user's existing ~/Dropbox/notes/setupfile.org Blog HTML exporter configuration, including the blog output directory declared there. Use when the user asks to publish, export, rebuild, or preview Org notes as HTML blog posts, especially requests mentioning org, Org mode, notes, setupfile.org, blog HTML export, or ~/zorowk.github.io.
---

# Org Blog Exporter

## Purpose

Export selected Org files from `~/Dropbox/notes` into the blog directory declared by `~/Dropbox/notes/setupfile.org` as static HTML blog files while reusing the existing blog export settings in that setupfile.

The implementation lives in `scripts/org-blog-exporter.el`. Load it into the user's running Emacs session, then call one of its functions through `emacsclient --eval`.

## Defaults

- Notes directory: `~/Dropbox/notes/`
- Blog output directory: read from `#+BLOG_EXPORT_DIR:` in `~/Dropbox/notes/setupfile.org`; fallback `~/zorowk.github.io/`
- Setupfile: `~/Dropbox/notes/setupfile.org`
- Org setup directive inserted when missing: `#+SETUPFILE: /absolute/path/to/setupfile.org`
- Export backend: `org-export-to-file` with the HTML backend
- Default behavior: export `.org` files recursively, skip files tagged or placed in `noexport`, and preserve relative paths under the blog root.

## Workflow

1. Identify whether the user wants one file, several files, or a full rebuild.
2. Inspect the relevant Org files before exporting when the request is ambiguous. Do not publish private drafts unless the user explicitly asks.
3. Use the bundled Elisp through `emacsclient --eval`:

```elisp
(progn
  (load-file "/path/to/org-blog-exporter/scripts/org-blog-exporter.el")
  (org-blog-exporter-export-file "~/Dropbox/notes/example.org"))
```

4. For a directory rebuild, call:

```elisp
(progn
  (load-file "/path/to/org-blog-exporter/scripts/org-blog-exporter.el")
  (org-blog-exporter-export-all))
```

5. Report exported HTML paths and any skipped files or errors.

## Functions

- `(org-blog-exporter-export-file ORG-FILE &optional OUTPUT-DIR SETUPFILE)`: export one Org file and return the HTML path.
- `(org-blog-exporter-export-files ORG-FILES &optional OUTPUT-DIR SETUPFILE)`: export a list of Org files and return HTML paths.
- `(org-blog-exporter-export-all &optional NOTES-DIR OUTPUT-DIR SETUPFILE)`: recursively export eligible Org files under the notes directory.
- `(org-blog-exporter-list-candidates &optional NOTES-DIR)`: list exportable Org files before taking action.

When `OUTPUT-DIR` is nil, the script reads the output directory from the setupfile. Supported setupfile keywords are `#+BLOG_EXPORT_DIR:`, `#+BLOG_OUTPUT_DIR:`, `#+BLOG_DIR:`, and `#+BLOG_DIRECTORY:`. Prefer `#+BLOG_EXPORT_DIR:`.

## Selection Rules

Treat a file as not exportable when any of these are true:

- The file is `setupfile.org`.
- The path contains `.git`, `.stversions`, `archive`, `archives`, `attach`, `attachments`, `assets`, `auto`, `backup`, `backups`, `draft`, `drafts`, `private`, `tmp`, or `trash` as a directory component.
- The file has a top-level `#+FILETAGS:` line containing `noexport`, `private`, or `draft`.
- The file name starts with `.` or `#`, or ends with `~`.

When the user names an excluded file explicitly, ask before overriding the exclusion.

## Export Notes

The script creates a temporary export buffer that prepends an absolute `#+SETUPFILE:` directive when the source file does not already specify a setupfile. This makes Org load the user's current blog HTML settings without modifying the original note.

HTML output preserves the note's path relative to `~/Dropbox/notes`. For example:

- `~/Dropbox/notes/posts/foo.org` -> `~/zorowk.github.io/posts/foo.html`
- `~/Dropbox/notes/foo.org` -> `~/zorowk.github.io/foo.html`

If the source file contains local image or attachment links, inspect them before publishing. Copying assets is not automatic unless the user asks; prefer preserving existing relative links when the blog repo already contains those assets.

## Verification

After exporting, verify at least one generated file exists and contains HTML. For full rebuilds, summarize counts:

- candidate Org files
- exported HTML files
- skipped files
- errors, if any

Do not run `git add`, `git commit`, or deploy from `~/zorowk.github.io` unless the user asks.
