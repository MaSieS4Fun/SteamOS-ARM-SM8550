#!/usr/bin/env python3
import pathlib, re, sys
boot, uuid = pathlib.Path(sys.argv[1]), sys.argv[2]
found = False
for cfg in (boot / 'EFI/BOOT/grub.cfg', boot / 'boot/grub/grub.cfg'):
    if not cfg.is_file():
        continue
    text = cfg.read_text(encoding='utf-8', errors='replace')
    ntext, n = re.subn(r'root=UUID=[0-9a-fA-F-]{36}', f'root=UUID={uuid}', text)
    if n:
        cfg.write_text(ntext, encoding='utf-8')
        print(f'patched {cfg} ({n})')
        found = True
    else:
        raise SystemExit(f'no root=UUID= in {cfg}')
if not found:
    raise SystemExit('no grub.cfg found on ESP')
