defmodule Bluex.DBusDevice do
  use GenServer

  @dbus_name Application.get_env(:bluex, :dbus_name)
  @iface_dbus_name Application.get_env(:bluex, :iface_dbus_name)
  @device_dbus_name Application.get_env(:bluex, :device_dbus_name)
  @gatt_dbus_name Application.get_env(:bluex, :gatt_dbus_name)
  @characteristic_gatt_dbus_name Application.get_env(:bluex, :characteristic_gatt_dbus_name)
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

  """
  @spec discover_service(pid, String.t) :: :ok
  def discover_service(pid, service_uuid) do
    GenServer.cast(pid, {:discover_service, service_uuid})
  end

  @spec get_service(pid, String.t) :: any
  def get_service(pid, service_uuid) do
    GenServer.call(pid, {:get_service, service_uuid})
  end

  @doc """
  Discovers characteristic with given uuid and calls 'characteristic_found` callback if the characteristic is
  found otherwise calls `characteristic_not_found` callback.

  In the first call only it traverses DBus path and finds the characteristic, on the next calls it uses list of
  cached characteristics.
  """
  @spec discover_characteristic(pid, String.t, String.t) :: any
  def discover_characteristic(pid, service_uuid, characteristic_uuid) do
    GenServer.cast(pid, {:discover_characteristic, service_uuid, characteristic_uuid})
  end

  @doc """
  Starts notification for the given characteristic.

  It calls `receive_notification` callbacks when notification is received
  """
  @spec start_notification(pid, String.t, String.t) :: any
  def start_notification(pid, service_uuid, characteristic_uuid) do
   GenServer.cast(pid, {:start_notification, service_uuid, characteristic_uuid})
  end

  @doc """
  Writes given value for the characteristic
  """
  @spec write_characteristic_value(pid, String.t, String.t, String.t) :: any
  def write_characteristic_value(pid, service_uuid, characteristic_uuid, value) do
    GenServer.call(pid, {:write_characteristic_value, service_uuid, characteristic_uuid, value})
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
                 |> Enum.map(&Path.basename/1)
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
  def handle_cast({:discover_characteristic, service_uuid, characteristic_uuid}, state) do
    characteristics = case state do
      %{services: %{^service_uuid => %{characteristics: characteristics}}} -> characteristics
        _ -> do_discover_characteristic(service_uuid, characteristic_uuid, state)
    end
    if characteristics[characteristic_uuid] do
      apply(state[:module], :characteristic_found, [state[:device], service_uuid, characteristic_uuid])
    else
      apply(state[:module], :characteristic_not_found, [state[:device], service_uuid, characteristic_uuid])
    end
    state = put_in(state[:services][service_uuid][:characteristics], characteristics)
    {:noreply, state}
  end

  @doc false
  def handle_cast({:start_notification, service_uuid, characteristic_uuid}, state) do
    characteristic = state[:services][service_uuid][:characteristics][characteristic_uuid]
    receive_notification = fn(_sender, _ifacname, "PropertiesChanged", _path, args, pid) ->
      case args do
        {@characteristic_gatt_dbus_name, %{"Notifying" => true}, _} -> :noop
        {@characteristic_gatt_dbus_name, %{"Value" => value}, _} ->
          GenServer.cast(pid, {:notification_received, service_uuid, characteristic_uuid, value})
      end
    end

    :ok = :dbus_proxy.connect_signal(characteristic[:dbus_proxy], "org.freedesktop.DBus.Properties", "PropertiesChanged", {receive_notification, self})
    {:ok, _ } = :dbus_proxy.call(characteristic[:dbus_proxy], @characteristic_gatt_dbus_name, "StartNotify", [])

    {:noreply, state}
  end

  @doc false
  def handle_cast({:notification_received, service_uuid, characteristic_uuid, value}, state) do
    apply(state[:module], :notification_received, [state[:device], service_uuid, characteristic_uuid, value])
    {:noreply, state}
  end

  @doc false
  def handle_call({:write_characteristic_value, service_uuid, characteristic_uuid, value}, _, state) do
    characteristic = state[:services][service_uuid][:characteristics][characteristic_uuid]
    :ok = :dbus_proxy.call(characteristic[:dbus_proxy], @characteristic_gatt_dbus_name, "WriteValue", [value])
    {:reply, :ok, state}
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

  defp get_proxy_and_uuid(bus, dbus_path, dbus_name) do
    {:ok, proxy} = :dbus_proxy.start_link(bus, @dbus_name, dbus_path)
    {:ok, uuid} = :dbus_proxy.call(proxy, @properties_dbus_name, "Get", [dbus_name, "UUID"])
    {proxy, uuid}
  end

  defp do_discover_characteristic(service_uuid, characteristic_uuid, state) do
    device = state[:device]
    service = state[:services][service_uuid]

    service[:dbus_proxy]
    |> :dbus_proxy.children
    |> Enum.map(&Path.basename/1)
    |> Enum.map(fn (dbus_name) ->
         dbus_path = "#{device_dbus_path(device)}/#{service[:dbus_name]}/#{dbus_name}"
         {proxy, uuid} = get_proxy_and_uuid(state[:bus], dbus_path, @characteristic_gatt_dbus_name)
         {uuid, %{dbus_name: dbus_name, dbus_proxy: proxy}}
       end)
    |> Enum.into(%{})
  end
end
