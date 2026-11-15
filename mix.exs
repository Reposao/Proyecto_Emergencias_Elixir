defmodule Emergencias.MixProject do
  use Mix.Project

  def project do
    [app: :emergencias, version: "1.0.0", elixir: "~> 1.14", deps: []]
  end

  def application do
    [extra_applications: [:logger, :crypto], mod: {Emergencias.Aplicacion, []}]
  end
end
