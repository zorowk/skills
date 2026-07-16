# HyWiki API and links

Read only when changing HyWiki integration or composing links.

## HyWiki constraints

Relevant public functions from the installed HyWiki:

- `(hywiki-add-page PAGE-NAME &optional FORCE-FLAG)` returns
  `(page . "/absolute/PageName.org")` and creates the file when needed.
- `(hywiki-get-existing-page-file PAGE-NAME)` returns an existing page path or nil.
- `(hywiki-get-page-files)` lists recognized pages.

## Links and provenance

- Plain existing `HyWikiWord` text is automatically active.
- `[[hy:HyWikiWord]]` is the explicit Org link form.
- `HyWikiWord#Section-Name` links to a section.
- Use `[[denote:IDENTIFIER][Description]]` to retain provenance to a Denote note.
