# Brave Browser + VPN aziendale: fix timeout sui siti interni

## Il problema

Dopo la connessione alla VPN aziendale (OpenVPN), Brave non riesce a raggiungere i siti interni (Bitbucket, Jira, Confluence, ecc.) mostrando:

```
ERR_TIMED_OUT
bitbucket.sanmarcoweb.com ha impiegato troppo tempo a rispondere.
```

Mentre `curl`, `ping` e altri browser funzionano normalmente.

## Causa

Brave (e tutti i browser basati su Chromium) inviano un **TLS Client Hello molto grande** rispetto ad altri client, perché includono estensioni post-quantum (ML-KEM/Kyber) e molte cipher suite.

Questo pacchetto, una volta incapsulato dal tunnel VPN, supera la MTU del percorso di rete e viene **silenziosamente scartato** (PMTU black hole). I pacchetti piccoli passano, quelli grandi no: il risultato è un timeout.

### Diagnosi con tcpdump

```
# Il segmento da 1368 byte viene ritrasmesso all'infinito, mai ricevuto dal server
11:11:35.111751 IP client > server.https: Flags [.], seq 1:1369, length 1368
11:11:35.245200 IP server > client.https: Flags [.], ack 1, sack 1 {1369:1744}  # riceve solo il frammento piccolo
11:11:35.245244 IP client > server.https: Flags [.], seq 1:1369, length 1368     # ritrasmissione
11:11:35.493413 IP client > server.https: Flags [.], seq 1:1369, length 1368     # ritrasmissione
# ... all'infinito fino al timeout
```

## Soluzione

Ridurre la MTU dell'interfaccia tunnel a 1280 byte:

```bash
sudo ip link set dev tun0 mtu 1280
```

Questo forza TCP a negoziare segmenti più piccoli che passano senza problemi attraverso il tunnel.

### Applicazione permanente

Aggiungi il comando nello script di avvio della VPN, subito dopo la connessione riuscita, oppure nel file `.ovpn`:

**Opzione A** — nello script di connessione:

```bash
# Dopo "Initialization Sequence Completed"
sudo ip link set dev tun0 mtu 1280
```

**Opzione B** — nel file `.ovpn` del client:

```
tun-mtu 1280
```

**Opzione C** — con un hook `up` di OpenVPN:

Crea `/etc/openvpn/client/fix-mtu.sh`:

```bash
#!/bin/bash
ip link set dev "$1" mtu 1280
```

```bash
chmod +x /etc/openvpn/client/fix-mtu.sh
```

Aggiungi al file `.ovpn`:

```
script-security 2
up /etc/openvpn/client/fix-mtu.sh
```

## Nota su Brave installato come Snap

Se Brave è installato come Snap, potrebbe non vedere l'interfaccia `tun0` della VPN per via della sandbox. In quel caso conviene installare la versione APT:

```bash
sudo snap remove brave
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
sudo apt update && sudo apt install -y brave-browser
```

## Colpisce anche Chrome, Edge, Vivaldi?

Si, qualsiasi browser basato su Chromium recente (v124+) che include le estensioni TLS post-quantum. Firefox non è colpito perché il suo Client Hello è più piccolo.

## Verifica

```bash
# Prima del fix
sudo tcpdump -i tun0 host <ip-server> -c 20
# Vedrai ritrasmissioni infinite del segmento grande

# Dopo il fix
curl -sI https://bitbucket.sanmarcoweb.com
# HTTP/2 302 — funziona
```
