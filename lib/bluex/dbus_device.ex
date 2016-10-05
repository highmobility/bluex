defmodule Bluex.DBusDevice do
  use GenServer

  @dbus_name Application.get_env(:bluex, :dbus_name)
  @iface_dbus_name Application.get_env(:bluex, :iface_dbus_name)
  @device_dbus_name Application.get_env(:bluex, :device_dbus_name)
  @dbus_bluez_path Application.get_env(:bluex, :dbus_bluez_path)
  @dbus_type Application.get_env(:bluex, :bus_type)

  @type on_start :: {:ok, pid} | :ignore | {:error, {:already_started, pid} | term}

  @doc ~S"""
  Starts a `GenServer` process that is responsible for handling the given device.

  The module name that is passed as the first argument, should adopt the `Bluex.Device` behaviour and
  implements the callbacks.

      defmodule MyDeviceHandler do
        @behaviour Bluex.Device

        def device_connected(device, params) do
          IO.puts "device #{inspect device} is connected with params #{inspect params}"
        end

        #and the rest of the callbacks
      end

  You may use it like this:

      iex> device= %Bluex.Device{adapter: "hci1", mac_address: "00:16:3e:16:43:32", manufacturer_data: nil, rssi: "-71", uuids: []}
      iex> {:ok, pid} = Bluex.DBusDevice.start_link(MyDeviceHandler, device)
      iex> Bluex.DBusDevice.connect(device_pid)
      device %Bluex.Device{adapter: "hci1", mac_address: "00:16:3e:16:43:32", manufacturer_data: nil, rssi: "-71", uuids: []} is connected with params %{}
      :ok
  """
  @spec start_link(module, %Bluex.Device{}) :: on_start
  def start_link(module, %Bluex.Device{} = device) do
    GenServer.start_link(__MODULE__, [module, device])
  end

  @doc false
  def init([module, device]) do
    {:ok, bus} = :dbus_bus_connection.connect(@dbus_type)

    state = %{module: module, device: device, bus: bus}
    {:ok, state}
  end

  @doc """
  Connects to the device. On a successful connection, calls `device_connected` function on given module.

  On failure, throws exception!

  #TODO: handle connection failure
  """
  @spec connect(pid) :: :ok
  def connect(pid) do
    GenServer.cast(pid, :connect)
  end

  @doc "false"
  def handle_cast(:connect, state) do
    {:ok, device_proxy} = :dbus_proxy.start_link(state[:bus], @dbus_name, device_dbus_path(state[:device]))
    :ok = :dbus_proxy.call(device_proxy, @device_dbus_name, "Connect", [])
    apply(state[:module], :device_connected, [state[:device], %{}])
    {:noreply, state}
  end

  @doc """
  builds dbus path for given device
  """
  @spec device_dbus_path(%Bluex.Device{}) :: String.t
  def device_dbus_path(device) do
    mac = String.replace(device.mac_address, ":", "_")
    "#{@dbus_bluez_path}/#{device.adapter}/dev_#{mac}"
  end
end
