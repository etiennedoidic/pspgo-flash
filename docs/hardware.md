# Hardware mods

Do both in one teardown, after ARK is stable. Back up first (`bash pspgo-setup.sh backup`).

## microSD

[Natalie the Nerd PSP Go Micro SD](https://nataliethenerd.com/products/psp-go-micro-sd) (AUD 39). It's a spring push-in slot in the original M2 slot, with no shell trimming, tested to 128 GB. Larger cards wake from sleep more slowly.

Format as FAT32/MBR on the Mac (`diskutil eraseDisk FAT32 PSPGOSD MBRFormat /dev/diskN`), then format again on the Go so it makes its folders. Keep ARK on the Go's internal storage (ef0), so CFW boots with the card out.

## USB-C with video out kept

The Go has a single 28-pin multi-use connector that carries USB, power, audio and analog video. Kits that *replace* it lose TV out; the giltesa kit says so in its listing. So keep the original connector, and wire a USB-C receptacle in parallel to its power and USB pins only.

Pinout source: [psdevwiki: PSP Go Jigkick](https://www.psdevwiki.com/psp/Psp_Go_Jigkick).

| USB-C | Go pin | Signal | Note |
| --- | --- | --- | --- |
| VBUS | 22 | 5V input | Via a low-Vf Schottky / ideal diode (no backfeed from the stock charger) |
| VBUS via 10 kΩ | 20 | DET_5V_CRADLE | Enables the pin 22 input |
| D+ | 26 | USB D+ | Short, twisted |
| D− | 27 | USB D− | Short, twisted |
| GND | 1, 28 | GND | |
| CC1, CC2 | none | 5.1 kΩ each to GND | So C-to-C chargers supply 5 V |
| none | 21 | DET_USB_CABLE_CONNECTED | **Open:** probe with a stock cable in data mode |

The video and audio pins stay on the original port and are untouched: 13 Pr/composite, 16 Y, 19 Pb, 5/8 audio L/R, 10 audio-out enable, 14/15 cable sense. Sony's PSP-N150 (composite), N170/N180 (component) and the N340 cradle keep working. For HDMI TVs, use a component-to-HDMI scaler.

**Parts:** a 16-pin USB-C 2.0 receptacle/breakout, 2× 5.1 kΩ, 1× 10 kΩ (0402), a Schottky (SS14-class if it fits), 32–36 AWG enamelled wire, Kapton tape.

**Checks:**
- [ ] Measure free space in the shell for the second port
- [ ] Probe pin 21 during a stock-cable data transfer
- [ ] Before closing up: USB-C charge, USB-C data (the Go mounts on the Mac), AV out on the original port
- [ ] Never plug both ports in at once until the diode is verified
