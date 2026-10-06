{ pkgs ? import <nixpkgs> {} }:

let
  storageDirectory = "/storage";
  dogecoind_bin = pkgs.callPackage (pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/Dogebox-WG/dogebox-nur-packages/6531e850a6e964a9cd4c36671cb9b3b7414d8044/pkgs/dogecoin-core/default.nix";
    sha256 = "sha256-bSl/IKyAV2Gnh7TNDISBVxouQTdI5jmDqTfs6qfdz2w=";
  }) {
    disableWallet = true;
    disableGUI = true;
    disableTests = true;
    enableZMQ = true;
  };

  dogecoind = pkgs.writeScriptBin "run.sh" ''
    #!${pkgs.stdenv.shell}
    if [ ! -f /storage/rpcuser.txt ] || [ ! -f /storage/rpcpassword.txt ]; then
        RPCUSER=dogebox_core_pup_temporary_static_username
        RPCPASS=dogebox_core_pup_temporary_static_password

        echo "$RPCUSER" > /storage/rpcuser.txt
        echo "$RPCPASS" > /storage/rpcpassword.txt
    else
        RPCUSER=$(cat /storage/rpcuser.txt)
        RPCPASS=$(cat /storage/rpcpassword.txt)
    fi
    
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

    ${dogecoind_bin}/bin/dogecoind \
      -port=22556 \
      -datadir=${storageDirectory} \
      -rpc=1 \
      -rpcuser=$RPCUSER \
      -rpcpassword=$RPCPASS \
      -rpcbind=$DBX_PUP_IP \
      -rpcport=22555 \
      -rpcallowip=0.0.0.0/0 \
      -txindex=1 \
      -zmqpubhashblock=tcp://0.0.0.0:28332 $REINDEX_FLAG
  '';

  monitor = pkgs.buildGoModule {
    pname = "monitor";
    version = "0.0.1";
    src = ./monitor;
    vendorHash = null;

    systemPackages = [ dogecoind_bin ];
    
    buildPhase = ''
      export GO111MODULE=off
      export GOCACHE=$(pwd)/.gocache
      go build -ldflags "-X main.pathToDogecoind=${dogecoind_bin}" -o monitor monitor.go
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp monitor $out/bin/
    '';
  };

  logger = pkgs.buildGoModule {
    pname = "logger";
    version = "0.0.1";
    src = ./logger;
    vendorHash = null;

    buildPhase = ''
      export GO111MODULE=off
      export GOCACHE=$(pwd)/.gocache
      go build -ldflags "-X main.storageDirectory=${storageDirectory}" -o logger logger.go
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp logger $out/bin/
    '';
  };
in
{
  inherit dogecoind monitor logger;
}
