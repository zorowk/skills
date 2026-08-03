---
name: org-blog-exporter
description: >-
  Export or explicitly publish configured Org notes as static HTML through Emacs, including local
  resources, generated commits, and pushes for authorized publishing.
---

# Org Blog Exporter

Every request is one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/org-blog-exporter.el")
  (org-blog-exporter-run REQUEST))
```

Replace `<skill-dir>` with this skill's directory and uppercase names with real
Elisp values. `REQUEST` is a plist beginning with `:operation`. Query exact
parameters before an unfamiliar operation:

```elisp
(org-blog-exporter-run
 (list :operation (quote describe) :target (quote publish)))
```

Explicit publish:

```elisp
(org-blog-exporter-run
 (list :operation (quote publish) :files FILES
       :authorization (quote explicit)))
```

Use only fields returned by `describe`. Do not inspect the script unless the entry
point fails.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

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
