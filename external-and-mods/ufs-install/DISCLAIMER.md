# DISCLAIMER — USE AT YOUR OWN RISK

**Read this entire document before running any script in this folder.**

## What these tools do

The scripts in **steamos-oficial/external-and-mods/ufs-install** repartition the **internal UFS** storage on Qualcomm SM8550 handhelds (AYN Odin 2 and similar) to install **this project's SteamOS** alongside **Android**, using a **ROCKNIX ABL** dual-boot layout with **three Linux partitions** (`ROCKNIX` + `STORAGE` + `HOME`).

This is **not** a supported manufacturer procedure. It is an **experimental community tool**.

## Data loss

Running `install-masios-to-internal.sh` (unless using `--resume` / `--deploy-only` on **existing** SteamOS 3-partition layouts only):

- **Wipes Android `userdata`** — all apps, photos, game saves, accounts, and settings on internal Android storage are **permanently erased** (equivalent to repartition + factory reset).
- **May destroy other data** on internal UFS if the partition table is modified incorrectly.
- **Does not automatically back up** your microSD Linux system before copying it to UFS.

**Back up anything important before proceeding.**

## Boot failure risk

After installation or a failed attempt:

- **Android may not boot** until you perform a **factory data reset** from recovery (expected after userdata wipe).
- **Linux may not boot** from microSD or from internal UFS if the kernel, partitions, or cmdline are wrong (black screen, hang, etc.).
- **Both systems can fail** at the same time, leaving the device unusable without recovery steps (recovery mode, SD boot, ABL “Uninstall ROCKNIX”, EDL flash, etc.).

## Requirements (your responsibility)

- **ROCKNIX ABL** already installed and working (1.1.8 or compatible).
- Boot **SteamOS from microSD** (not from UFS) when running the installer.
- A **UFS-capable `/boot/KERNEL`** from this project's kernel build (`root=UUID=` + `masi.ufsroot=PARTLABEL=STORAGE`).
- Correct **ABL device profile** (“Set the Device” → your exact model).

## No warranty

THE SOFTWARE IS PROVIDED **"AS IS"**, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.

## Limitation of liability

IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE, INCLUDING BUT NOT LIMITED TO:

- Loss of data
- Bricked or unbootable devices
- Loss of Android or Linux functionality
- Hardware damage (including UFS wear or corruption in edge cases)

## Your acceptance

By running these scripts, **you confirm that**:

1. You understand the risks above.
2. You have backed up data you care about.
3. You accept **full responsibility** for the outcome.
4. You will not hold the authors liable for any damage or data loss.

If you do not agree, **do not run the installer**.

## Other UFS layouts

These scripts target the **SteamOS three-partition layout** (`ROCKNIX` + `STORAGE` + `HOME`). They will **refuse** an old two-partition `ROCKNIX` + `STORAGE` install. Use ABL **Uninstall ROCKNIX** (and remove a leftover `HOME` if needed) before a fresh install.

## License

Scripts are licensed under **GPL-2.0-or-later** (see [LICENSE](LICENSE)). The disclaimer above is additional safety information and does not replace the license terms.
