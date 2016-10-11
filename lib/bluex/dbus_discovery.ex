defmodule Bluex.DBusDiscovery do
  @dbus_name Application.get_env(:bluex, :dbus_name)
  @iface_dbus_name Application.get_env(:bluex, :iface_dbus_name)
  @device_dbus_name Application.get_env(:bluex, :device_dbus_name)
  @dbus_bluez_path Application.get_env(:bluex, :dbus_bluez_path)
  @dbus_type Application.get_env(:bluex, :bus_type)

  use GenServer

  @doc """
  Gets list of adapters
  """
  @spec get_adapters(pid) :: list(String.t)
  def get_adapters(pid) do
    GenServer.call(pid, :get_adapters)
  end

  @doc """
  Gets list of devices
  """
  @spec get_devices(pid) :: list(%Bluex.Device{})
  def get_devices(pid) do
    GenServer.call(pid, :get_devices)
  end

  @doc false
  @spec device_found(pid, %Bluex.Device{}) :: :ok
  def device_found(pid, device) do
    GenServer.cast(pid, {:device_found, device})
  end

  def start_link(module, opts \\ []) do
    GenServer.start_link(__MODULE__, [module, opts], name: module)
  end

  @doc """
  Starts Bluetooth discovery
  """
  @spec start_discovery(pid) :: :ok
  def start_discovery(pid) do
    GenServer.cast(pid, :start_discovery)
  end

  @doc """
  Starts Bluetooth discovery
  """
  @spec stop_discovery(pid) :: :ok
  def stop_discovery(pid) do
    GenServer.cast(pid, :stop_discovery)
  end


  @doc false
  def init([module, _opts]) do
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
    |> Stream.map(&Path.basename/1)
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

  @doc false
  def handle_cast(:stop_discovery, state) do
    state[:adapters]
    |> Enum.each(fn ({_, %{proxy: adapter_proxy}}) ->
      :dbus_proxy.call(adapter_proxy, @iface_dbus_name, "StopDiscovery", [])
    end)
    {:noreply, state}
  end

  @doc false
  def handle_cast(:start_discovery, state) do
    #TODO: ???get list of devices now and call the device_found callback before leaving this function
    add_interface = fn(_sender, "org.freedesktop.DBus.ObjectManager", "InterfacesAdded", _path, args, pid) ->
      case args do
        {_interface_bluez_path, %{@device_dbus_name => device_details}} ->
          device = %Bluex.Device{}
                   |> Map.put(:mac_address, device_details["Address"])
                   |> Map.put(:manufacturer_data, device_details["ManufacturerData"])
                   |> Map.put(:rssi, device_details["RSSI"])
                   |> Map.put(:uuids, device_details["UUIDs"])
                   |> Map.put(:adapter, Path.basename(device_details["Adapter"]))
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

  defmacro __using__(_opts) do
    quote [unquote: false, location: :keep] do
      @behaviour Bluex.Discovery
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

      def stop_discovery do
        Bluex.DBusDiscovery.stop_discovery(__MODULE__)
      end
    end
  end
end
