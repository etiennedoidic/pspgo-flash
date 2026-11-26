# Wi-Fi

## Now: ARK's WPA2 option

ARK added WPA2 support in 2025 ([Wololo](https://wololo.net/2025/02/14/the-20-year-old-psp-can-now-connect-to-wpa2-wifi-networks/)). Turn it on in SELECT > Custom Firmware Settings > WPA2, then Restart VSH.

Limits:
- 2.4 GHz only. Split the SSID if your router merges bands.
- WPA2 with AES-CCMP only. No TKIP, and WEP/WPA stop working while it's on.
- WPA2/WPA3 mixed mode can break DHCP. Use a static IP or a WPA2-only network.

Best setup: a 2.4 GHz guest SSID, WPA2-AES only, isolated from the main LAN. WPA3 isn't possible on this chip.

## Next: Join Wi-Fi app

The goal is modern sign-in: scan, pick, password once.

1. Type networks on the Mac in Studio's Wi-Fi tab. They're saved to `profile/wifi.json` (git-ignored) and pushed to `PSP/COMMON/pspgo/wifi.json`.
2. A homebrew app on the Go scans, lists networks by signal, joins known ones in one press, and writes them into the PSP's own connection slots so games use them too.

Prove first:
- [ ] Scan list from homebrew
- [ ] Write a connection slot (SSID, WPA2-AES key, DHCP) through the system net-config functions
- [ ] Works with ARK WPA2 mode on
