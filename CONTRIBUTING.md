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

CI runs exactly these, with no cloud credentials:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

If you change a provider or module version, refresh the lock file for every
platform CI and contributors use, or CI's `-lockfile=readonly` init fails:

```bash
terraform providers lock \
  -platform=linux_amd64 -platform=linux_arm64 \
  -platform=darwin_arm64 -platform=darwin_amd64
```

## Ground rules

- **Design changes go through an ADR in mbeacom/adrkit.** This repository
  implements [ADR-0056](https://github.com/mbeacom/adrkit/blob/main/docs/adr/0056-ship-the-azure-deployment-surface-as-terraform-in-a-separate-repository-behind-a.md).
  A change that contradicts it (a write route, a public backend, tracking
  `latest`) needs that record amended first.
- **Mark provider facts.** When code relies on Azure behaviour, say in a
  comment whether it was verified (and where) or is unmeasured.
- **No credentials in this repository**, including in examples and state.
