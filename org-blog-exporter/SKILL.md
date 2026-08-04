---
name: org-blog-exporter
description: >-
  Export or publish configured Org notes as static HTML through Emacs, including local resources
  and verified Git publication. Use only when the user explicitly requests export or publication.
---

# Org Blog Exporter

```text
publish? := user explicitly requests external publication
```

Invoke the facade with one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/org-blog-exporter.el")
  (org-blog-exporter-run REQUEST))
```

The facade owns source validation, authorization, asset planning, partial effects,
commit/push gates, recovery metadata, and completion verification.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

`publish` exports configured public Org sources, commits generated site files, and
pushes the configured upstream. Treat that full external effect as intentional only
when the user asked to publish; an export request alone never implies publication.
