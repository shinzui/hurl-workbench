{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      gitHash = inputs.self.shortRev or (inputs.self.dirtyShortRev or "unknown");
      hackagePackage =
        hfinal: name: version: hash:
        pkgs.haskell.lib.dontCheck (
          hfinal.callCabal2nix name
            (
              pkgs.fetchzip {
                url = "https://hackage.haskell.org/package/${name}-${version}/${name}-${version}.tar.gz";
                inherit hash;
              }
            )
            { }
        );
      haskellPackages = pkgs.haskell.packages.ghc9124.override {
        overrides = hfinal: _hprev: {
          aeson = hackagePackage hfinal "aeson" "2.2.5.1" "sha256-f1XeeVxXxoIVqHGNGUlbSL4LpF0jxjPlnC4XUpEf7C4=";
          generic-lens-core = hackagePackage hfinal "generic-lens-core" "2.3.0.0" "sha256-Abntgf3UMhQed5gOc6sDoVilMc0FRRCh8VJCeoQfNRY=";
          generic-lens = hackagePackage hfinal "generic-lens" "2.3.0.0" "sha256-V8M8gkbrrLAsJ42IKa26HnU28sfljwUZuBiCJBV8ABs=";
          http2 = hackagePackage hfinal "http2" "5.4.4" "sha256-ftdFX8cWOWKhCKa++vFkVBStW8q/uTVJIUvP55pkLv8=";
          http-semantics = hackagePackage hfinal "http-semantics" "0.4.1" "sha256-jzNgENa0Uj0ZGfg0N6zfbP2crSfRjBNpikKGgEl1hl4=";
          network = hackagePackage hfinal "network" "3.2.9.0" "sha256-ViRVmiVNjeZ2RB2MpGKiDdSDRxSGT328uChf72vdS+0=";
          optparse-applicative = hackagePackage hfinal "optparse-applicative" "0.19.0.0" "sha256-dhqvRILfdbpYPMxC+WpAyO0KUfq2nLopGk1NdSN2SDM=";
          recv = hackagePackage hfinal "recv" "0.1.2" "sha256-rV143/8NvBXGPkyDpJ45OxLJh0Tg9JGK+dX0uSJDmok=";
          time-manager = hackagePackage hfinal "time-manager" "0.3.2" "sha256-RSH3Uk/8mNVzXVSHhbPcfn3GVWqXUaWKUojJ7gtrXrs=";
          wai = hackagePackage hfinal "wai" "3.2.5" "sha256-Pmj0T7nVWbeJC2owVdM5gGUMSocVd2D0/lCKIy85Xp0=";
          warp = hackagePackage hfinal "warp" "3.4.16" "sha256-7RJ4GMwqSDszM/t6yadW6mQIAIMARX/khD0lf+UWVg8=";
          hurl-workbench-core = pkgs.haskell.lib.dontCheck (hfinal.callCabal2nix "hurl-workbench-core" ./hurl-workbench-core { });
          hurl-workbench-cli = pkgs.haskell.lib.dontCheck (hfinal.callCabal2nix "hurl-workbench-cli" ./hurl-workbench-cli { });
        };
      };
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
        pkgs.ripgrep
      ];

      packages.hurl-workbench-core = corePackage;
      packages.hurl-workbench-cli = cliPackage;
      packages.default = cliPackage;
    };
}
