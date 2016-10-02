defmodule Bluex.PyDBusServer do
  def new(service_path) do
    dbus_pid = spawn(__MODULE__, :init_cmd, ['dbus-daemon --config-file=test/bluem-dbus/session_unix_external.conf'])
    :os.putenv('DBUS_SESSION_BUS_ADDRESS', 'unix:path=/tmp/dbus-test')
    server_pid = spawn(__MODULE__, :init_cmd, [service_path])
    :timer.sleep(1_000)
    %{dbus_server: server_pid, dbus_daemon: dbus_pid}
  end

  def init_cmd(service_path) do
    port = :erlang.open_port({:spawn, service_path}, [:exit_status])
    loop(port, service_path)
  end

  def loop(port, service_path) do
    receive do
      {:exit} ->
        :ok
      {:command, :exit} ->
        {:os_pid, pid} = :erlang.port_info(port, :os_pid)
        :erlang.port_close(port)
        :os.cmd(:io_lib.format('kill -9 ~p', [pid]))
      _ ->
        IO.puts "Looping in #{inspect __MODULE__}"
        loop(port, service_path)
    end
  end
end
