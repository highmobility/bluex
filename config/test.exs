use Mix.Config

config :bluex,
  bus_type: :session,
  dbus_name: "org.bluem",
  iface_dbus_name: "org.bluem.Adapter1",
  device_dbus_name: "org.bluem.Device1",
  gatt_dbus_name: "org.bluem.GattService1",
  characteristic_gatt_dbus_name: "org.bluem.GattCharacteristic1",
  dbus_bluez_path: "/org/bluem"
