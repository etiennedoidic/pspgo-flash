# USB-C mod plan (keeps video out)

Goal: charge and transfer files over a USB-C port, while the original 28-pin multi-use port keeps working for TV out (composite/component), the cradle and the stock charger.

How: the original connector stays soldered in place. A small USB-C receptacle is wired **in parallel** to the original port's power, detect and USB data pins only. Kits that *replace* the connector remove the video pins, which is why we're not using one.

Read this whole page before buying anything. Phase 1 is a multimeter job on a cable and needs no teardown; it settles the one open question (pin 21) before you open the Go.

---

## Phase 0: before you open anything

- [ ] ARK-5 installed and permanent (CustomIPL), tested for a few days. If the mod goes wrong, you want the software side to be known-good.
- [ ] `bash pspgo-setup.sh backup --with-games`
- [ ] Battery charged to about 50% (safe to work on, enough to test with).
- [ ] Note what works today, so you can compare after: USB charge, USB Connection on the Mac, TV out (if you have the cable), cradle.

## Phase 1: learn the stock cable (no teardown)

The pin table (psdevwiki, *PSP Go Jigkick* page) names the pins but doesn't say how Sony's USB cable uses them. We need that, because the USB-C port has to look exactly like a stock cable to the Go.

Pins that matter:

| Go pin | Name | What we know |
| --- | --- | --- |
| 22 | 5V_INPUT | The only 5 V input. Charges the battery / powers the board. |
| 20 | DET_5V_CRADLE | "+5 V through 10 kΩ enables pin 22" |
| 21 | DET_USB_CABLE_CONNECTED | Name only. **Unknown how the cable drives it.** |
| 26 / 27 | USB_D+ / USB_D− | USB 2.0 data |
| 1, 7, 9, 11, 12, 25, 28 | GND | |
| 13, 16, 19 | Pr/composite, Y, Cb | Video. **Not touched.** |
| 5, 8, 10, 3 | Audio L/R, audio-out enable, mic | **Not touched.** |
| 24 | SYSCON_TOH0 | **Danger:** grounding it while off enters service mode. Keep solder and wire well away. |
| 14, 17 | Cable sense 1 / jig serial | Not touched. |

What to do:

1. Get a cheap third-party PSP Go USB cable (a few dollars) as a sacrificial one. Keep the Sony cable for later checks.
2. Carefully cut the plastic off the Go-side plug so you can see its little PCB or pin row. Number the pins from the plug's markings or count from the GND ends (1 and 28).
3. Multimeter on continuity / resistance, USB-A end to Go-side pins:
   - USB-A VBUS (pin 1 of USB-A) to Go pins 20, 21, 22. Write down the resistance to each (0 Ω = direct, ~10 kΩ = resistor, open = not connected).
   - USB-A GND to Go pins 21, 14, 15. Same.
   - USB-A D+ / D− to 26 / 27 (confirms orientation).
   - Check whether any Go pins are shorted to each other inside the plug (e.g. 21 to GND, 14 to 15).
4. Write the results in the table at the bottom of this file. Expected (a guess until measured): VBUS direct to 22, VBUS via ~10 kΩ to 20, and 21 tied to GND or to VBUS through a resistor.

If the cheap cable doesn't charge or doesn't mount, its wiring isn't a good model. Confirm it works on the Go before you cut it.

## Phase 2: buy parts

| Part | Notes | Approx. |
| --- | --- | --- |
| USB-C 2.0 receptacle, 16-pin, mid-mount or on a tiny breakout | 16-pin gives D+/D− and CC; skip 6-pin power-only ones | $1–5 |
| 2× 5.1 kΩ resistor, 0402 or 0603 | CC1, CC2 to GND, so C-to-C chargers supply 5 V | <$1 |
| 1× 10 kΩ, 0402 or 0603 | pin 20 detect (only if Phase 1 shows the cable does this) | <$1 |
| Reverse-current block on VBUS: an ideal-diode IC (e.g. TI LM66100, SC-70, 1.5 A) or a low-Vf Schottky (SS14-class or smaller) | Stops the stock charger on the old port backfeeding into whatever is on the USB-C cable. The ideal diode drops ~0.05 V; a Schottky drops ~0.3–0.4 V, which still charges but slower | $1–2 |
| Extra resistor for pin 21 | value from Phase 1 | <$1 |
| 34–36 AWG enamelled (magnet) wire | | $5 |
| Kapton tape, UV solder mask or thin hot glue | insulation and strain relief | $5 |
| Flux (no-clean gel), 0.3 mm solder | | $10 |
| Fine conical/knife tip iron (e.g. Pinecil), tweezers | | if not owned |
| Magnification: stereo microscope or a good USB scope | the connector pitch is tiny; don't do this by eye | if not owned |
| Spare PSP Go USB cable | the one you cut in Phase 1 | $3 |

Also: the microSD adapter (Natalie the Nerd, see `hardware.md`) so both mods happen in one teardown.

## Phase 3: teardown and find a spot

Follow an iFixit PSP Go teardown for the shell and ribbon cables. Disconnect the battery first and keep it disconnected while soldering.

1. Photograph every step and every ribbon before you lift it.
2. Locate the multi-use connector on the board. Look on both sides of the board for where its pins land: test pads, vias or wide traces for 22, 20, 21, 26, 27 and GND are much easier to solder to than the connector legs. Follow traces with continuity from each connector pin.
3. Choose where the USB-C port goes. Criteria: a flat spot in the bottom half's shell with ~3.5 mm height and ~9 mm width, near the connector (short D+/D− runs), not over the battery, not blocking the slider or the M2/microSD slot. Measure with calipers and test-fit the receptacle with the shell closed before soldering anything.
4. Mark the cutout. Cut slowly (drill + needle files); a slightly small hole you file to size looks far better than an oversized one.

## Phase 4: wiring

```
USB-C VBUS ──► [ideal diode / Schottky] ──┬──────────► Go pin 22 (5V_INPUT)
                                          └─[10 kΩ]──► Go pin 20 (DET_5V_CRADLE)
                              (per Phase 1) ─────────► Go pin 21 (DET_USB_CABLE_CONNECTED)
USB-C D+ ─────────────────────────────────────────────► Go pin 26
USB-C D− ─────────────────────────────────────────────► Go pin 27
USB-C GND ────────────────────────────────────────────► Go GND (pin 1/28 or a ground pad)
USB-C CC1 ──[5.1 kΩ]── GND
USB-C CC2 ──[5.1 kΩ]── GND
```

Rules:

- Mount the CC resistors and the diode on the USB-C side, so only 5–6 wires run to the Go board.
- D+ and D− the same length, twisted together, as short as you can (a few cm). The old connector's pins act as short stubs, which USB 2.0 tolerates.
- Pin 24 (service mode) sits between 23 and 25. If you solder near the connector legs, check under magnification that nothing bridges to 24 or to the video pins 13/16/19.
- Do pin 21 exactly as Phase 1 found. If the stock cable leaves it open, leave it open.
- Insulate every joint, then tack the wires down with Kapton so nothing pulls when the slider moves.

## Phase 5: bench test before closing

Battery connected, shell open, board on a non-conductive surface.

1. Resistance check before power: USB-C VBUS to GND should not be a short. Pin 22 to pin 24 should be open.
2. USB-C charger (a C-to-C phone charger): the orange charge light comes on.
3. USB-C to the Mac (C-to-C or A-to-C data cable), Settings > USB Connection: PSPGO mounts. Then `bash pspgo-setup.sh status` and copy a large file to check stability.
4. Original port with the stock cable: still charges and mounts.
5. TV out on the original port (N150/N170/N180 cable), if you have one: picture works.
6. Backfeed check: stock charger in the old port, nothing in USB-C. Measure USB-C VBUS: should be ~0 V (diode working). Only after this passes may both ports ever be plugged in at once, and even then avoid it.
7. Put the microSD in and check PSPGoSD mounts.

Then close up, and repeat 2, 3 and 5 once more.

## Order with the microSD mod

Same teardown, microSD first: it's mechanical and quick, and if anything is wrong you know it isn't the USB-C wiring. Test the card mounts, then do the USB-C work, then test both.

## Rollback

Every change is additive. Desoldering the 5–6 wires returns the Go to stock; the original connector was never removed.

## Phase 1 results (fill in)

| Measurement | Result |
| --- | --- |
| VBUS → pin 22 | |
| VBUS → pin 20 | |
| VBUS → pin 21 | |
| GND → pin 21 | |
| D+ → 26, D− → 27 | |
| Pins shorted together in the plug | |
| Free space measured (W × H × D) and location | |

Send these to Claude and the wiring above gets finalised.
