defmodule Bluex.PyDBusServer do
  def new(py_path) do
    spawn(__MODULE__, :init_cmd, [py_path])
    :timer.sleep(1_000)
  end

  def init_cmd(py_path) do
    port = :erlang.open_port({:spawn, py_path}, [:exit_status])
    loop(port, py_path)
  end

  def loop(port, py_path) do
    receive do
      {:exit} ->
        IO.inspect "exiting ...."
      {:command, :exit} ->
        IO.inspect "exiting ...."
        {:os_pid, pid} = :erlang.port_info(port, :os_pid)
        :erlang.port_close(port)
        :os.cmd(:io_lib.format('kill -9 ~p', [pid]))
      _ ->
        IO.puts "Looping in #{inspect __MODULE__}"
        loop(port, py_path)
    end
  end
end
