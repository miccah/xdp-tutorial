Notes for [xdp-tutorial](https://github.com/xdp-project/xdp-tutorial).


## Table of Contents

* [Setup Dependencies](#setup-dependencies)


## Setup Dependencies

The first step is to [setup dependencies](https://github.com/xdp-project/xdp-tutorial/blob/main/setup_dependencies.org).
I'm running this on NixOS, so let's try and figure out how to do that.

These were the packages I added to the flake:
```
clang llvm elfutils libpcap
m4 perf gnumake linuxHeaders
bpftools tcpdump pkg-config
```

But Nix wraps the std compiler with some hardening flags and other warnings, so
I also needed to disable those features, along with additional flags to find
the 32-bit headers. The full diff is
[here](https://github.com/miccah/xdp-tutorial/commit/b07a34ac486e17b1394bbf1ae0bd3d3fa91b4e58).

After those changes, I can now `./configure` and `make` successfully.
