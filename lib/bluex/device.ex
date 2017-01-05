defmodule Bluex.Device do
  defstruct mac_address: nil, manufacturer_data: nil, rssi: nil, uuids: nil, adapter: nil, options: []

  @callback device_connected(%Bluex.Device{}, any) :: any
  @doc """
  When the device is disconnected this callback gets called.

  Don't heavily relay on it. Sometimes the devices are disconnected and this callback never get's called
  """
  @callback device_disconnected(%Bluex.Device{}) :: any
  @callback service_found(%Bluex.Device{}, String.t) :: any
  @callback service_not_found(%Bluex.Device{}, String.t) :: any
  @callback characteristic_found(%Bluex.Device{}, String.t, String.t) :: any
  @callback characteristic_not_found(%Bluex.Device{}, String.t, String.t) :: any
  @callback notification_received(%Bluex.Device{}, String.t, String.t, String.t) :: any
end
