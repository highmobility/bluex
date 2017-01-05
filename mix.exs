defmodule Bluex.Mixfile do
  use Mix.Project

  def project do
    [app: :bluex,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     elixirc_paths: elixirc_paths(Mix.env),
     package: package,
     description: description,
     deps: deps(),
     dialyzer: [plt_add_deps: :transitive]]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  defp deps do
    [
      {:dbus, github: "slashmili/erlang-dbus", branch: "unix-socket", optional: true},
      {:dialyxir, "~> 0.3.5", only: :dev},
      {:ex_doc, "~> 0.14.2", only: :dev},
      {:earmark, "~> 1.0", only: :dev},
    ]
  end

  def package do
    [maintainers: ["Milad Rastian"],
     licenses: ["MIT"],
     links: %{github: "https://github.com/highmobility/bluex"},
     files: ~w(lib config)]
  end

  def description do
    """
    Bluex is an abstraction layer on top of the DBus/Bluez.
    """
  end
end
