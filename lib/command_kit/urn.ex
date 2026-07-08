defmodule CommandKit.URN do
  @moduledoc """
  Builds URNs used for causation and correlation ids.

  A URN has the form `"<source>:<name>:<id>"`, where `source` is the
  application-wide prefix configured on the command base module (for example
  `"de.123fahrschule:absence"`), `name` is a kebab-case command or event
  name, and `id` is the message identity.

      CommandKit.URN.generate("de.123fahrschule:absence", "record-payout", uuid)
      #=> "de.123fahrschule:absence:record-payout:" <> uuid
  """

  @spec generate(String.t(), String.t(), term()) :: String.t()
  def generate(source, name, id) when is_binary(source) and is_binary(name) do
    source <> ":" <> name <> ":" <> to_string(id)
  end
end
