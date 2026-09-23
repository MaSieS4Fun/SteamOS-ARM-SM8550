AYN Thor — paquete autoinstalable (touch dual-screen)
=====================================================

Contenido
---------

  install-auto.sh     ← úsalo al preparar la imagen multi-dispositivo
  auto/               helper + unidad systemd (detección / aplicación)
  payload/            patch userspace (udev, thorch-*, autostart KDE)
  fix-thor.sh         instalación manual (opcional; pide root)

Preparar imagen
---------------

  cd Thor
  sudo ./install-auto.sh
  # o sobre rootfs montada:
  sudo ./install-auto.sh --root /mnt/armbi_root

Después ya puedes empaquetar. No hace falta copiar esta carpeta Thor/
dentro de la imagen del usuario.

Arranque del usuario
--------------------

  • AYN Thor (compatible=ayn,thor)
      → aplica el patch sin contraseña
      → espera al reinicio de armbian-resize-filesystem si hace falta
      → se desactiva para siempre

  • Cualquier otro dispositivo
      → no aplica el patch, quita restos si los hubiera, y se desactiva

  Do not enable thorch-touchscreen-setup or the KDE autostart files in the
  shared image. Only odin3-thor-autoinstall.service is enabled; it checks
  /proc/device-tree/compatible for ayn,thor before applying anything.

Requisitos del patch (solo en Thor)
-----------------------------------

  • KDE Plasma on Wayland
  • qdbus6, kscreen-doctor
