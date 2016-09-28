defmodule Bluex.Device do
  defstruct mac_address: nil, manufacturer_data: nil, rssi: nil, uuids: nil, adapter: nil
  @callback device_connected(%Bluex.Device{}, any) :: any
end
