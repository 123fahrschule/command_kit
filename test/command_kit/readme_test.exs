defmodule CommandKit.ReadmeTest do
  use ExUnit.Case, async: true

  test "installation dependency uses the current project version" do
    version = Mix.Project.config() |> Keyword.fetch!(:version)
    readme = File.read!("README.md")

    assert readme =~ ~s({:command_kit, "~> #{version}"})
  end
end
