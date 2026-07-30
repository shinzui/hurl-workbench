# hurl-workbench

> A Haskell-powered Hurl workbench for composing, exploring, executing, and testing reusable API workflows without duplicating request templates.

## Layout

This project is split into two cabal packages:

- **`hurl-workbench-core`** — the library. Domain types, business logic, and
  the project-wide `HurlWorkbench.Prelude` that re-exports
  [`lens`](https://hackage.haskell.org/package/lens) and
  [`generic-lens`](https://hackage.haskell.org/package/generic-lens).
- **`hurl-workbench-cli`** — the command-line interface. Exposes
  `HurlWorkbench.Cli.runCli` and ships an executable named
  **`hurl-workbench`** that just calls it.

Both packages target **GHC `ghc9124`** with `default-language: GHC2024`
and the same warning set + default extensions
(`DeriveAnyClass`, `DuplicateRecordFields`, `OverloadedLabels`, `OverloadedStrings`).

## Develop

The project ships a Nix flake (`nix-haskell-flake`) that pins GHC and provides
the dev shell. Enter the shell with:

```bash
nix develop      # or: direnv allow, if you use direnv
```

To add dev-shell tools or extra flake outputs, copy `flake.module.nix.example` to
`flake.module.nix` and edit it. It is imported automatically and is never overwritten
by template upgrades, so your customizations there survive `nix-haskell-flake` updates.

Then build and run:

```bash
cabal build all
cabal run hurl-workbench -- hello --name world
```

## License

[BSD-3-Clause](./LICENSE) — (c) 2026 Nadeem Bitar.
