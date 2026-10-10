# Security

This repository follows the adrkit security policy. Report vulnerabilities as
described in
[mbeacom/adrkit SECURITY.md](https://github.com/mbeacom/adrkit/blob/main/SECURITY.md),
and say that the report concerns `mbeacom/adrkit-azure`.

Do not open a public issue for a vulnerability.

Two properties of this deployment are security boundaries rather than
features. A report that either can be broken is in scope:

- The adrkit server authenticates no one (ADR-0055 clause 14). It must be
  reachable only through APIM. A path to the Container Apps app that bypasses
  APIM is a vulnerability.
- The deployment is read-only. A published route, MCP tool, or job that can
  change a decision record is a vulnerability.
