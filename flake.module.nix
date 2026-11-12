{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      gitHash = inputs.self.shortRev or (inputs.self.dirtyShortRev or "unknown");
      sharedPkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [ inputs.haskell-nix.overlays.github ];
      };
      haskellPackages = sharedPkgs.haskell.packages.ghc9124.override (old: {
        overrides = pkgs.lib.composeExtensions (old.overrides or (_: _: { })) (hfinal: _hprev: {
          hurl-workbench-core = pkgs.haskell.lib.dontCheck (hfinal.callCabal2nix "hurl-workbench-core" ./hurl-workbench-core { });
          hurl-workbench-cli = pkgs.haskell.lib.dontCheck (hfinal.callCabal2nix "hurl-workbench-cli" ./hurl-workbench-cli { });
        });
      });
      corePackage = haskellPackages.hurl-workbench-core;
      cliPackage = pkgs.haskell.lib.overrideCabal haskellPackages.hurl-workbench-cli (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--ghc-option=-DGIT_HASH=\"${gitHash}\""
        ];
      });
    in
    {
      haskellProject.extraDevPackages = [
        pkgs.curl
        pkgs.hurl
        pkgs.python3
        pkgs.ripgrep
      ] ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.procps;

      # Release checks need the pinned compiler and CLI tools, while the editor
      # language server adds a large unrelated source build on fresh Linux hosts.
      devShells.check = inputs.haskell-nix-dev.lib.${system}.mkDevShell {
        ghc = "ghc9124";
        withHls = false;
        extraNativeBuildInputs = [
          pkgs.zlib
          pkgs.just
          pkgs.pkg-config
          pkgs.curl
          pkgs.hurl
          pkgs.python3
          pkgs.ripgrep
        ] ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.procps;
      };

      packages.hurl-workbench-core = corePackage;
      packages.hurl-workbench-cli = cliPackage;
      packages.default = cliPackage;
    };
}
