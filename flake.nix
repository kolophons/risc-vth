{
  inputs.nixpkgs.url = "github:NixOS/nixpks/nixos-unstable";
  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.pkgsCross.riscv64-embedded.buildPackages.binutils
          pkgs.qemu
        ];
      };
    };
}
