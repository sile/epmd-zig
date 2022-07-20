epmd
====

EPMD (Erlang Port Mapping Daemon) client in Zig.

Examples
--------

```console
// Register a node.
$ zig run examples/register-node.zig --main-pkg-path ../ -- foo
Registered node: creation=1658309464

Please enter a key to terminate this process and to deregister the node.

// In another shell, get the above node information.
$ zig run examples/get-node.zig --main-pkg-path ../ -- foo
Node:
- name: foo
- port: 4321
- node_type: 72
- protocol: 0
- highest_version: 6
- lowest_version: 5
- extra:

// Get registered node list.
$ zig run examples/get-names.zig --main-pkg-path ../
name foo at port 4321
```
