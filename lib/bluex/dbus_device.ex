defmodule Bluex.DBusDevice do
  use GenServer

  @dbus_name Application.get_env(:bluex, :dbus_name)
  @iface_dbus_name Application.get_env(:bluex, :iface_dbus_name)
  @device_dbus_name Application.get_env(:bluex, :device_dbus_name)
  @gatt_dbus_name Application.get_env(:bluex, :gatt_dbus_name)
  @dbus_bluez_path Application.get_env(:bluex, :dbus_bluez_path)
  @dbus_type Application.get_env(:bluex, :bus_type)
  @properties_dbus_name "org.freedesktop.DBus.Properties"

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

    state = %{module: module, device: device, bus: bus, device_proxy: nil, services: %{}}
    {:ok, state}
  end

  @doc """
  Connects to the device. On a successful connection, calls `device_connected` callback on given module.

  On failure, throws exception!

  #TODO: handle connection failure
  """
  @spec connect(pid) :: :ok
  def connect(pid) do
    GenServer.cast(pid, :connect)
  end

  @doc """
  Discovers service with given uuid and calls `service_found` callback if service is provided.

  #TODO: call service_not_found
  """
  @spec discover_service(pid, String.t) :: :ok
  def discover_service(pid, service_uuid) do
    GenServer.cast(pid, {:discover_service, service_uuid})
  end

  @spec get_service(pid, String.t) :: any
  def get_service(pid, service_uuid) do
    GenServer.call(pid, {:get_service, service_uuid})
  end

  @doc false
  def handle_cast(:connect, state) do
    {:ok, device_proxy} = :dbus_proxy.start_link(state[:bus], @dbus_name, device_dbus_path(state[:device]))
    :ok = :dbus_proxy.call(device_proxy, @device_dbus_name, "Connect", [])
    #TODO: check if there is any other way than reconnecting
    {:ok, device_proxy} = :dbus_proxy.start_link(state[:bus], @dbus_name, device_dbus_path(state[:device]))
    apply(state[:module], :device_connected, [state[:device], %{}])
    {:noreply, %{state | device_proxy: device_proxy}}
  end

  @doc false
  def handle_cast({:discover_service, service_uuid}, %{device_proxy: nil} = state) do
    apply(state[:module], :service_not_found, [state[:device], service_uuid])
    {:noreply, state}
  end

  @doc false
  def handle_cast({:discover_service, service_uuid}, state) do
    device_proxy = state[:device_proxy]
    device = state[:device]
    with {:ok, services} = :dbus_proxy.call(device_proxy, @properties_dbus_name, "Get", [@device_dbus_name, "UUIDs"]),
    true <- Enum.member?(services, service_uuid) do
      services = device_proxy
                 |> :dbus_proxy.children
                 |> Enum.map(fn (s) -> s |> String.split("/") |> Enum.at(-1) end)
                 |> Enum.map(fn (service_dbus_name) ->
                    IO.puts "path: #{device_dbus_path(device)}/#{service_dbus_name}"
                    {:ok, service} = :dbus_proxy.start_link(state[:bus], @dbus_name, "#{device_dbus_path(device)}/#{service_dbus_name}")
                    {:ok, service_uuid} = :dbus_proxy.call(service, @properties_dbus_name, "Get", [@gatt_dbus_name, "UUID"])
                    {service_uuid, %{dbus_name: service_dbus_name, dbus_proxy: service}}
                 end)
                 |> Enum.into(%{})


      apply(state[:module], :service_found, [state[:device], service_uuid])
      {:noreply, %{state| services: services}}
    else
      _ ->
      apply(state[:module], :service_not_found, [state[:device], service_uuid])
      {:noreply, state}
    end
  end

  @doc false
  def handle_call({:get_service, service_uuid}, _, state) do
    {:reply, state[:services][service_uuid], state}
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
