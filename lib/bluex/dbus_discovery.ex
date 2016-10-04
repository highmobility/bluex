defmodule Bluex.DBusDiscovery do
  @callback device_found(%Bluex.Device{}) :: :ok | :ignore | :error

  @dbus_name Application.get_env(:bluex, :dbus_name)
  @iface_dbus_name Application.get_env(:bluex, :iface_dbus_name)
  @device_dbus_name Application.get_env(:bluex, :device_dbus_name)
  @dbus_bluez_path Application.get_env(:bluex, :dbus_bluez_path)
  @dbus_type Application.get_env(:bluex, :bus_type)

  use GenServer

  @doc """
  Gets list of adapters
  """
  def get_adapters(pid) do
    GenServer.call(pid, :get_adapters)
  end

  @doc """
  Gets list of devices
  """
  def get_devices(pid) do
    GenServer.call(pid, :get_devices)
  end

  @doc false
  def device_found(pid, device) do
    GenServer.cast(pid, {:device_found, device})
  end

  def start_link(module, opts \\ []) do
    GenServer.start_link(__MODULE__, [module, opts], name: module)
  end

  @doc """
  Starts Bluetooth discovery
  """
  def start_discovery(pid) do
    GenServer.cast(pid, :start_discovery)
  end

  @doc false
  def init([module, opts]) do
    {:ok, bus} = :dbus_bus_connection.connect(@dbus_type)
    {:ok, adapter_manager} = :dbus_proxy.start_link(bus, @dbus_name, @dbus_bluez_path)
    {:ok, bluez_manager} = :dbus_proxy.start_link(bus, @dbus_name, "/")

    {:ok, %{bus: bus, adapter_manager: adapter_manager, devices: [], adapters: [], bluez_manager: bluez_manager, module: module}}
  end

  @doc false
  def handle_call(:get_adapters, _, state) do
    {:reply, state[:adapters], state}
  end

  @doc false
  def handle_call(:get_devices, _, state) do
    {:reply, state[:devices], state}
  end

  @doc false
  def handle_info({:dbus_signal, _}, state) do
    GenServer.cast(state[:module], :get_adapters)
    {:noreply, state}
  end

  @doc false
  def handle_cast(:get_adapters, state) do
    adapters = :dbus_proxy.children(state[:adapter_manager])
    |> Stream.map(fn (adapter) -> adapter |> String.split("/") |> Enum.at(-1) end)
    |> Stream.map(fn (adapter) ->
      bluez_path = "#{@dbus_bluez_path}/#{adapter}"
      {:ok, adapter_proxy} = :dbus_proxy.start_link(state[:bus], @dbus_name, bluez_path)
      :dbus_proxy.has_interface(adapter_proxy, @iface_dbus_name)
      {adapter, %{path: bluez_path, proxy: adapter_proxy}}
    end)
    |> Stream.filter(fn ({_, %{proxy: adapter_proxy}}) ->
      #TODO close invalid adapter
      :dbus_proxy.has_interface(adapter_proxy, @iface_dbus_name)
    end)
    |> Enum.into(%{})

    state = Map.put(state, :adapters, adapters)
    {:noreply, state}
  end

  #path: "/", args: {"/org/bluez/hci1/dev_C0_CB_38_EB_74_13", %{"org.bluez.Device1" => %{"Adapter" => "/org/bluez/hci1", "Address" => "C0:CB:38:EB:74:13", "Alias" => "ubuntu-0", "Blocked" => false, "Class" => 7078144, "Connected" => false, "Icon" => "computer", "LegacyPairing" => false, "Name" => "ubuntu-0", "Paired" => false, "RSSI" => -71, "Trusted" => false, "TxPower" => 0, "UUIDs" => ["0000112d-0000-1000-8000-00805f9b34fb", "00001112-0000-1000-8000-00805f9b34fb", "0000111f-0000-1000-8000-00805f9b34fb", "0000111e-0000-1000-8000-00805f9b34fb", "0000110c-0000-1000-8000-00805f9b34fb", "0000110e-0000-1000-8000-00805f9b34fb", "0000110a-0000-1000-8000-00805f9b34fb", "0000110b-0000-1000-8000-00805f9b34fb"]}, "org.freedesktop.DBus.Introspectable" => %{}, "org.freedesktop.DBus.Properties" => %{}}}

  @doc false
  def handle_cast(:start_discovery, state) do
    #TODO: ???get list of devices now and call the device_found callback before leaving this function
    add_interface = fn(sender, "org.freedesktop.DBus.ObjectManager", "InterfacesAdded", path, args, pid) ->
      case args do
        {interface_bluez_path, %{@device_dbus_name => device_details}} ->
          device = %Bluex.Device{mac_address: device_details["Address"], manufacturer_data: device_details["ManufacturerData"], rssi: device_details["RSSI"], uuids: device_details["UUIDs"], adapter: "hci1"}
          Bluex.DBusDiscovery.device_found(pid, device)
        _ -> :ok
      end
    end
    :dbus_proxy.connect_signal(state[:bluez_manager],
                               "org.freedesktop.DBus.ObjectManager",
                               "InterfacesAdded",
                               {add_interface, self})
    :dbus_proxy.children(state[:bluez_manager])
    state[:adapters]
    |> Enum.each(fn ({_, %{proxy: adapter_proxy}}) ->
      #TODO: to filter_services
      #:ok = :dbus_proxy.call(adapter_proxy, @iface_dbus_name, "SetDiscoveryFilter", [%{"UUIDs" => ["5842aec9-3aee-a150-5a8c-159d686d6363"]}])
      :ok = :dbus_proxy.call(adapter_proxy, @iface_dbus_name, "StartDiscovery", [])
    end)
    {:noreply, state}
  end

  @doc false
  def handle_cast({:device_found, device}, state) do
    state = case apply(state[:module], :device_found, [device]) do
      :ok ->
        Map.put(state, :devices, [device])
      _ ->
        state
    end
    {:noreply, state}
  end

  defmacro __using__(opts) do
    quote [unquote: false, location: :keep] do
      @behaviour Bluex.DBusDiscovery
      import Bluex.DBusDiscovery
      use GenServer

      @doc false
      def start_link do
        Bluex.DBusDiscovery.start_link(__MODULE__, [])
      end

      @doc """
      Starts Bluetooth discovery
      """
      def start_discovery do
        Bluex.DBusDiscovery.start_discovery(__MODULE__)
      end
    end
  end
end
