    # --- txindex bootstrap (fork-only addition) ---------------------------
    # Dogecoin Core 1.14 keeps the txindex inside blocks/index. A datadir
    # ever loaded WITHOUT -txindex (synced by the stock pup, or imported
    # from an external drive) keeps that empty index: later boots with
    # -txindex=1 only index NEW blocks, and getrawtransaction <old-txid>
    # fails with "No such mempool or blockchain transaction". The only fix
    # is one -reindex pass over the local block files.
    #
    # Rule: boot with -reindex until the datadir proves it has a complete
    # index. Proof is either of:
    #   a) "Reindexing finished" in debug.log (a reindex boot completed), or
    #   b) the .txindex-verified stamp written by the watcher below
    #      (functional RPC proof: ancient txid resolvable AND chain at tip).
    # The stamp lives in the datadir, so it travels with /storage across
    # pup updates (README storage-copy trick). A reindex boot keeps RPC up
    # the whole time, so consumers see chain progress throughout.
    # ----------------------------------------------------------------------
    REINDEX_FLAG=""
    if [ -f ${storageDirectory}/.txindex-verified ] || \
       grep -q "Reindexing finished" ${storageDirectory}/debug.log 2>/dev/null; then
        echo "txindex-bootstrap: index verified — normal boot"
    else
        echo "txindex-bootstrap: no completed txindex found — booting with -reindex (one-time, can take hours)"
        REINDEX_FLAG="-reindex"
    fi

    if [ -n "$REINDEX_FLAG" ]; then
    (
        # Watcher: stamp once the index is PROVEN complete — both an ancient
        # txid resolvable via RPC and the chain caught up past the probe
        # height. (Block 1,000,000's coinbase is a permanent chain fact;
        # its txid is fixed forever.) No curl in the container? Harmless:
        # the "Reindexing finished" marker in debug.log covers future boots.
        command -v curl >/dev/null 2>&1 || exit 0
        n=0
        while [ $n -lt 2880 ]; do   # 48h ceiling, then give up silently
            tip=$(echo '{"jsonrpc":"1.0","id":"c","method":"getblockcount","params":[]}' | \
                curl -s -m 5 --user "$RPCUSER:$RPCPASS" \
                  -H 'Content-Type: application/json' -d @- \
                  "http://$DBX_PUP_IP:22555/" 2>/dev/null | \
                  grep -o '"result":[0-9]*' | cut -d: -f2)
            ok=$(echo '{"jsonrpc":"1.0","id":"c","method":"getrawtransaction","params":["bc06dcc8c8841728b905fa45e4d21ed460a2e136bb0545fcf2906a149e704bb9"]}' | \
                curl -s -m 5 --user "$RPCUSER:$RPCPASS" \
                  -H 'Content-Type: application/json' -d @- \
                  "http://$DBX_PUP_IP:22555/" 2>/dev/null | \
                  grep -c '"error":null')
            if [ -n "$tip" ] && [ "$tip" -ge 6400000 ] 2>/dev/null && [ "$ok" = "1" ]; then
                touch ${storageDirectory}/.txindex-verified
                echo "txindex-bootstrap: functional RPC proof passed — stamping datadir as verified"
                break
            fi
            n=$((n+1))
            sleep 60
        done
    ) &
    fi

