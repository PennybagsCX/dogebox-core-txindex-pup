# Dogecoin Core (txindex) — Dogebox pup

<p align="center"><img src="docs/banner.jpg" width="100%" alt="Dogecoin Core (txindex) banner"></p>
<p align="center"><img src="docs/logo.png" width="96" alt="Dogecoin Core (txindex) logo"></p>

Fork of the [Dogebox-WG `core` pup](https://github.com/Dogebox-WG/pups/tree/main/core) that runs Dogecoin Core v1.14.9 with **`txindex=1`**, enabling by-transaction lookups (`getrawtransaction` for any txid) for indexers, explorers and analytics.

## Differences from upstream core pup

The `dogecoind` invocation in `core-txindex/pup.nix` differs in two ways:

```
-txindex=1        # always on — the point of this pup
$REINDEX_FLAG     # -reindex on first boot only, until the index is verified
```

Plus a bootstrap block before the invocation (`scripts/bootstrap-fragment.sh`):

- If the datadir has no completed index (no `Reindexing finished` in `debug.log` and no `.txindex-verified` stamp), the pup boots **once with `-reindex`** — a one-time pass over the local block files that can take hours. RPC and the chain tip stay live during the rebuild, so consumers keep working.
- A background watcher stamps the datadir (`.txindex-verified`) once the index is *functionally* proven: an ancient fixed txid resolves via RPC **and** the chain has caught up. The stamp travels with `/storage`, so pup updates never re-trigger the rebuild.

Why the bootstrap exists: Dogecoin Core 1.14 stores the txindex in `blocks/index`. A datadir ever synced/imported **without** `-txindex` keeps that empty index — later boots with `txindex=1` only index *new* blocks and `getrawtransaction <old-txid>` fails with `No such mempool or blockchain transaction`. Without the bootstrap this failure is silent; with it, the pup self-heals on first boot.

Everything else (monitor, logger, interfaces, metrics, ports) is identical, so this pup is a drop-in provider for the `core-rpc` / `core-zmq` / `core-network` interfaces — pups depending on Core can bind to it instead of the stock pup.

## Cost

A txindex node uses roughly **2× the disk** of a standard node (~200 GB vs ~100 GB at current height, growing).

## Install (as a Pup Source)

Dashboard → Pup Store → Manage Sources → add this repo's URL (or a local path on the box), then install "Dogecoin Core (txindex)".

### Avoiding a re-sync when replacing an existing node

If you already run the stock core pup with an indexed datadir, you can seed this pup's storage with it: stop both pups, copy `/opt/dogebox/pups/storage/<old-hash>/` into the new pup's storage dir, start. Same chain → no reindex, no resync.

## Maintenance — automated

This fork tracks upstream automatically:

- `scripts/sync-upstream.sh` — clones `Dogebox-WG/pups`, re-applies the one-line txindex patch to upstream's `pup.nix`, refreshes monitor/logger/logo assets, recomputes the manifest hash, and bumps the patch version. Bails loudly (instead of guessing) if upstream's flags change shape or ship txindex natively.
- `.github/workflows/sync-upstream.yml` — runs the script weekly (Mon 04:23 UTC); commits + tags + pushes when upstream moves.

So when Dogecoin Core (or the pup format) updates upstream, this repo follows within a week with zero human steps. The Dogebox Pup Store then offers the update on your box like any other pup.

## Status

Dev-tier, tested on Dogebox OS beta (NanoPC-T6).

## License

MIT for the packaging. This repo packages and forks the Dogecoin Foundation's `core` pup (https://github.com/Dogebox-WG/pups) and Dogecoin Core. Those projects and their assets remain the property of their respective owners and are subject to their own licenses.
