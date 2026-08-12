# RFC: `sora provide`

**Status: proposal.** Nothing here is implemented in sora. It is written up
because the evidence behind it already exists and would otherwise be lost: two
working reference implementations, measured on real hardware, plus the traps
found while getting them to work.

Reference implementations and raw notes: the `extras/` directory of
`sora-adv-br`, a small project that bridges Brazilian e-signature tooling
(SafeSign, SafeNet, Lacuna, Softplan, Certisign) from a Debian box to a Fedora
host.

Test environment for everything claimed below: host Fedora 44 (p11-kit
0.26.5), box Debian trixie (p11-kit 0.25.5), distrobox 1.8.2.5, podman
rootless with `keep-id`.

## The problem

sora resolves host to container for **commands**: the user types, the command
runs in the box. But much of what people actually want out of a box is never
typed by anyone. It is looked up by a host program at its own integration
point: a browser looking for a signing helper, NSS looking for a PKCS#11
module, the desktop looking for a MIME handler.

In those cases the `sora anxious` wrapper is already the right executable.
What is missing is **registering that wrapper at the host's integration
point**.

## The observation that generalizes

Three bridges, one shape:

| Bridge | Transport | What gets written on the host |
|---|---|---|
| `.desktop` entry (implemented, `anxious --desktop`) | process exec | `~/.local/share/applications/*.desktop`, field `Exec=` |
| Signing helpers (Lacuna, Softplan, Certisign) | stdio, via the `anxious` wrapper | native-messaging manifest in the browser profile, field `path` |
| Token driver (PKCS#11) | stdio, via `p11-kit remote` | `~/.config/pkcs11/modules/*.module`, field `remote:` |

The mechanism is identical every time: **a host configuration file whose "run
this" field points at a wrapper that enters the box.** Only the file format
and its location change.

That is the argument for one command with adapters rather than `sora pkcs11`,
`sora native-messaging`, and so on:

```console
$ sora provide native-messaging com.lacunasoftware.webpki --box adv-br
$ sora provide pkcs11 /usr/lib/libaetpkss.so --box adv-br --label safesign
$ sora provide list
$ sora provide remove pkcs11 --box adv-br --label safesign
```

One mechanism (create the wrapper, write the file, know how to undo it) and
one adapter per integration point. Further candidates, in rough order of
plausibility: user systemd socket units, xdg/MIME handlers beyond what
`--desktop` covers, SSH agent, D-Bus services.

Much of the transport is already free. distrobox shares `/run/user/$UID`,
`/tmp` and the network stack, so unix sockets and local ports cross with
nobody doing anything (PJeOffice, which listens on a local port, works from
the host browser with no configuration at all). What is missing is the
host-side registration, the lifecycle, and the undo.

## Relationship to `anxious --desktop`

`anxious --desktop` is the first adapter of this shape, arrived at
independently, before the generalization was written down. That is the main
reason to believe the generalization is real rather than tidy.

It should **stay where it is**. `provide` and `--desktop` share the mechanism
underneath (the wrapper, the registry, the undo path) and stay separate at the
CLI, because a desktop entry is what an ordinary user wants without ever
learning the phrase "integration point". Renaming a shipped command to make a
taxonomy come out even is churn paid by users.

## Prerequisites in `anxious`

Both adapters need two things sora does not do yet. The reference
implementations worked around the first and were bitten by the second.

**1. Export by path, under a chosen name.** `anxious` can only export a
command name resolvable in the box's `PATH`. Integration binaries usually live
outside it (`/opt/lacuna-webpki/webpki`), so `ponte-assinadores.sh` has to
`ln -sf` into `/usr/local/bin` **as root inside the box** just to give the
binary a name sora can see. That workaround should not survive into a
built-in: something like `sora anxious --path /opt/lacuna-webpki/webpki --as
webpki-lacuna --box adv-br`.

**2. Refusal to shadow a host binary.** This is a hole in the project's
headline claim, not just an adapter concern. "Host binaries always win" is
*structural* for late resolution (the hook only fires after `PATH` already
missed) but is **not** enforced for eager export: `cmd_anxious` resolves the
name inside the box and writes into `~/.local/bin`, which usually precedes
`/usr/bin`, without ever asking whether that name already exists on the host.
Exporting `webpki` silently hijacks the host's `webpki`.

Adapters should also pick distinct names by default (`webpki-lacuna`, not
`webpki`).

## Why not "any library"

The next temptation is to generalize downward: use any `.so` from the box on
the host. This is not reachable, and it is worth knowing why before trying.

PKCS#11 is remotable by a happy accident of design: a stable function table,
coarse granularity, no callbacks into the caller's memory, and well-defined
memory ownership. That is why someone was able to write a marshalling protocol
for it, and they had to write it by hand, function by function. For an
arbitrary `.so`, a generic marshalling of the C ABI means serializing
pointers, nested structs, callbacks and threading semantics with no contract
saying what is input, what is output, and who owns which allocation. There is
no shortcut: it would need an IDL per interface, which is precisely what
PKCS#11 already had in practice.

The correct generalization is therefore upward, at the integration point, not
downward at the ABI.

## The PKCS#11 adapter

p11-kit has had remoting since 2017, built to forward a token over SSH. A
module configuration (`~/.config/pkcs11/modules/<name>.module`) accepts:

```
remote: |<command speaking the remoting protocol on stdin/stdout>
```

The documented example is `|ssh user@remote p11-kit remote /path/module.so`.
Swapping `ssh` for `distrobox enter` solves the whole problem:

```
remote: |/usr/bin/distrobox enter --name adv-br -- p11-kit remote /usr/lib/libaetpkss.so
```

Verified: the binary channel crosses `distrobox enter` intact (byte-for-byte
comparison of a message containing `\r\n` and `NUL`, identical hash), and
`distrobox-enter` sends its progress messages to stderr, so stdout stays clean
for the protocol. The native-messaging adapter relies on the same property.

On the host side, NSS consumers (Chromium, Brave, Chrome) need
`p11-kit-proxy.so` registered in `~/.pki/nssdb`; it is the proxy that reads
the `.module` files and reaches the drivers in the box.

### Result

`p11-kit list-modules` on the host, with the driver existing only inside the
container and **nothing installed on the host**:

```
module: sora-adv-br-safesign
    path: (null)
    uri: pkcs11:library-description=Cryptographic%20Token%20Interface;library-manufacturer=A.E.T.%20Europe%20B.V.
    library-description: Cryptographic Token Interface
    library-manufacturer: A.E.T. Europe B.V.
    library-version: 3.0
```

With Debian's trust module standing in for the driver (to get slots without
depending on hardware), the host enumerated **150 certificate objects** across
the RPC, with the slot labelled `/etc/ssl/certs/ca-certificates.crt`, a Debian
path, and `hardware version 0.25`, the box's p11-kit version. Objects, slots
and tokens all cross; `C_Login` and `C_Sign` use the same channel.

## The native-messaging adapter is not a template

A browser signing helper is not a library loaded into the browser. It is a
separate program the browser executes and talks to over stdin/stdout
(Chromium's native messaging: 4 length bytes plus JSON). The program loads the
PKCS#11 module and talks to the token, so if the program runs in the box it
uses the box's driver and reaches the token through the host's `pcscd`. The
host browser only needs to know how to execute it.

This adapter carries real logic, unlike the PKCS#11 one:

- it must discover which browser profiles actually exist on the host (Brave
  Origin, Brave Browser, Chrome, Chromium, plus Firefox in a different
  directory);
- Chromium and Firefox use different manifest formats (`allowed_origins`
  versus `allowed_extensions`);
- the manifest must be copied **out of the box** with only `path` rewritten.
  `allowed_origins` binds the manifest to the extension's ID and cannot be
  invented.

Worth stating plainly so the estimate is not made twice: the mechanism/adapter
split holds, but "an adapter is a twenty-line template" is true only for
PKCS#11.

## Traps found

1. **`modutil -add` loads the library; `-rawadd` does not.** Registering the
   host's `p11-kit-proxy.so` using the box's `modutil` fails, because
   `modutil` tries to load a Fedora `.so` inside Debian. `-rawadd` only writes
   the line into `pkcs11.txt`, which is what is wanted. This also avoids
   installing `nss-tools` on the host: the box's `modutil` writes to the
   host's NSS database, mounted at the same absolute path and using the same
   `sql:` format.

2. **The executable path in the configuration file must be absolute.** True
   for every adapter: the browser is started from the desktop menu, with a
   `PATH` that frequently does not include the distrobox directory. This is
   the same reason `anxious --desktop` writes an absolute `Exec=`.

3. **The PID namespace is shared with the host.** A `pkill -f "p11-kit
   server"` run inside the box kills host processes, including the very shell
   whose command line contains that text. This cost two sessions during
   testing. Any stop routine must match by PID, never by command-line pattern.
   This one deserves a place in [architecture.md](architecture.md)'s pitfalls
   regardless of whether `provide` is ever built.

4. **A p11-kit version mismatch does not matter.** Debian 0.25.5 as server and
   Fedora 0.26.5 as client talked with no adjustment. The reported version is
   in fact how you tell the two sides apart (Cryptoki 3.0 from the box, 3.2
   from the host).

5. **A module can abort on load.** SerproID's `libneoidp11.so` kills the
   loading process with SIGSEGV unless its application is authenticated. An
   adapter must not validate a module by loading it, and if it ever does, it
   should isolate with `ulimit -c 0` rather than fill the machine with core
   dumps.

6. **Latency.** Every use starts a `distrobox enter`: 2.3 s with the container
   stopped, 1.4 s warm, measured on the test machine. Fine for a browser's
   lifecycle, noticeable for a command-line tool that opens and closes the
   resource per invocation.

7. **Security.** Publishing a box resource gives any host application the same
   access it would have if the resource were local. That is equivalent, not
   worse, but it belongs in the documentation, because people reach for
   containers expecting the opposite.

## Alternative design, evaluated and rejected

For the PKCS#11 adapter: `p11-kit server` plus a unix socket. It works.
distrobox mounts the host's `/run/user/$UID` into the box, so a server started
in the box creates a socket the host can see, and if the socket is created at
the default path (`$XDG_RUNTIME_DIR/p11-kit/pkcs11`) the host client finds it
with **no environment variable at all** (verified).

Rejected because it requires the `p11-kit-client` package on the host (with
`remote:`, the `p11-kit-proxy.so` from base p11-kit is enough), requires a
live daemon with its own lifecycle (a user systemd unit, restart after
reboot), and the default path is singular: two boxes cannot publish modules at
the same time. `remote:` has none of those problems. It starts on demand, dies
with its consumer, and scales to as many modules as you like.

Worth keeping as a documented fallback for consumers that do not go through
p11-kit, and it is the shape any future socket adapter would use anyway.
