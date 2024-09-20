#!/bin/bash

# Default variables
function="install"

# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }

while test $# -gt 0; do
    case "$1" in
        -in|--install)
            function="install"
            shift
            ;;
        -up|--update)
            function="update"
            shift
            ;;
        -un|--uninstall)
            function="uninstall"
            shift
            ;;
        *|--)
            break
            ;;
    esac
done

wallet() {
    if [ -f $HOME/popm-address.json ]; then
        echo "File popm-address.json already exists. Skipping wallet generation."
        return 0
    else
        if [ ! -d $HOME/hemi ]; then
            echo "Directory $HOME/hemi does not exist. Cannot generate wallet."
            return 1
        fi

        cd $HOME/hemi || { echo "Failed to change directory to $HOME/hemi."; return 1; }
        ./keygen -secp256k1 -json -net="testnet" > ~/popm-address.json

        PRIVATE_KEY=$(jq -r '.private_key' $HOME/popm-address.json)
        if [ -n "$PRIVATE_KEY" ]; then
            echo "export POPM_BTC_PRIVKEY=$PRIVATE_KEY" >> ~/.bashrc
            echo 'export POPM_STATIC_FEE=50' >> ~/.bashrc
            echo 'export POPM_BFG_URL=wss://testnet.rpc.hemi.network/v1/ws/public' >> ~/.bashrc
        else
            echo "Failed to extract PRIVATE_KEY. Check popm-address.json."
            return 1
        fi

        # Reload bashrc to apply new variables
        source ~/.bashrc

        # Restart the hemi service
        sudo systemctl restart hemi.service
    fi
}

install() {
    sudo apt update && sudo apt upgrade -y
    if [ -d $HOME/hemi ]; then
        echo "Directory $HOME/hemi/ already exists. Skipping installation."
        return 0
    else
        heminetwork_version=$(wget -qO- https://api.github.com/repos/hemilabs/heminetwork/releases/latest | jq -r ".tag_name")
        wget -qO $HOME/hemi.tar.gz "https://github.com/hemilabs/heminetwork/releases/download/${heminetwork_version}/heminetwork_${heminetwork_version}_linux_amd64.tar.gz"
        
        if [ $(wc -c < "$HOME/hemi.tar.gz") -ge 1000 ]; then
            tar -xvf $HOME/hemi.tar.gz -C $HOME
            rm -rf $HOME/hemi.tar.gz

            # Rename the extracted directory
            mv $HOME/heminetwork_${heminetwork_version}_linux_amd64/ $HOME/hemi/
            chmod +x $HOME/hemi/popmd
            
            # Create the systemd service file
            sudo tee /etc/systemd/system/hemi.service > /dev/null <<EOF
[Unit]
Description=Heminetwork Node
After=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/hemi/
ExecStart=$HOME/hemi/popmd
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

            sudo systemctl enable hemi.service
            sudo systemctl daemon-reload

            # Call the wallet function to generate and set up keys
            wallet
        else
            rm -rf $HOME/hemi.tar.gz
            echo "Archive is not downloaded or too small!"
            return 1
        fi
    fi
}

update() {
    sudo apt update && sudo apt upgrade -y
    
    if [ -d "$HOME/hemi" ]; then
        echo "Directory $HOME/hemi exists. Checking for updates..."
        heminetwork_version=$(wget -qO- https://api.github.com/repos/hemilabs/heminetwork/releases/latest | jq -r ".tag_name")
        wget -qO $HOME/hemi.tar.gz "https://github.com/hemilabs/heminetwork/releases/download/${heminetwork_version}/heminetwork_${heminetwork_version}_linux_amd64.tar.gz"
        
        if [ $(wc -c < "$HOME/hemi.tar.gz") -ge 1000 ]; then
            tar -xvf $HOME/hemi.tar.gz -C $HOME
            rm -rf $HOME/hemi.tar.gz

            mv $HOME/heminetwork_${heminetwork_version}_linux_amd64/ $HOME/hemi/
            chmod +x $HOME/hemi/popmd

            sudo systemctl restart hemi.service
            echo "Heminetwork updated successfully to version ${heminetwork_version}."
        else
            echo "Failed to download or archive is too small. No update applied."
            rm -rf $HOME/hemi.tar.gz
            return 1
        fi
    else
        echo "Directory $HOME/hemi does not exist. Installing..."
        install
    fi
}

uninstall() {
    if [ ! -d "$HOME/hemi" ]; then
        echo "Directory $HOME/hemi does not exist. Nothing to uninstall."
        return 0
    fi

    read -r -p "Wipe all DATA? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            sudo systemctl stop hemi.service  
            sudo systemctl disable hemi.service
            sudo systemctl daemon-reload

            mkdir -p $HOME/backuphemi

            if [ -f "$HOME/popm-address.json" ]; then
                mv "$HOME/popm-address.json" "$HOME/backuphemi/"
            fi

            rm -rf "$HOME/hemi"

            sed -i '/POPM_BTC_PRIVKEY/d' ~/.bashrc
            sed -i '/POPM_STATIC_FEE/d' ~/.bashrc
            sed -i '/POPM_BFG_URL/d' ~/.bashrc

            source ~/.bashrc

            echo "Heminetwork successfully uninstalled and data wiped."
            ;;
        *)
            echo "Canceled"
            return 0
            ;;
    esac
}

# Install necessary packages and execute the function
sudo apt install wget jq -y &>/dev/null
cd
$function
