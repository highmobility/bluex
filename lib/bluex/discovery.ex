defmodule Bluex.Discovery do
  @callback device_found(%Bluex.Device{}) :: :ok | :ignore | :error
end

defmodule Bluex.DiscoveryFilter do
  @moduledoc """
      * transport, type of scan to run:
        * :auto  - interleaved scan
        * :bredr - br/edr inquiry
        * :le  - le only scan, default value
      * uuids: filtered service UUIDs
      * adapters: list of the adapters to run discovery on.
          If it's not provided the discovery runs on all the adapters.
  """
  defstruct transport: :le, uuids: [], adapters: []
end
