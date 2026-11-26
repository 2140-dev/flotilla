# flotilla

NixOS host configurations for the 2140.dev fleet. Consumes
[roost](https://github.com/2140-dev/roost) for the public Frigate
silent-payments server stack, and ships per-host configurations
for the bare-metal Hetzner machines that run it.

## Hosts

- **kingfisher** — production silent-payments server (all-in-one).
  Runs bitcoind, Fulcrum and Frigate (GPU scanning on an RTX 4000
  SFF Ada); publishes `frigate.2140.dev:50002` over TLS.
- **albatross** — frigate-edge serving `frigate.2140.dev` until the
  cutover to kingfisher; backends on finney over the WireGuard mesh.
  Retiring after cutover.
- **finney** — bitcoind + Fulcrum backend for albatross, reachable only
  on the mesh. Leaving the fleet after cutover.

## Layout

```
modules/common.nix     operator-wide settings (state version, ZFS, openssh, gc, josie's user)
modules/frigate-watchdog.nix  restart-on-wedge safety net for frigate (imported per host)
hosts/<name>/          per-host config: disko layout, hardware, host-specific services
secrets/secrets.nix    agenix recipient registry
flake.nix              consumes roost, defines nixosConfigurations
```

## Deploy a host

From a fresh Hetzner box:

```
nix run github:nix-community/nixos-anywhere -- \
  --flake .#<host> \
  root@<host-ip>
```

Subsequent updates:

```
nixos-rebuild switch --flake .#<host> --target-host root@<host-ip>
```

## Binary cache

Pre-built outputs are pulled from `https://2140-dev.cachix.org`,
including the Frigate package from `roost`. Configure once:

```
cachix use 2140-dev
```

## Tests

`nix flake check` builds each host's toplevel system. CI runs the
same builds against the cache.

## License

MIT. See [LICENSE](LICENSE).
