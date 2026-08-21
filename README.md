Notes for [xdp-tutorial](https://github.com/xdp-project/xdp-tutorial).


## Table of Contents

* [Introduction](#introduction)
* [Setup Dependencies](#setup-dependencies)
* [Basic01: loading your first BPF program](#basic01-loading-your-first-bpf-program)
* [Basic02: loading a program by name](#basic02-loading-a-program-by-name)


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


## Basic02: loading a program by name

A BPF ELF file can contain more than one XDP program, and the **libxdp** API
can be used to select which one.

### Setting up the test lab

I added `t` as a program in my nix flake:

```nix
testHelper = pkgs.writeShellScriptBin "t" ''
  sudo bash /home/xdp/xdp/xdp-tutorial/testenv/testenv.sh "$@"
'';
```

```bash
# setup the virtual interface
t setup --name veth-basic02

# view
t status
ip link show veth-basic02
ip addr show veth-basic02

# remove
t teardown --name veth-basic02
```

My machine has IP address `fc00:dead:cafe:1::1` and apparently there is a peer
at `fc00:dead:cafe:1::2`.

```bash
ping -c4 fc00:dead:cafe:1::2
```

### Loading a program by name

This seems to be the part in `xdp_loader.c` that loads the program by name. We
initialize `xdp_opts` with the `DECLARE_LIBXDP_OPTS` macro before passing it to
`xdp_program__create`

```c
DECLARE_LIBXDP_OPTS(xdp_program_opts, xdp_opts,
		    .obj = obj,
		    .prog_name = cfg.progname);
struct xdp_program *prog = xdp_program__create(&xdp_opts);
```

Side note: I could not find docs on `xdp_program__create`. Not in `man libxdp`
and not on the Internet. Maybe it just passes through to a BPF program create
function.

Anyway, once it's built, we can load XDP programs by name using the custom
`xdp_loader` program.

```bash
sudo ./xdp_loader --help
sudo ./xdp_loader --dev veth-basic02
sudo ./xdp_loader --dev veth-basic02 --unload-all
sudo ./xdp_loader --dev veth-basic02 --progname xdp_drop_func
sudo ./xdp_loader --dev veth-basic02 --progname xdp_pass_func
```

Loading `xdp_drop_func` causes the `ping` to timeout!


### veth packet directions

> When you load an XDP program on the interface visible on your host machine,
> it will operate on all packets arriving to that interface. And since packets
> that are sent from one interface in a veth pair will arrive at the other end,
> the packets that your XDP program will see are the ones sent from within the
> network namespace (netns). This means that when you are testing, you should
> do the ping from within the network namespace that were created by the
> script.
>
> You can “enter” the namespace manually (via `sudo ip netns exec veth-basic02
> /bin/bash`)

I'm not sure I understand this section, mostly because `ping` from "outside"
the namespace works as expected. It responds and drops packets the way I would
expect when certain programs are loaded. Maybe it "works" because the ping goes
through fine, but on the way out it gets dropped?


### Add xdp_abort program

This seems pretty straightforward:

```c
SEC("xdp")
int xdp_abort_func(struct xdp_md *ctx)
{
	return XDP_ABORTED;
}
```

```bash
# load program by name
sudo ./xdp_loader --dev veth-basic02 --progname xdp_abort_func

# note that ping fails
ping -c4 fc00:dead:cafe:1::2
```

`XDP_ABORTED` is different from `XDP_DROP` in that it triggers the tracepoint
named `xdp:xdp_exception`. You can see this happening with `perf`:

```bash
sudo perf record -a -e xdp:xdp_exception sleep 4 &
ping -c2 fc00:dead:cafe:1::2
sudo perf script
```

```
ping   48888 [008] 27127.497657: xdp:xdp_exception: prog_id=1073 action=ABORTED ifindex=4
ping   48888 [008] 27128.546514: xdp:xdp_exception: prog_id=1073 action=ABORTED ifindex=4
```
