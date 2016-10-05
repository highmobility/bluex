defmodule DBusDeviceTest do
  use Bluex.DBusCase, async: false
  @moduletag dbus_server: "test/bluem-dbus/bluem-service.py"

  alias Bluex.DBusDevice
  alias Bluex.DBusDiscovery

  @dbus_name Application.get_env(:bluex, :dbus_name)
  @mock_dbus_name "org.mock"
  @dbus_mock_path "/org/mock"
  @dbus_type Application.get_env(:bluex, :bus_type)
  @iface_dbus_name Application.get_env(:bluex, :iface_dbus_name)

  #test "call device_found callback when new device is discoverd" do
    #    {:ok, _} = DBusDiscovery.start_link(__MODULE__, [])
    #    :ok = DBusDiscovery.start_discovery(__MODULE__)
    #    :timer.sleep(100)


    #    {:ok, bus} = :dbus_bus_connection.connect(@dbus_type)
    #    {:ok, mock_controller} = :dbus_proxy.start_link(bus, @dbus_name, @dbus_mock_path)
    #    {:ok, device_dbus_path} = :dbus_proxy.call(mock_controller, @mock_dbus_name, "AddDevice", [])
    #    :timer.sleep(100)

    #    devices = DBusDiscovery.get_devices(__MODULE__)
    #    assert devices == nil
    #    refute Enum.empty?(devices)
    #    d = List.first(devices)
    #    dbus_name = String.replace(d.mac_address, ":", "_")
    #    assert device_dbus_path =~ dbus_name
    #  end


  test "start DBusDevice" do
    device_info = %Bluex.Device{adapter: "hci1", mac_address: "00:16:3e:16:43:32", manufacturer_data: nil, rssi: "-71", uuids: ""}

    {:ok, _} = DBusDevice.start_link(__MODULE__, device_info)
  end

  test "connects to a device" do

    device = add_device

    {:ok, prop} =  read_device_properties(device)
    assert %{"Connected" => false} = prop

    {:ok, pid} = DBusDevice.start_link(__MODULE__, device)
    :ok = DBusDevice.connect(pid)
    Process.sleep(100)

    {:ok, prop} =  read_device_properties(device)
    assert %{"Connected" => true} = prop
  end

  defp read_device_properties(device) do
    {:ok, bus} = :dbus_bus_connection.connect(@dbus_type)
    {:ok, device_proxy} = :dbus_proxy.start_link(bus, @dbus_name, DBusDevice.device_dbus_path(device))
    :dbus_proxy.call(device_proxy, "org.freedesktop.DBus.Properties", "GetAll", [@iface_dbus_name])
  end

  defp add_device do
    {:ok, bus} = :dbus_bus_connection.connect(@dbus_type)
    {:ok, mock_controller} = :dbus_proxy.start_link(bus, @dbus_name, @dbus_mock_path)
    {:ok, device_dbus_path} = :dbus_proxy.call(mock_controller, @mock_dbus_name, "AddDevice", [])
    %{"dbus_mac" => dbus_mac} = Regex.named_captures(~r{/hci1/dev_(?<dbus_mac>.+)}, device_dbus_path)
    Process.sleep(100)
    %Bluex.Device{adapter: "hci1", mac_address: String.replace(dbus_mac, "_", ":"), manufacturer_data: nil, rssi: "-71", uuids: ""}
  end

  def device_connected(_, _) do
    :ok
  end
end
