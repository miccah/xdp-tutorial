Notes for [xdp-tutorial](https://github.com/xdp-project/xdp-tutorial).


## Table of Contents

* [Introduction](#introduction)
* [Setup Dependencies](#setup-dependencies)
* [Basic01: loading your first BPF program](#basic01-loading-your-first-bpf-program)


## Introduction

eXpress Data Path (XDP) is a type of *extended Berkley packet filter* (eBPF)
that runs in the Linux kernel. It's a special type of program that runs very
early in the networking stack, usually before the kernel processes any packets.

eBPF (and therefore XDP) must pass extra checks when compiling to ensure there
is no unsafe memory access or other unbounded behavior.


## Setup Dependencies

The first step is to [setup dependencies](https://github.com/xdp-project/xdp-tutorial/blob/main/setup_dependencies.org).
I'm running this on NixOS, so let's try and figure out how to do that.

These were the packages I added to the flake:
```
clang llvm elfutils libpcap
m4 perf gnumake linuxHeaders
bpftools tcpdump pkg-config
xdp-tools
```

But Nix wraps the std compiler with some hardening flags and other warnings, so
I also needed to disable those features, along with additional flags to find
the 32-bit headers. The full diff is
[here](https://github.com/miccah/xdp-tutorial/commit/b07a34ac486e17b1394bbf1ae0bd3d3fa91b4e58).

After those changes, I can now `./configure` and `make` successfully.


## Basic01: loading your first BPF program

The simplest XDP program which does nothing!

```c
/* SPDX-License-Identifier: GPL-2.0 */
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>

SEC("xdp")
int  xdp_prog_simple(struct xdp_md *ctx)
{
	return XDP_PASS;
}

char _license[] SEC("license") = "GPL";
```

The object dump shows the file-format is bpf and `XDP_PASS` has a value of
`0x2`.

```bash
llvm-objdump -S xdp_pass_kern.o
```

```
xdp_pass_kern.o:	file format elf64-bpf

Disassembly of section xdp:

0000000000000000 <xdp_prog_simple>:
; 	return XDP_PASS;
       0:	b4 00 00 00 02 00 00 00	w0 = 0x2
       1:	95 00 00 00 00 00 00 00	exit
```

### Loading

The BPF bytecode is stored in an ELF file. To load it into the kernel, a
user-space program needs to read the file and pass it to the kernel in the
correct format.

**libbpf** provides an ELF loader and helper functions. It implements bytecode
relocation via a thing called
[CO-RE](https://nakryiko.com/posts/bpf-core-reference-guide/) which stands for
*compile-once, run everywhere*.

**libxdp** builds on top of **libbpf** by adding helper functions for XDP
programs, and it installs programs using the XDP multi-dispatch protocol.
This protocol essentially introduces a chain of XDP programs that run sort of
like middleware.

There are many practical ways to load a program, such as via the `ip` command,
the `xdp-loader` command, or even [a custom loader written by the tutorial
author](https://github.com/xdp-project/xdp-tutorial/blob/main/basic01-xdp-pass/xdp_pass_user.c).


#### Loading via ip

`ip` does not implement the XDP multi-dispatch protocol, so you can only attach
one XDP program to a device at a time.

```bash
# load
sudo ip link set dev lo xdpgeneric obj xdp_pass_kern.o sec xdp

# view
sudo ip link show dev lo

# unload
sudo ip link set dev lo xdpgeneric off
```

```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 xdpgeneric qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    prog/xdp id 590 name xdp_prog_simple tag d4f8542f2b42fac5 jited
                         ^^^^^^^^^^^^^^^
```

#### Loading via xdp-loader

Notice that the top level program is `xdp_dispatcher`. We also load it in
**skb** mode, which means "socket buffers." It's a fallback way to run programs
for any network device that does not have specific XDP support. It's less
effecient since it copies the packets into user-space.

```bash
# load
sudo xdp-loader load -m skb lo xdp_pass_kern.o

# view
sudo xdp-loader status lo

# unload
sudo xdp-loader unload -i 867 lo

# unload all
sudo xdp-loader unload -a lo
```

```
CURRENT XDP PROGRAM STATUS:

Interface        Prio  Program name      Mode     ID   Tag               Chain actions
--------------------------------------------------------------------------------------
lo                     xdp_dispatcher    skb      858  ba2e1a15f08cd656
 =>              50     xdp_prog_simple           867  d4f8542f2b42fac5  XDP_PASS
```


#### Loading with xdp_pass_user

`xdp_pass_user` is the loader provided by the tutorial. It was included to help
show how to integrate XDP into other OSS projects.

```bash
# load
sudo ./xdp_pass_user --dev lo

# view (using other tools)
sudo xdp-loader status lo
sudo ip link list dev lo
sudo bpftool net list dev lo

# unload
sudo ./xdp_pass_user --dev lo -U 896

# unload all
sudo ./xdp_pass_user --dev lo --unload-all
```
