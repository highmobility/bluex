defmodule Bluex.Discovery do
  @callback device_found(%Bluex.Device{}) :: :ok | :ignore | :error
end
