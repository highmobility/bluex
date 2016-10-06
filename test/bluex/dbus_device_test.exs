defmodule DBusDeviceTest do
  use Bluex.DBusCase, async: false
  @moduletag dbus_server: "test/bluem-dbus/bluem-service.py"

  alias Bluex.DBusDevice

  @dbus_name Application.get_env(:bluex, :dbus_name)
  @mock_dbus_name "org.mock"
  @dbus_mock_path "/org/mock"
  @dbus_type Application.get_env(:bluex, :bus_type)
  @iface_dbus_name Application.get_env(:bluex, :iface_dbus_name)
  @device_dbus_name Application.get_env(:bluex, :device_dbus_name)
  @service_uuid "713d0100-503e-4c75-ba94-3148f18d941e"
  @characteristic_uuid "713d0103-503e-4c75-ba94-3148f18d941e"
  @invalid_uuid "82a1ae9e-8b02-11e6-ae22-56b6b6499611"

  test "start DBusDevice" do
    device_info = %Bluex.Device{adapter: "hci1", mac_address: "00:16:3e:16:43:32", manufacturer_data: nil, rssi: "-71", uuids: ""}

    {:ok, _} = DBusDevice.start_link(__MODULE__, device_info)
  end

  test "connect to a device" do

    device = add_device

    {:ok, prop} =  read_device_properties(device)
    assert %{"Connected" => false} = prop

    {:ok, pid} = DBusDevice.start_link(__MODULE__, device)
    :ok = DBusDevice.connect(pid)
    Process.sleep(100)

    {:ok, prop} =  read_device_properties(device)
    assert %{"Connected" => true} = prop
  end

  test "doesnt discover any service before connecting to the device" do
    device = add_device

    {:ok, pid} = DBusDevice.start_link(__MODULE__, device)
    Process.sleep(100)

    :ok = DBusDevice.discover_service(pid, @service_uuid)
    Process.sleep(100)

    refute DBusDevice.get_service(pid, @service_uuid)
  end

  test "discover_service" do
    device = add_device

    {:ok, pid} = DBusDevice.start_link(__MODULE__, device)
    :ok = DBusDevice.connect(pid)
    Process.sleep(100)

    {:ok, prop} =  read_device_properties(device)
    assert %{"Connected" => true} = prop

    :ok = DBusDevice.discover_service(pid, @service_uuid)
    Process.sleep(100)

    assert DBusDevice.get_service(pid, @service_uuid)
  end

  test "discover non existence service" do
    device = add_device

    {:ok, pid} = DBusDevice.start_link(__MODULE__, device)
    :ok = DBusDevice.connect(pid)
    Process.sleep(100)

    {:ok, prop} =  read_device_properties(device)
    assert %{"Connected" => true} = prop

    :ok = DBusDevice.discover_service(pid, @invalid_uuid)
    Process.sleep(100)

    refute DBusDevice.get_service(pid, @invalid_uuid)
  end


  test "discover characteristics" do
    device = %{add_device| options: [device_handler_pid: self]}

    {:ok, pid} = DBusDevice.start_link(__MODULE__, device)
    :ok = DBusDevice.connect(pid)
    Process.sleep(100)

    {:ok, prop} =  read_device_properties(device)
    assert %{"Connected" => true} = prop

    :ok = DBusDevice.discover_service(pid, @service_uuid)
    Process.sleep(100)

    assert DBusDevice.get_service(pid, @service_uuid)

    :ok = DBusDevice.discover_characteristic(pid, @service_uuid, @characteristic_uuid)
    Process.sleep(100)
    assert_receive({:characteristic_found, @service_uuid, @characteristic_uuid})

    :ok = DBusDevice.discover_characteristic(pid, @service_uuid, @invalid_uuid)
    Process.sleep(200)
    assert_receive({:characteristic_not_found, @service_uuid, @invalid_uuid})
  end



  def read_device_properties(device) do
    {:ok, bus} = :dbus_bus_connection.connect(@dbus_type)
    {:ok, device_proxy} = :dbus_proxy.start_link(bus, @dbus_name, DBusDevice.device_dbus_path(device))
    :dbus_proxy.call(device_proxy, "org.freedesktop.DBus.Properties", "GetAll", [@device_dbus_name])
  end

  def add_device do
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

  def service_found(_, _) do
    :ok
  end

  def service_not_found(_, _) do
    :ok
  end

  def characteristic_found(device, service_uuid, characteristic_uuid) do
    send(device.options[:device_handler_pid], {:characteristic_found, service_uuid, characteristic_uuid})
    :ok
  end

  def characteristic_not_found(device, service_uuid, characteristic_uuid) do
    send(device.options[:device_handler_pid], {:characteristic_not_found, service_uuid, characteristic_uuid})
    :ok
  end
end
