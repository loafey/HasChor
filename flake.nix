{
  description = "HasTEEProcedureCall";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";
  outputs = { self, nixpkgs }:
    let
      lastModifiedDate = self.lastModifiedDate or self.lastModified or "19700101";
      version = builtins.substring 0 8 lastModifiedDate;
      supportedSystems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
    in
    {
      devShells = forAllSystems
        (system:
          let pkgs = nixpkgsFor.${system}; in {
            default = pkgs.mkShell
              {
                buildInputs = with pkgs; [
                  zlib
                  haskellPackages.cabal-install
                  haskellPackages.fourmolu
                  haskellPackages.ghc
                  haskellPackages.ghcid
                  pkgs.haskell-language-server
                  botan3.dev
                ];
                shellHook = ''
                  export C_INCLUDE_PATH="${pkgs.botan3.dev}/include/botan-3"
                '';
              };
          });
      defaultPackage = forAllSystems (system: self.packages.${system}.dit313);
    };
}
