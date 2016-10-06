defmodule Bluex.Device do
  defstruct mac_address: nil, manufacturer_data: nil, rssi: nil, uuids: nil, adapter: nil, options: []

  @callback device_connected(%Bluex.Device{}, any) :: any
  @callback service_found(%Bluex.Device{}, String.t) :: any
  @callback service_not_found(%Bluex.Device{}, String.t) :: any
  @callback characteristic_found(%Bluex.Device{}, String.t, String.t) :: any
  @callback characteristic_not_found(%Bluex.Device{}, String.t, String.t) :: any
end
