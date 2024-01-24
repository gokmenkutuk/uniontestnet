#!/bin/bash

# Prompt for moniker
read -p "Enter your moniker: " MONIKER

# Install dependencies
sudo apt -q update
sudo apt -qy install curl git jq lz4 build-essential
sudo apt -qy upgrade

# Install Go
sudo rm -rf /usr/local/go
curl -Ls https://go.dev/dl/go1.21.6.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
eval $(echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/golang.sh)
eval $(echo 'export PATH=$PATH:$HOME/go/bin' | tee -a $HOME/.profile)

# Download binaries
mkdir -p $HOME/.union/cosmovisor/genesis/bin
wget -O $HOME/.union/cosmovisor/genesis/bin/uniond https://snapshots.kjnodes.com/union-testnet/uniond-genesis-linux-amd64
chmod +x $HOME/.union/cosmovisor/genesis/bin/uniond

# Create application symlinks
sudo ln -s $HOME/.union/cosmovisor/genesis $HOME/.union/cosmovisor/current -f
sudo ln -s $HOME/.union/cosmovisor/current/bin/uniond /usr/local/bin/uniond -f

# Install Cosmovisor and create a service
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.5.0

sudo tee /etc/systemd/system/union.service > /dev/null << EOF
[Unit]
Description=union node service
After=network-online.target

[Service]
User=$USER
ExecStart=$(which cosmovisor) run start --home=/home/union-testnet/.union/
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
Environment="DAEMON_HOME=$HOME/.union"
Environment="DAEMON_NAME=uniond"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:$HOME/.union/cosmovisor/current/bin"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable union.service

# Initialize the node
alias uniond='uniond --home=/home/union-testnet/.union/'

uniond config chain-id union-testnet-5
uniond config keyring-backend test
uniond config node tcp://localhost:17157

uniond init $MONIKER bn254 --chain-id union-testnet-5

curl -Ls https://snapshots.kjnodes.com/union-testnet/genesis.json > $HOME/.union/config/genesis.json
curl -Ls https://snapshots.kjnodes.com/union-testnet/addrbook.json > $HOME/.union/config/addrbook.json

sed -i -e "s|^seeds *=.*|seeds = \"3f472746f46493309650e5a033076689996c8881@union-testnet.rpc.kjnodes.com:17159\"|" $HOME/.union/config/config.toml
sed -i -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"0muno\"|" $HOME/.union/config/app.toml
sed -i -e 's|^pruning *=.*|pruning = "custom"|' -e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' -e 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|' -e 's|^pruning-interval *=.*|pruning-interval = "19"|' $HOME/.union/config/app.toml

sed -i -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:17158\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:17157\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:17160\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:17156\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":17166\"%" $HOME/.union/config/config.toml

sed -i -e "s%^address = \"tcp://0.0.0.0:1317\"%address = \"tcp://0.0.0.0:17117\"%; s%^address = \":8080\"%address = \":17180\"%; s%^address = \"0.0.0.0:9090\"%address = \"0.0.0.0:17190\"%; s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:17191\"%; s%:8545%:17145%; s%:8546%:17146%; s%:6065%:17165%" $HOME/.union/config/app.toml

# Download latest chain snapshot
curl -L https://snapshots.kjnodes.com/union-testnet/snapshot_latest.tar.lz4 | tar -Ilz4 -xf - -C $HOME/.union
[[ -f $HOME/.union/data/upgrade-info.json ]] && cp $HOME/.union/data/upgrade-info.json $HOME/.union/cosmovisor/genesis/upgrade-info.json

# Start service and check the logs
sudo systemctl start union.service && sudo journalctl -u union.service -f --no-hostname -o cat
