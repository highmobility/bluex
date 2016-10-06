# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config


config :bluex,
  bus_type: :system,
  dbus_name: "org.bluez",
  iface_dbus_name: "org.bluez.Adapter1",
  device_dbus_name: "org.bluez.Device1",
  gatt_dbus_name: "org.bluez.GattService1",
  characteristic_gatt_dbus_name: "org.bluez.GattCharacteristic1",
  dbus_bluez_path: "/org/bluez"

import_config "#{Mix.env}.exs"
