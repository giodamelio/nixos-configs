_: _: {
  # Add some UDEV rules so it can connect
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="0060", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="006d", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="0063", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="006c", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="008f", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="0080", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="0090", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="0086", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="0084", MODE="0660", GROUP="users"

    SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="0060", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="006d", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="0063", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="006c", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="008f", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="0080", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="0090", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="0086", MODE="0660", GROUP="users"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="0084", MODE="0660", GROUP="users"

    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="0084", MODE="0666", GROUP="users"
  '';
}
