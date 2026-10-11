# Contributing

## Sign-off is required

All commits require a [DCO](https://developercertificate.org/) sign-off, as in
[mbeacom/adrkit](https://github.com/mbeacom/adrkit/blob/main/CONTRIBUTING.md).
There is no CLA.

```bash
git commit -s -m "your message"
```

That adds `Signed-off-by: Your Name <your@email>`. To sign off commits you
already made on a branch:

```bash
git rebase --signoff origin/main
git push --force-with-lease
```

GitHub's web editor does not add a sign-off.

## Before opening a pull request

Install the tools at the versions CI uses, then run the hooks:

| Tool | Version |
| --- | --- |
| Terraform | 1.13.3 (floor 1.10) |
| TFLint | 0.64.0 (plugins pinned in `.tflint.hcl`) |
| terraform-docs | 0.24.0 |
| Trivy | 0.75.0 |
| Checkov | 3.3.26 |
| ShellCheck | any recent |
| pre-commit | any recent |

```bash
pre-commit install          # once
pre-commit run --all-files  # fmt, tflint, terraform test, docs, trivy, checkov, shellcheck
```

CI also runs, with no cloud credentials, in the repository root, in
`examples/basic` and `examples/advanced`, and in each `measure/<root>`
directory:

```bash
terraform init -backend=false -lockfile=readonly
terraform validate
```

[AGENTS.md](./AGENTS.md) has the exact command list. Never run
`measure/run.sh` in CI: it creates billed resources (see
[`measure/README.md`](./measure/README.md)).

If you change an input's validation, add a case to
`tests/validation.tftest.hcl`. If you change a variable, output, or version
constraint, regenerate the docs:

```bash
for d in . modules/*/ examples/*/; do terraform-docs "$d"; done
```

If you change a provider or module version, refresh the lock file (the
root's, each `examples/<name>`'s, and each `measure/<root>`'s) for every
platform CI and contributors use, or CI's `-lockfile=readonly` init fails:

```bash
terraform providers lock \
  -platform=linux_amd64 -platform=linux_arm64 \
  -platform=darwin_arm64 -platform=darwin_amd64
```

A security finding is fixed, or suppressed inline next to the resource with
its reason (README, "Security scanning"); never in the scanner config files.

## Ground rules

- **Design changes go through an ADR in mbeacom/adrkit.** This repository
  implements [ADR-0056](https://github.com/mbeacom/adrkit/blob/main/docs/adr/0056-ship-the-azure-deployment-surface-as-terraform-in-a-separate-repository-behind-a.md).
  A change that contradicts it (a write route, a public backend, tracking
  `latest`) needs that record amended first.
- **Mark provider facts.** When code relies on Azure behaviour, say in a
  comment whether it was verified (and where) or is unmeasured.
- **No credentials in this repository**, including in examples and state.
