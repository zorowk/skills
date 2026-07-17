---
name: org-blog-exporter
description: >-
  Export or explicitly publish configured Org notes as static HTML through Emacs, including local
  resources, generated commits, and pushes for authorized publishing.
---

# Org Blog Exporter

Load `scripts/org-blog-exporter.el` and call `org-blog-exporter-run` through the
running Emacs server. Keep compact results unless complete path lists are necessary.
Read `:data` and follow `:page :next-offset`; use `describe` only when needed.

Resolve ambiguous files before acting. Export needs no external authorization.
Publish only after an explicit user request and pass `:authorization explicit`;
nil `:files` means all public notes. Never bypass a program safety error manually.
