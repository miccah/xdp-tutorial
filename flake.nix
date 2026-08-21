{
  description = "xdp";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
    };
    testHelper = pkgs.writeShellScriptBin "t" ''
      sudo bash /home/xdp/xdp/xdp-tutorial/testenv/testenv.sh "$@"
    '';
  in {
    devShells.${system}.default = pkgs.mkShell {
      # Disable hardening flags baked into the wrapped compiler.
      hardeningDisable = [ "all" ];
      # Suppress target bpf warnings from the wrapped compiler.
      # (The compiler still outputs bpf code).
      NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING = "1";
      # Use multi.dev include for gnu/stubs-32.h and disable the
      # unused-driver-arg diagnostic from the wrapped compiler.
      NIX_CFLAGS_COMPILE = "-idirafter ${pkgs.glibc_multi.dev}/include -Wno-unused-command-line-argument";
      packages = with pkgs; [
        # Add packages here.
        clang
        llvm
        elfutils
        libpcap
        m4
        perf
        gnumake
        linuxHeaders
        bpftools
        tcpdump
        pkg-config
        xdp-tools
        ethtool
        testHelper
      ];
    };
  };
}
