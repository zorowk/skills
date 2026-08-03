---
name: org-blog-exporter
description: >-
  Export or publish configured Org notes as static HTML through Emacs, including local resources
  and verified Git publication. Use only when the user explicitly requests export or publication.
---

# Org Blog Exporter

## Decision summary

```text
export?  := explicit export or publish request
publish? := explicit publish request AND explicit authorization
mutate?  := explicit authorization AND unambiguous sources
            AND requested operation permits its effects
done?    := requested outputs and repository effects pass verification
```

Invoke the facade with one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/org-blog-exporter.el")
  (org-blog-exporter-run REQUEST))
```

Replace `<skill-dir>` and uppercase placeholders with real Elisp values.
`REQUEST` is a plist beginning with `:operation`. Describe an unknown operation:

```elisp
(org-blog-exporter-run
 (list :operation (quote describe) :target (quote publish)))
```

Explicit publish:

```elisp
(org-blog-exporter-run
 (list :operation (quote publish)
       :files (list "/home/alice/notes/emacs-startup.org")
       :title "publish Emacs startup note"
       :notes-dir "/home/alice/notes/"
       :repository-dir "/home/alice/site/"
       :setupfile "/home/alice/notes/setupfile.org"
       :authorization (quote explicit)))
```

Use existing public Org files below `:notes-dir`.  `publish` exports them,
commits generated files in `:repository-dir`, and pushes the configured
upstream.

## Execution and recovery

Call documented operations directly. Use `describe` only when the schema is
unknown or after the first `invalid-request`; revise and retry once. A second
invalid request stops the goal. On `partial`, preserve returned evidence and
effects, then retry only the safe remainder.

`stop` means no further facade calls for the blocked goal in this turn. If safe
recovery is unclear, report observed effects and the remaining goal, then stop.

When `describe` is used, send only fields declared by the returned schema. Inspect
the script only if the entry point fails.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

## Completion

Resolve ambiguous files before acting. Never bypass a facade safety error.

```text
export_done :=
  every source has an existing output
  AND public-note policy passed
  AND rewritten asset links passed

publish_allowed := user explicitly requested publish
publish_done :=
  publish_allowed
  AND export_done
  AND index and planned assets verified
  AND path-scoped commit exists when changes occurred
  AND upstream commit = pushed commit
```

Use `:verification`, not tool-call success, as completion evidence.

If index generation fails, do not commit or push. A resource or index failure after
HTML generation is partial success: report effects, leave commit and push unset,
and do not retry the whole publish blindly.
