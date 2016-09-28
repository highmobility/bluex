defmodule Bluex.DBusCase do
  use ExUnit.CaseTemplate

  setup tags do
    dbus_server = if tags[:dbus_server] do
      Bluex.PyDBusServer.new(tags[:dbus_server])
    else
      nil
    end
    {:ok, dbus_server: dbus_server}
  end

end
