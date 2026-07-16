# Local Denote and HyWiki interface

Read this reference when changing integration behavior or creating HyWiki pages.

## Configured directories

- Denote: `~/Dropbox/notes/`, set by `denote-directory` in
  `~/.emacs.d/elisp/init-org.el`.
- HyWiki: `~/Dropbox/hywiki/`, set before Hyperbole loads in
  `~/.emacs.d/elisp/init-hyperbole.el`.
- `hyperbole-mode` and `(hywiki-mode :all)` are enabled in the running Emacs.

Always use the running Emacs server for writes so Denote metadata, buffers, and
HyWiki caches remain coherent.

Periodic and full-corpus scans select standard Denote Org filenames by identifier,
not by `ai`, `report`, or other keywords. Keyword filtering is optional and must be
explicit.

`~/Dropbox` is the Git repository containing both `notes/` and `hywiki/`. Every
Denote Scribe run makes a local path-scoped commit through synchronous Magit APIs.
A literal `🔒` in the commit subject marks a successful HyWiki extraction and
resets the five-commit cadence. There are no HyWiki trailers. Never infer
permission to push.

## HyWiki constraints

Hyperbole stores one Org file per page directly below `hywiki-directory`.
`hywiki-word-is-p` validates a page name. A normal page name starts with an
uppercase letter, contains letters only, and becomes `PageName.org`. Spaces,
hyphens, underscores, digits, and non-Latin names are unsuitable as canonical
page names in the installed HyWiki interface.

Relevant public functions from the installed `hywiki.el`:

- `(hywiki-add-page PAGE-NAME &optional FORCE-FLAG)` returns
  `(page . "/absolute/PageName.org")` and creates the file when needed.
- `(hywiki-get-existing-page-file PAGE-NAME)` returns an existing page path or nil.
- `(hywiki-get-page-files)` lists recognized page files.
- `(hywiki-find-page &optional PAGE-NAME)` displays or creates a page.

The bundled helper wraps `hywiki-add-page`, writes through a visited buffer, and
protects existing non-empty pages from accidental replacement.

## Links and provenance

Within HyWiki Org pages:

- Plain existing `HyWikiWord` text is automatically active.
- `[[hy:HyWikiWord]]` is the explicit Org link form.
- `HyWikiWord#Section-Name` links to a section.
- Use `[[denote:IDENTIFIER][Description]]` to retain provenance to a Denote note.

Do not use a HyWiki page as a transcript. Keep temporal investigation detail in
Denote and write only the durable definition, reasoning, boundaries, relations,
and provenance into HyWiki.
