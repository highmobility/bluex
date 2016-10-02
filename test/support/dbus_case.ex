defmodule Bluex.DBusCase do
  use ExUnit.CaseTemplate

  setup tags do
    dbus = if tags[:dbus_server] do
      Bluex.PyDBusServer.new(tags[:dbus_server])
    else
      nil
    end

    on_exit fn ->
      case dbus do
        %{dbus_server: dbus_server, dbus_daemon: dbus_daemon} ->
          send(dbus_server, {:command, :exit})
          send(dbus_daemon, {:command, :exit})
          _ -> :ok
      end
    end
    {:ok, dbus: dbus}
  end

end
