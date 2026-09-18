# Brave Browser + VPN aziendale: fix timeout sui siti interni

## Il problema

Dopo la connessione alla VPN aziendale (OpenVPN), i browser basati su Chromium (Brave, Chrome, Edge, Vivaldi, Opera) non riescono a raggiungere i siti interni mostrando:

```
ERR_TIMED_OUT
<sito-interno> ha impiegato troppo tempo a rispondere.
```

Mentre `curl`, `ping` e Firefox funzionano normalmente.

## Causa

I browser basati su Chromium recenti (v124+) inviano un **TLS Client Hello molto grande** rispetto ad altri client, perché includono estensioni post-quantum (ML-KEM/Kyber) e molte cipher suite.

Questo pacchetto, una volta incapsulato dal tunnel VPN, supera la MTU del percorso di rete e viene **silenziosamente scartato** (PMTU black hole). I pacchetti piccoli passano, quelli grandi no: il risultato è un timeout.

### Diagnosi con tcpdump

```bash
sudo tcpdump -i tun0 host <ip-server> -c 20
```

Output tipico del problema — il segmento da 1368 byte viene ritrasmesso all'infinito:

```
11:11:35.111751 IP client > server.https: Flags [.], seq 1:1369, length 1368
11:11:35.245200 IP server > client.https: Flags [.], ack 1, sack 1 {1369:1744}  # riceve solo il frammento piccolo
11:11:35.245244 IP client > server.https: Flags [.], seq 1:1369, length 1368     # ritrasmissione
11:11:35.493413 IP client > server.https: Flags [.], seq 1:1369, length 1368     # ritrasmissione
# ... all'infinito fino al timeout
```

## Soluzione

### Fix immediato (temporaneo, vale fino alla prossima riconnessione)

```bash
sudo ip link set dev tun0 mtu 1280
```

### Fix permanente (consigliato)

Aggiungi questa riga al file `.ovpn` del client:

```
tun-mtu 1280
```

Alla prossima connessione OpenVPN imposterà la MTU automaticamente.

### Alternative

**Nello script di connessione** — se usi uno script custom per avviare la VPN, aggiungi dopo la connessione riuscita:

```bash
sudo ip link set dev tun0 mtu 1280
```

**Con un hook `up` di OpenVPN** — crea uno script (es. `/etc/openvpn/client/fix-mtu.sh`):

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

## Nota su Brave installato come Snap (Ubuntu)

Se Brave è installato come Snap, potrebbe non vedere l'interfaccia `tun0` per via della sandbox. In quel caso conviene installare la versione APT:

```bash
sudo snap remove brave
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
sudo apt update && sudo apt install -y brave-browser
```

## Browser colpiti

| Browser | Colpito? | Note |
|---------|----------|------|
| Brave   | Si | Client Hello post-quantum molto grande |
| Chrome  | Si | Stesso engine di Brave |
| Edge    | Si | Chromium-based |
| Vivaldi | Si | Chromium-based |
| Opera   | Si | Chromium-based |
| Firefox | No | Client Hello più piccolo, non include ML-KEM |

## Script di utilità

Il repo include `fix-mtu.sh` per applicare il fix al volo:

```bash
sudo ./fix-mtu.sh          # default: MTU 1280 su tun0
sudo ./fix-mtu.sh 1300     # MTU custom
sudo ./fix-mtu.sh 1280 tun1  # interfaccia diversa
```

## Verifica

```bash
# Controlla la MTU attuale
ip link show tun0 | grep mtu

# Testa la connessione
curl -sI https://<sito-interno>
# HTTP/2 302 → funziona
```
